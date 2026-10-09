import Foundation
import Observation
import OSLog
import Sparkle

/// Automatische Updates über Sparkle (docs/SECURE-DESIGN.md E9, Muster Kalli).
///
/// **Das ist der einzige Netzwerkzugriff von Seam.** Abgefragt wird
/// `raw.githubusercontent.com` (Feed), geladen von `github.com`. Dabei gehen wie bei
/// jedem HTTP-Aufruf IP-Adresse und implizit die installierte Version mit. Keine
/// Kennung, kein Tracking.
///
/// Sparkle prüft vor dem Ersetzen die **EdDSA-Signatur** des Archivs gegen
/// `SUPublicEDKey` (Pflicht vor dem Entpacken: `SUVerifyUpdateBeforeExtraction`) und
/// danach die **Code-Signatur** des Bundles. `SUEnableAutomaticChecks` ist bewusst nicht
/// gesetzt: Sparkle fragt beim ersten Mal, ob es automatisch suchen darf.
///
/// Anders als Kalli schickt Seam **keine Mitteilung**: Seam hat keine
/// Mitteilungs-Erlaubnis und soll für ein Update keine erfragen. Findet eine
/// automatische Prüfung etwas, steht es im Menü („Update x.y verfügbar …“). Ein Fenster
/// hinter anderen Apps (Sparkles Standard bei Apps ohne Dock-Symbol) gibt es nicht.
@MainActor
@Observable
final class Updater {

    /// Version eines Updates, das eine automatische Prüfung gefunden hat.
    private(set) var pendingVersion: String?
    /// Spiegel von Sparkles `canCheckForUpdates` per KVO. Vorher eine berechnete Eigenschaft:
    /// SwiftUI beobachtet Sparkle nicht, das Menü zeigte den Wert vom Aufbauzeitpunkt
    /// (Michael, 09.10.: „Nach Updates suchen“ in 0.1.0 dauerhaft ausgegraut).
    private(set) var canCheck = false
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "update")

    private let controller: SPUStandardUpdaterController
    /// Sparkle hält den Delegate nur schwach.
    private let reminder: MenuReminder

    init() {
        let r = MenuReminder()
        reminder = r
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: r)
        r.onChange = { [weak self] version in self?.pendingVersion = version }
        // Sparkle ändert `canCheckForUpdates` auf dem Hauptthread (SPUUpdater ist eine Hauptthread-
        // Klasse), KVO meldet auf demselben Thread. Daher zugesichert statt per Task verschoben
        // (Compiler-Warnung beim Code-Audit-Fix 09.10.).
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                let value = updater.canCheckForUpdates
                self?.canCheck = value
                Self.log.notice("Nach Updates suchen: \(value ? "möglich" : "gesperrt", privacy: .public) (Sitzung läuft: \(updater.sessionInProgress, privacy: .public), automatisch prüfen/laden: \(updater.automaticallyChecksForUpdates, privacy: .public)/\(updater.automaticallyDownloadsUpdates, privacy: .public))")
            }
        }
    }

    /// Auf Anforderung. Sparkle zeigt selbst an, was es gefunden hat, auch „kein Update“.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

}

/// Entscheidet nur, WIE ein gefundenes Update gezeigt wird. Signaturprüfung, Feed und
/// Installation bleiben Sparkles Standardweg.
@MainActor
private final class MenuReminder: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var onChange: ((String?) -> Void)?
    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "update")

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Nie selbst ein Fenster für eine AUTOMATISCHE Prüfung: Ohne Nutzeraktion käme es
    /// hinter anderen Apps zu liegen (gemessen an Tippi/Kalli, 2026-09-24).
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        Self.log.notice("Update \(update.displayVersionString, privacy: .public): Hinweis im Menü")
        onChange?(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { onChange?(nil) }
    func standardUserDriverWillFinishUpdateSession() { onChange?(nil) }
}
