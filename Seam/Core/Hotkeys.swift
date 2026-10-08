import Carbon
import OSLog

/// Globale Tastenkürzel über `RegisterEventHotKey` (docs/SECURE-DESIGN.md E1).
///
/// macOS liefert Seam damit **nur** die registrierten Kombinationen, keine
/// anderen Tasten. Kein Event-Tap, keine Freigabe „Eingabeüberwachung“.
@MainActor
final class Hotkeys {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "kuerzel")
    private static let signature: OSType = 0x5345_414D   // 'SEAM'

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var byID: [UInt32: KeyCombo] = [:]
    var onPress: ((KeyCombo) -> Void)?

    /// Kürzel, die macOS nicht registrieren ließ (z. B. von einer anderen App belegt).
    private(set) var failed: [KeyCombo] = []

    func register(_ keys: Set<KeyCombo>) {
        unregister()
        installHandlerIfNeeded()
        for (i, key) in keys.sorted(by: { ($0.modifiers, $0.keyCode) < ($1.modifiers, $1.keyCode) }).enumerated() {
            let id = UInt32(i + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key.keyCode, key.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                byID[id] = key
            } else {
                failed.append(key)
            }
        }
        // Messpunkt: still nicht registrierte Kürzel sehen aus wie „Seam reagiert nicht“.
        Self.log.notice("Kürzel registriert: \(self.refs.count, privacy: .public), fehlgeschlagen: \(self.failed.map(\.label).joined(separator: " "), privacy: .public)")
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        byID = [:]
        failed = []
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard let userData else { return noErr }
            let id = hk.id
            // Carbon liefert auf dem Hauptthread.
            MainActor.assumeIsolated {
                let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
                if let key = hotkeys.byID[id] { hotkeys.onPress?(key) }
            }
            return noErr
        }, 1, &spec, me, &handler)
    }
}
