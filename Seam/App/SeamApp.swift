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

        // Hilfe, Änderungen, Fremdcode-Lizenzen (Sparkle verlangt, dass sein Lizenztext
        // mit ausgeliefert und erreichbar ist).
        Window("Seam", id: "hilfe") {
            HelpView()
                .padding(16)
                .frame(width: 520)
        }
        .windowResizability(.contentSize)
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
    /// Updates (Sparkle). Im Testlauf nicht gestartet: kein Netz aus dem Test-Host.
    private(set) var updater: Updater?

    @ObservationIgnored private lazy var actions = WindowActions(prefs: prefs)
    @ObservationIgnored private lazy var drag = DragController(prefs: prefs, actions: actions)
    @ObservationIgnored private lazy var pairs = PairKeeper(prefs: prefs)
    @ObservationIgnored private lazy var dimmer = Dimmer(prefs: prefs)
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
        updater = Updater()
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
        actions.onSplit = { [weak self] a, b in self?.pairs.pair(a, b) }
        pairs.start()
        dimmer.partnerOf = { [weak self] w in self?.pairs.partner(of: w) }
        pairs.onRaised = { [weak self] in self?.dimmer.refresh() }
        dimmer.apply()
    }

    /// Befehl aus dem Menü: wirkt wie das Kürzel auf das vorderste Fenster.
    func perform(_ key: KeyCombo) {
        guard running else { return }
        actions.perform(key)
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

    /// Schalter „Geteilte Fenster bleiben zusammen“ (E12): aus = Paare und Beobachter weg.
    func applyPairSetting() {
        guard running else { return }
        pairs.applySetting()
    }

    /// Schalter/Stärke „Hintergrund abdunkeln“ (E13).
    func applyDimSetting() {
        guard running else { return }
        dimmer.apply()
    }

    func applyDimStrength() {
        guard running else { return }
        dimmer.strengthChanged()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
