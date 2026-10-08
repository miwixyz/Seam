import AppKit
import Observation
import OSLog

/// Beobachtet Space-Wechsel und liefert Liste + aktuellen Space (docs/SECURE-DESIGN.md E14).
/// Läuft unabhängig von der Bedienungshilfen-Freigabe: Spaces lesen braucht sie nicht.
@MainActor
@Observable
final class SpaceWatcher {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "spaces")

    /// Alle Spaces, in Mission-Control-Reihenfolge. Leer = Schnittstelle liefert nichts.
    private(set) var spaces: [SpaceInfo] = []
    private(set) var current: SpaceInfo?
    var available: Bool { !spaces.isEmpty }

    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var reportedMissing = false

    func start() {
        guard tokens.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // Bildschirm des aktiven Fensters kann wechseln (mehrere Bildschirme mit eigenen Spaces).
        tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        guard let list = SpaceReader.read() else {
            if !reportedMissing {
                reportedMissing = true
                Self.log.notice("Spaces: Schnittstelle liefert nichts, Funktion ausgeblendet")
            }
            if !spaces.isEmpty { spaces = [] }
            current = nil
            return
        }
        reportedMissing = false
        if list != spaces { spaces = list }
        let now = SpaceNames.current(list, display: SpaceReader.displayIdentifier(of: NSScreen.main))
        if now != current {
            current = now
            Self.log.notice("Space gewechselt: \(now.map { $0.isFullScreen ? "Vollbild" : "Nr. \($0.number)" } ?? "–", privacy: .public) von \(list.count)")
        }
    }

    /// Text neben dem Symbol in der Menüleiste: nur ein selbst vergebener Name, sonst nichts.
    func menuBarTitle(_ prefs: Preferences) -> String? {
        guard prefs.showSpaceName, let c = current, let n = prefs.spaceNames[c.key], !n.isEmpty else { return nil }
        return n
    }
}
