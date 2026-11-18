import AppKit
import OSLog

/// SeamKeys: Supertaste als eigener Prozess (docs/SECURE-DESIGN.md E22). Kein Fenster, kein Dock-Symbol.
/// Enthält nur Tastatur-Code — keine Fenster, keine Bildschirmaufnahme, kein Netz (Lint `seamkeys_nur_tastatur`).
@main
@MainActor
enum SeamKeysMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let keys = HyperKey()
        keys.start()
        withExtendedLifetime(keys) { app.run() }
    }
}

@MainActor
final class HyperKey {

    private static let log = Logger(subsystem: "dev.mwlr.seam.keys", category: "supertaste")
    nonisolated static let seamID = "dev.mwlr.seam"
    /// F18: darauf legt die macOS-Tastenbelegung die Feststelltaste (E22c).
    nonisolated static let escape: CGKeyCode = 53

    private var tap: CFMachPort?
    private var retry: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var termSource: DispatchSourceSignal?
    fileprivate var state: TapState = {
        let s = HyperSettings.load(suite: HyperKey.seamID)
        return TapState(flags: s.flags, escapeOnTap: s.escapeOnTap)
    }()

    func start() {
        // E22d: nur zusammen mit Seam.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.seamID).isEmpty else {
            Self.log.notice("Seam läuft nicht, beende")
            exit(0)
        }
        // Von Hand gestartet, Supertaste in Seam aber aus (Audit 18.11.): nichts belegen, sofort beenden.
        guard HyperSettings.isEnabled(suite: Self.seamID) else {
            Self.log.notice("Supertaste in Seam ausgeschaltet, beende")
            exit(0)
        }
        let nc = NSWorkspace.shared.notificationCenter
        tokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.seamID else { return }
            MainActor.assumeIsolated { self.quit("Seam beendet") }
        })
        // Nach dem Aufwachen kann macOS die Belegung neuer Geräte verlieren → neu setzen.
        tokens.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if self.tap != nil { KeyMapping.set(capsToF18: true) } }
        })
        // Seam beendet den Helfer per `terminate()` (Beenden-Anfrage). Das läuft über NSApplication und
        // erreicht weder den SIGTERM-Weg noch die Beende-Meldung → hier aufräumen (code-audit 18.11.).
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.cleanUp("Beenden-Anfrage") }
        })
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { self.quit("SIGTERM") } }
        source.resume()
        termSource = source

        // Belegung erst, wenn der Tap steht (installTap): ohne Freigabe bliebe die Feststelltaste sonst
        // auf F18 ohne Abnehmer, also tot (code-audit 18.11.).
        Self.reportTap(active: false)
        Self.log.notice("Einstellungen: Sondertasten \(self.state.flags.rawValue, privacy: .public), Escape bei kurzem Druck: \(self.state.escapeOnTap, privacy: .public)")
        if !installTap() {
            // E22e: Freigabe fehlt. Einmal anfragen, dann nachsehen, bis sie da ist.
            let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            Self.log.notice("Tap nicht möglich. Bedienungshilfen: \(AXIsProcessTrustedWithOptions(opts), privacy: .public), Eingabeüberwachung: \(CGPreflightListenEventAccess(), privacy: .public)")
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    if self.installTap() { self.retry?.invalidate(); self.retry = nil }
                }
            }
        }
    }

    private func quit(_ why: String) {
        Self.cleanUp(why)
        exit(0)
    }

    private static func cleanUp(_ why: String) {
        reportTap(active: false)
        KeyMapping.set(capsToF18: false)
        log.notice("Beendet (\(why, privacy: .public)), Belegung entfernt")
    }

    /// Aktiver Tap auf Tasten-Ereignisse. Rückgabe false = macOS verweigert (Freigabe fehlt).
    private func installTap() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: hyperCallback, userInfo: me) else {
            return false
        }
        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        KeyMapping.set(capsToF18: true)
        Self.reportTap(active: true)
        Self.log.notice("Tap aktiv")
        return true
    }

    /// Status für Seams Einstellungen, nur in der EIGENEN Domain: Prozessnummer bei aktivem Tap, sonst 0.
    private static func reportTap(active: Bool) {
        let d = UserDefaults.standard
        d.set(active ? Int(ProcessInfo.processInfo.processIdentifier) : 0, forKey: HyperSettings.tapPIDKey)
        d.synchronize()
    }

    fileprivate func reenable() {
        // Während der Abschaltung kann das Loslassen der Taste verloren gegangen sein. Ohne Zurücksetzen
        // bekäme danach JEDE Taste die Sondertasten dazu (code-audit 18.11.).
        state.down = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        Self.log.notice("Tap von macOS abgeschaltet, wieder an, Zustand zurückgesetzt")
    }
}

private func hyperCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<HyperKey>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { keys.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let (action, flags) = MainActor.assumeIsolated { (keys.state.handle(type: type, keyCode: code), keys.state.flags) }
    switch action {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .swallowAndEscape:
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: HyperKey.escape, keyDown: down)?.post(tap: .cgSessionEventTap)
        }
        return nil
    case .addFlags:
        event.flags.formUnion(flags)
        return Unmanaged.passUnretained(event)
    }
}

/// macOS-Tastenbelegung: Feststelltaste → F18 (E22c). Fester Befehl, kein Nutzer-Text, keine Shell.
enum KeyMapping {
    private static let log = Logger(subsystem: "dev.mwlr.seam.keys", category: "belegung")
    static let capsToF18 = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    static let empty = #"{"UserKeyMapping":[]}"#

    static func set(capsToF18 on: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", on ? capsToF18 : empty]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            log.notice("Belegung \(on ? "gesetzt" : "entfernt", privacy: .public): Exit \(p.terminationStatus, privacy: .public)")
        } catch {
            log.error("hidutil nicht startbar: \(error.localizedDescription, privacy: .public)")
        }
    }
}
