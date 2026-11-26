import AppKit
import OSLog

/// Ton der App-Familie beim Einrasten (0,18 s, dumpfer Schlag + Einrast-Schnapp, `seam.caf`).
/// Einmal geladen, bei jedem Einrasten von vorn gespielt. Fehlt die Datei oder spielt sie
/// nicht, steht es im Protokoll (Kategorie „ton“) – nie stumm.
@MainActor
final class SnapSound {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "ton")
    private lazy var sound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "seam", withExtension: "caf") else {
            Self.log.notice("Einrast-Ton: seam.caf fehlt im Bündel")
            return nil
        }
        guard let s = NSSound(contentsOf: url, byReference: true) else {
            Self.log.notice("Einrast-Ton: seam.caf nicht lesbar")
            return nil
        }
        return s
    }()

    func play() {
        guard let sound else { return }
        sound.stop()   // schnell hintereinander eingerastet: neu starten statt verschlucken
        if !sound.play() { Self.log.notice("Einrast-Ton: Wiedergabe fehlgeschlagen") }
    }
}
