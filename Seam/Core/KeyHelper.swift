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

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
