import AppKit
import OSLog

/// „Spaces in fester Reihenfolge halten“ (E21g): macOS ordnet Spaces sonst nach der letzten Nutzung
/// neu (`com.apple.dock` / `mru-spaces`). Einziger Schreibzugriff auf eine fremde Einstellung.
/// Nur auf Klick des Nutzers; der vorherige Wert wird gemerkt und beim Ausschalten zurückgeschrieben.
@MainActor
enum SpaceOrder {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "spaces")
    private static let domain = "com.apple.dock" as CFString
    private static let key = "mru-spaces" as CFString

    /// Was macOS gerade gespeichert hat: true/false oder nil = nicht gesetzt (Standard: neu ordnen).
    static func storedValue() -> Bool? {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.boolValue
    }

    /// Feste Reihenfolge ist wirksam, wenn `mru-spaces` ausdrücklich false ist.
    static var isFixed: Bool { storedValue() == false }

    /// Einschalten: alten Wert zurückgeben (zum Merken), `false` schreiben, Dock neu starten.
    static func fix() -> Bool? {
        let previous = storedValue()
        write(false)
        return previous
    }

    /// Ausschalten: den gemerkten Wert wiederherstellen (nil = Eintrag entfernen).
    static func restore(_ previous: Bool?) {
        write(previous)
    }

    private static func write(_ value: Bool?) {
        CFPreferencesSetAppValue(key, value.map { $0 as CFBoolean }, domain)
        let ok = CFPreferencesAppSynchronize(domain)
        log.notice("mru-spaces → \(value.map { String($0) } ?? "entfernt", privacy: .public), gespeichert: \(ok, privacy: .public)")
        restartDock()
    }

    /// Das Dock liest die Einstellung nur beim Start. macOS startet es nach dem Beenden selbst neu.
    private static func restartDock() {
        guard let pid = AXAccess.dockProcess(), let dock = NSRunningApplication(processIdentifier: pid) else { return }
        let asked = dock.terminate()
        // Das Dock reagiert nicht immer auf die höfliche Bitte (wie `killall Dock`, das ein Signal schickt).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let forced = !dock.isTerminated
            if forced { dock.forceTerminate() }
            log.notice("Dock neu gestartet (Bitte angenommen: \(asked, privacy: .public), erzwungen: \(forced, privacy: .public))")
        }
    }
}
