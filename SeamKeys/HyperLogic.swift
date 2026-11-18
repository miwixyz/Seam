import CoreGraphics
import Foundation

/// Zustand und Entscheidung des Taps — reine Logik, getestet (HyperKeyTests).
struct TapState {
    /// F18: darauf legt die macOS-Tastenbelegung die Feststelltaste (E22c).
    static let f18: Int64 = 79
    let flags: CGEventFlags
    let escapeOnTap: Bool
    var down = false
    var used = false

    enum Action: Equatable { case pass, swallow, swallowAndEscape, addFlags }

    mutating func handle(type: CGEventType, keyCode: Int64) -> Action {
        if keyCode == TapState.f18 && (type == .keyDown || type == .keyUp) {
            if type == .keyDown {
                if !down { down = true; used = false }      // Wiederholung beim Halten ignorieren
                return .swallow
            }
            let wasTap = down && !used
            down = false
            return wasTap && escapeOnTap ? .swallowAndEscape : .swallow
        }
        guard down else { return .pass }
        if type == .keyDown { used = true }
        return .addFlags
    }
}

/// Einstellungen aus Seams Domain (E22d), nur gültige Werte (STRIDE T).
enum HyperSettings {
    static func load(suite: String) -> (flags: CGEventFlags, escapeOnTap: Bool) {
        let d = UserDefaults(suiteName: suite)
        let raw = d?.object(forKey: "hyperKeyModifiers") as? Int ?? 15
        return (flags(raw), d?.string(forKey: "hyperKeyTap") == "escape")
    }

    /// Bitmaske 1 = ⇧, 2 = ⌃, 4 = ⌥, 8 = ⌘. Ungültig oder leer → alle vier.
    static func flags(_ raw: Int) -> CGEventFlags {
        let m = (1...15).contains(raw) ? raw : 15
        var f: CGEventFlags = []
        if m & 1 != 0 { f.insert(.maskShift) }
        if m & 2 != 0 { f.insert(.maskControl) }
        if m & 4 != 0 { f.insert(.maskAlternate) }
        if m & 8 != 0 { f.insert(.maskCommand) }
        return f
    }
}
