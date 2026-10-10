import AppKit

/// Nimmt Links (Apple Event „GetURL“) und HTML-Dateien an und reicht sie an den `LinkRouter`
/// (SECURE-DESIGN E16). Hat sonst keine Aufgabe und kennt die Fenster-Bausteine nicht.
final class LinkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Im Testlauf (App als Test-Host) keinen Empfänger anmelden.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        LinkRouter.shared.installHandler()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        LinkRouter.shared.openFiles(urls)
    }
}
