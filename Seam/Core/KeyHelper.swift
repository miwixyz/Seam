import AppKit
import OSLog

/// Startet und beendet den Helfer SeamKeys (Supertaste, E22). Seam selbst hat keinen Event-Tap.
@MainActor
enum KeyHelper {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "supertaste")
    static let bundleID = "dev.mwlr.seam.keys"

    /// Nur der eingebettete Helfer aus dem eigenen Paket, nie ein anderer Ort.
    static var url: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SeamKeys.app") }

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Einstellungen gelten ab dem nächsten Start des Helfers: beenden, dann (falls an) neu starten.
    static func apply(enabled: Bool) {
        stop()
        guard enabled else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("SeamKeys fehlt im Paket")
            return
        }
        Task { @MainActor in
            // Der alte Helfer räumt beim Beenden die Belegung ab; erst danach den neuen starten.
            for _ in 0..<20 where isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            config.createsNewApplicationInstance = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                log.notice("SeamKeys gestartet")
            } catch {
                log.error("SeamKeys nicht gestartet: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func stop() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
    }

    /// E22c: Wurde SeamKeys früher ohne Aufräumen beendet (Absturz, ältere Version), bliebe die
    /// Feststelltaste auf F18 bis zum Neustart. Beim Start mit ausgeschalteter Supertaste abräumen,
    /// aber nur, wenn genau Seams Belegung gesetzt ist. Fester Befehl, keine Shell.
    static func clearOrphanedMapping() {
        guard !isRunning, let current = hidutil(["property", "--get", "UserKeyMapping"]),
              isOnlyOurMapping(current) else { return }
        _ = hidutil(["property", "--set", #"{"UserKeyMapping":[]}"#])
        log.notice("Verwaiste Belegung der Feststelltaste entfernt")
    }

    /// true = mindestens eine Belegung gesetzt, und alle sind Feststelltaste → F18.
    nonisolated static func isOnlyOurMapping(_ output: String) -> Bool {
        let src = output.matches(of: #/HIDKeyboardModifierMappingSrc = ([0-9]+);/#).map { String($0.output.1) }
        let dst = output.matches(of: #/HIDKeyboardModifierMappingDst = ([0-9]+);/#).map { String($0.output.1) }
        return !src.isEmpty && src.count == dst.count
            && src.allSatisfy { $0 == "30064771129" } && dst.allSatisfy { $0 == "30064771181" }
    }

    private static func hidutil(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()   // vor dem Warten lesen, sonst kann die Pipe volllaufen
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                log.error("hidutil Exit \(p.terminationStatus, privacy: .public)")
                return nil
            }
            return String(bytes: data, encoding: .utf8)
        } catch {
            log.error("hidutil nicht startbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
