import AppKit
import OSLog
import SwiftUI

@main
struct SeamApp: App {

    @State private var engine = Engine()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(engine)
                .environment(engine.prefs)
        } label: {
            let symbol = engine.isTrusted ? "rectangle.split.2x1" : "rectangle.split.2x1.slash"
            // E14: selbst vergebener Name des aktuellen Space neben dem Symbol.
            let name = engine.spaces.menuBarTitle(engine.prefs)
            let icon = SpaceWatcher.showsIcon(title: name, hideWhenNamed: engine.prefs.hideIconWithSpaceName,
                                              trusted: engine.isTrusted)
            if let name, icon {
                Label(name, systemImage: symbol).labelStyle(.titleAndIcon)
            } else if let name {
                Text(name)
            } else {
                Image(systemName: symbol)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Seam – Einstellungen", id: "einstellungen") {
            SettingsView()
                .environment(engine)
                .environment(engine.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)

        // Hilfe, Änderungen, Fremdcode-Lizenzen (Sparkle verlangt, dass sein Lizenztext
        // mit ausgeliefert und erreichbar ist).
        Window("Seam", id: "hilfe") {
            HelpView()
                .padding(16)
                .frame(width: 520)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)

        Window("Spaces benennen", id: "spaces") {
            SpaceNamesView()
                .environment(engine)
                .environment(engine.prefs)
                .padding(16)
                .frame(width: 380)
                .background(MoveToActiveSpace())
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
    /// Spaces und ihre Namen (E14). Läuft auch ohne Bedienungshilfen-Freigabe.
    let spaces = SpaceWatcher()
    private(set) var isTrusted = AXAccess.isTrusted
    private(set) var failedShortcuts: [KeyCombo] = []
    /// Updates (Sparkle). Im Testlauf nicht gestartet: kein Netz aus dem Test-Host.
    private(set) var updater: Updater?

    @ObservationIgnored private lazy var actions = WindowActions(prefs: prefs)
    @ObservationIgnored private lazy var drag = DragController(prefs: prefs, actions: actions)
    @ObservationIgnored private lazy var pairs = PairKeeper(prefs: prefs, writer: actions.writer)
    @ObservationIgnored private lazy var dimmer = Dimmer(prefs: prefs)
    @ObservationIgnored private let hotkeys = Hotkeys()
    @ObservationIgnored private var trustTimer: Timer?
    /// Prüft auch nach dem Start weiter, ob die Freigabe noch da ist (Code-Audit 09.10., C8/R9:
    /// entzogen im laufenden Betrieb zeigte Seam weiter „freigegeben“ und tat still nichts).
    @ObservationIgnored private var trustWatch: Timer?
    @ObservationIgnored private var running = false

    /// Im Testlauf startet die App als Test-Host. Dann weder Freigabe-Dialog noch
    /// Kürzel noch Maus-Beobachter: Die Tests prüfen reine Rechenlogik.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        FamilyTheme.app = .seam
        if !FamilyTheme.registerFonts() {
            // Code-Audit 09.10., C12: vorher verworfen, SwiftUI fiel still auf die Systemschrift zurück.
            Self.log.error("Schrift Plus Jakarta Sans nicht registriert, Systemschrift im Einsatz")
        }
        guard !Self.isRunningTests else { return }
        AXAccess.setGlobalTimeout()
        updater = Updater()
        spaces.start()
        trackTargetApp()
        #if DEBUG
        PreviewRenderer.runIfRequested(engine: self)
        #endif
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

    /// Alle 5 s: Freigabe noch da? `AXIsProcessTrusted` ist ein lokaler Aufruf ohne IPC in andere
    /// Apps. Fehlt sie, wird das Symbol durchgestrichen und das Popover zeigt den Hinweis.
    private func watchTrust() {
        guard trustWatch == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = AXAccess.isTrusted
                if now != self.isTrusted {
                    self.isTrusted = now
                    Self.log.notice("Bedienungshilfen \(now ? "wieder freigegeben" : "entzogen", privacy: .public)")
                }
            }
        }
        timer.tolerance = 1
        trustWatch = timer
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
        watchTrust()
    }

    /// Letzte vordere App, die nicht Seam ist. Öffnet man das Popover, wird Seam selbst aktiv;
    /// gemeint ist aber das Fenster der App davor (0.4).
    @ObservationIgnored private(set) var lastTargetPID: pid_t?
    @ObservationIgnored private var activationTokens: [NSObjectProtocol] = []

    private func trackTargetApp() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != own { lastTargetPID = front }
        let nc = NSWorkspace.shared.notificationCenter
        activationTokens.append(nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != own else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.lastTargetPID = pid }
        })
        // Code-Audit 09.10. (S6): beendete App vergessen, damit eine später wiederverwendete
        // Prozessnummer nie eine andere App trifft.
        activationTokens.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { if self?.lastTargetPID == pid { self?.lastTargetPID = nil } }
        })
    }

    /// Befehl aus dem Popover. Gemessen 09.10.: Solange das Popover offen ist, bleibt laut
    /// `NSWorkspace` die App davor vorn, für die Bedienungshilfen hat aber das Popover den
    /// Fokus — die systemweite Fokus-Abfrage fand deshalb „kein verwaltbares Fenster“. Darum
    /// immer gezielt das Fokusfenster der vorderen fremden App (bzw. der zuletzt vorderen).
    /// Tastenkürzel laufen über `Hotkeys` direkt in `WindowActions` und sind nicht betroffen.
    ///
    /// Übergeben wird der Befehl, nicht das Kürzel (Code-Audit 09.10., C1). Seam aktiviert die
    /// Ziel-App nur, wenn sie nicht ohnehin vorn ist (SECURE-DESIGN E15).
    func perform(_ cmd: Command) {
        guard running else {
            Self.log.notice("\(cmd.rawValue, privacy: .public): Seam läuft nicht (Freigabe fehlt)")
            return
        }
        guard let pid = targetPID, let w = AXAccess.focusedWindow(of: pid), w.isManageable else {
            Self.log.notice("\(cmd.rawValue, privacy: .public): kein verwaltbares Fenster bei der Ziel-App")
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        actions.perform(cmd, on: w)
    }

    /// Vordere fremde App, sonst die zuletzt vordere.
    private var targetPID: pid_t? {
        let own = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return (front != own ? front : nil) ?? lastTargetPID
    }

    /// Fürs Popover beim Öffnen: Name der Ziel-App und Ausrichtung ihres Bildschirms, damit die
    /// Kacheln zur Ausrichtung passen (C1). Bewusst eine Abfrage, keine beobachtete Eigenschaft:
    /// sonst rechnete SwiftUI das Popover bei jedem App-Wechsel neu.
    func targetInfo() -> (name: String?, orientation: Orientation?) {
        guard let pid = targetPID else { return (nil, nil) }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName
        let o = AXAccess.focusedWindow(of: pid)?.frame.flatMap { Screens.best(for: $0)?.orientation }
        return (name, o)
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

/// Fenster (Einstellungen, Hilfe, Spaces benennen) kommen in den Space, in dem man gerade ist.
/// Ohne das holt macOS beim zweiten Öffnen den Space nach vorn, in dem das Fenster zuerst
/// aufging — Michael 09.10.: „Die Einstellungen müssen im selben Space angezeigt werden!“
struct MoveToActiveSpace: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
    }
}
