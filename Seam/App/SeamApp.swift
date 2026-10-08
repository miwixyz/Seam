import AppKit
import OSLog
import SwiftUI

@main
struct SeamApp: App {

    @State private var engine = Engine()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(engine)
                .environment(engine.prefs)
        } label: {
            Image(systemName: engine.isTrusted ? "rectangle.split.2x1" : "rectangle.split.2x1.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Hält alles zusammen und startet die Beobachter erst, wenn die
/// Bedienungshilfen-Freigabe da ist.
@MainActor
@Observable
final class Engine {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "start")

    let prefs = Preferences()
    private(set) var isTrusted = AXAccess.isTrusted
    private(set) var failedShortcuts: [KeyCombo] = []

    @ObservationIgnored private lazy var actions = WindowActions(prefs: prefs)
    @ObservationIgnored private lazy var drag = DragController(prefs: prefs, actions: actions)
    @ObservationIgnored private let hotkeys = Hotkeys()
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var running = false

    /// Im Testlauf startet die App als Test-Host. Dann weder Freigabe-Dialog noch
    /// Kürzel noch Maus-Beobachter: Die Tests prüfen reine Rechenlogik.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        guard !Self.isRunningTests else { return }
        Task { @MainActor in self.boot() }
    }

    private func boot() {
        if AXAccess.isTrusted {
            startEngines()
        } else {
            AXAccess.requestTrust()
            // Freigabe kommt aus den Systemeinstellungen, ohne Benachrichtigung an uns.
            // Also nachsehen, bis sie da ist, dann ohne Neustart loslegen.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTrust() }
            }
        }
        Self.log.notice("Start: Bedienungshilfen \(AXAccess.isTrusted ? "freigegeben" : "fehlen", privacy: .public)")
    }

    private func checkTrust() {
        isTrusted = AXAccess.isTrusted
        guard isTrusted else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        startEngines()
    }

    private func startEngines() {
        guard !running else { return }
        running = true
        isTrusted = true
        hotkeys.onPress = { [weak self] key in
            guard let self, self.prefs.shortcuts else { return }
            self.actions.perform(key)
        }
        applyShortcutSetting()
        drag.start()
    }

    /// Kürzel an/aus: abmelden statt nur ignorieren, damit andere Apps sie nutzen können.
    func applyShortcutSetting() {
        guard running else { return }
        if prefs.shortcuts {
            hotkeys.register(Layout.allKeys)
            failedShortcuts = hotkeys.failed
        } else {
            hotkeys.unregister()
            failedShortcuts = []
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
