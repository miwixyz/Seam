import Carbon
import Foundation

/// Welcher Buchstabe auf einer Taste steht, nach der eingestellten Tastaturbelegung.
enum KeyboardLayout {

    /// Großbuchstabe für einen Tastencode ohne Zusatztasten, oder nil.
    /// Die Eingabequellen-Funktionen gelten nur auf dem Hauptthread als sicher;
    /// anderswo (z. B. Protokollzeilen) greift der Rückfall des Aufrufers.
    static func character(for keyCode: UInt32) -> String? {
        guard Thread.isMainThread,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length).uppercased()
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
        }
    }
}
