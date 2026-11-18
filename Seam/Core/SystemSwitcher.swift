import Foundation
import OSLog

// Nicht dokumentierte Funktionen (E21i), nur in dieser Datei. Gemessen 18.11. unter macOS 27.2:
// wirken, Rückgabe 0 = ok, und die Abschaltung überlebt das Programmende.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func cgsSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32
@_silgen_name("CGSIsSymbolicHotKeyEnabled")
private func cgsIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

/// macOS' eigenen Umschalter (⌘Tab, ⇧⌘Tab, nächstes Fenster) ab- und wieder einschalten (E21i).
/// Nur diese drei Kürzel, nur ein/aus.
enum SystemSwitcher {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "umschalter")
    /// 1 = ⌘Tab, 2 = ⇧⌘Tab, 6 = nächstes Fenster der App (⌘` bzw. ⌘< auf deutscher Tastatur).
    static let hotKeys: [Int32] = [1, 2, 6]

    /// true = alle drei sind bei macOS gerade aus.
    static var isOff: Bool { hotKeys.allSatisfy { !cgsIsSymbolicHotKeyEnabled($0) } }

    /// Schaltet um und prüft danach den echten Zustand (Regel 7). Rückgabe: Zustand stimmt.
    @discardableResult
    static func setOff(_ off: Bool) -> Bool {
        let codes = hotKeys.map { cgsSetSymbolicHotKeyEnabled($0, !off) }
        let ok = hotKeys.allSatisfy { cgsIsSymbolicHotKeyEnabled($0) == !off }
        log.notice("macOS-Umschalter \(off ? "aus" : "an", privacy: .public): Rückgaben \(codes.map(String.init).joined(separator: ","), privacy: .public), geprüft: \(ok, privacy: .public)")
        return ok
    }
}
