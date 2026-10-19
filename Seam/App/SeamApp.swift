import AppKit
import OSLog
import SwiftUI

@main
struct SeamApp: App {

    /// Links (E16): Der Empfänger muss vor dem Ende des App-Starts stehen, sonst geht der Link
    /// verloren, der Seam gestartet hat.
    @NSApplicationDelegateAdaptor private var linkDelegate: LinkAppDelegate
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
            Group {
                if let name, icon {
                    Label(name, systemImage: symbol).labelStyle(.titleAndIcon)
                } else if let name {
                    Text(name)
                } else {
                    Image(systemName: symbol)
                }
            }
            // Neu aufbauen, wenn sich der Inhalt ändert: sonst behielt das Menüleisten-Symbol
            // die Breite des ersten Namens, ein längerer lief über den Rand (Michael 09.10.:
            // „Produktivität“ 77 pt Text in 59 pt Symbol, Nachbar zeichnete darüber).
            .id("\(name ?? "")|\(icon)|\(symbol)")
            #if DEBUG
            .background(DebugWindowOpener())
            #endif
        }
        .menuBarExtraStyle(.window)

        Window("Seam – Einstellungen", id: "einstellungen") {
            SettingsView()
                .environment(engine)
                .environment(engine.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Gemessen 10.10.: Eine HTML-Datei (E16) öffnete sonst die Einstellungen — SwiftUI
        // zeigt bei Ereignissen von außen ein Fenster. Seams Fenster öffnet nur der Nutzer.
        .handlesExternalEvents(matching: [])

        // Hilfe, Änderungen, Fremdcode-Lizenzen (Sparkle verlangt, dass sein Lizenztext
        // mit ausgeliefert und erreichbar ist).
        Window("Seam", id: "hilfe") {
            HelpView()
                .padding(16)
                .frame(width: 520)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Gemessen 10.10.: Eine HTML-Datei (E16) öffnete sonst die Einstellungen — SwiftUI
        // zeigt bei Ereignissen von außen ein Fenster. Seams Fenster öffnet nur der Nutzer.
        .handlesExternalEvents(matching: [])

        Window("Link-Regeln", id: "linkregeln") {
            // 0.5.3: hier stand noch `.frame(width: 560)` aus 0.5.0 und schnitt die 620 pt breite
            // Ansicht links und rechts ab (gemessen bei Michael: Fenster 560 × 584). Größe und
            // Rand legt jetzt allein `LinkRulesWindow` fest — dieselbe Hülle rendert die Vorschau.
            LinkRulesWindow(router: LinkRouter.shared)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Gemessen 10.10.: Eine HTML-Datei (E16) öffnete sonst die Einstellungen — SwiftUI
        // zeigt bei Ereignissen von außen ein Fenster. Seams Fenster öffnet nur der Nutzer.
        .handlesExternalEvents(matching: [])

        Window("Abdunkeln", id: "abdunkeln") {
            DimSettingsWindow()
                .environment(engine)
                .environment(engine.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Gemessen 10.10.: Eine HTML-Datei (E16) öffnete sonst die Einstellungen — SwiftUI
        // zeigt bei Ereignissen von außen ein Fenster. Seams Fenster öffnet nur der Nutzer.
        .handlesExternalEvents(matching: [])

        Window("Layout bearbeiten", id: "layout") {
            DeskLayoutWindow()
                .environment(engine)
                .environment(engine.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Wie die anderen Fenster: öffnet nur der Nutzer, nie ein Ereignis von außen (E16).
        .handlesExternalEvents(matching: [])

        Window("Spaces benennen", id: "spaces") {
            SpaceNamesView()
                .environment(engine)
                .environment(engine.prefs)
                .padding(16)
                .frame(width: 380)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
        // Gemessen 10.10.: Eine HTML-Datei (E16) öffnete sonst die Einstellungen — SwiftUI
        // zeigt bei Ereignissen von außen ein Fenster. Seams Fenster öffnet nur der Nutzer.
        .handlesExternalEvents(matching: [])
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

    // MARK: Layouts pro Space (E17)

    /// ⌃⌥⌘L: Schreibtische aufräumen. In Seam frei (⌃⌘L ist „Linkes Drittel“).
    static let tidyKey = KeyCombo(keyCode: 37, modifiers: KeyCombo.ctrlOptCmd)
    @ObservationIgnored private lazy var desks = DeskRunner(prefs: prefs)
    @ObservationIgnored private let deskHUD = NoticeHUD()
    @ObservationIgnored private var autoTidyTask: Task<Void, Never>?
    @ObservationIgnored private var afterFixTask: Task<Void, Never>?
    @ObservationIgnored private var screenToken: NSObjectProtocol?
    /// rafter-code-review 19.10., Fund 3: Nachräumen nach dem Zurückziehen höchstens alle 30 s —
    /// ein flatternder Bildschirm darf Maus und Tastatur nicht in Dauerschleife übernehmen.
    @ObservationIgnored private var lastAfterFix: Date?
    /// Fürs Popover: Lauf aktiv, letzte Meldung, Schreibtische am falschen Platz.
    private(set) var deskRunning = false
    private(set) var deskMessage: String?
    private(set) var deskIssues: [DeskIssue] = []

    /// Im Testlauf startet die App als Test-Host. Dann weder Freigabe-Dialog noch
    /// Kürzel noch Maus-Beobachter: Die Tests prüfen reine Rechenlogik.
    static var isPreview: Bool {
        #if DEBUG
        PreviewRenderer.isRequested
        #else
        false
        #endif
    }

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
        // Im Vorschau-Modus (DEBUG, gleiche Bundle-ID wie die installierte App) keine Namen
        // übernehmen — sonst schriebe die Vorschau in Michaels echte Einstellungen (code-audit 19.10.).
        if !Self.isPreview {
            spaces.onChange = { [weak self, prefs] list in
                let n = prefs.adoptSpaceNames(list)
                if n > 0 { Self.log.notice("Space-Namen vom Platz übernommen: \(n)") }
                self?.spacesChanged()
            }
        }
        spaces.start()
        trackTargetApp()
        #if DEBUG
        PreviewRenderer.runIfRequested(engine: self)
        if PreviewRenderer.isRequested { return }
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
            if key == Self.tidyKey { self.tidyUp(automatic: false); return }
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
        // E17b: nach Anmeldung und nach jeder Bildschirmänderung, sobald die Bildschirme ruhig sind.
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAutoTidy() }
        }
        scheduleAutoTidy()
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
            hotkeys.register(Layout.allKeys.union([Self.tidyKey]))
            failedShortcuts = hotkeys.failed
        } else {
            hotkeys.unregister()
            failedShortcuts = []
        }
    }

    /// Popover/Menü: jetzige Anordnung als Layout dieser Bildschirm-Kombination speichern.
    func saveDeskLayout() {
        let screens = DeskLayouts.liveScreens()
        let spaces = SpaceReader.read() ?? []
        let layout = DeskLayouts.capture(windows: DeskLayouts.liveWindows(), spaces: spaces, names: prefs.spaceNames,
                                         screens: screens, ownBundleID: Bundle.main.bundleIdentifier)
        // Nichts erfasst (z. B. Spaces kurz nicht lesbar) → altes Layout behalten. Ein leeres Layout
        // hieße sonst „löschen“ (code-audit 19.10.).
        guard !layout.entries.isEmpty else { showDesk(DeskMessages.saved(apps: 0)); return }
        prefs.rememberSpaceSlots(spaces)
        let ok = prefs.saveDeskLayout(layout, for: screens.combinationKey)
        deskIssues = []
        Self.log.notice("Layout gespeichert: \(layout.entries.count) Apps")
        showDesk(ok ? DeskMessages.saved(apps: layout.entries.count)
                    : "Layout nicht gespeichert: Seam merkt sich höchstens 20 "
                        + "Bildschirm-Kombinationen.\n→ ZU TUN: in den Einstellungen unter „Layouts“ das Layout löschen und neu speichern.")
    }

    /// Popover, Kürzel ⌃⌥⌘L, Automatik.
    func tidyUp(automatic: Bool) {
        guard running else { return }
        if let block = desks.run(automatic: automatic, done: { [weak self] in self?.deskFinished($0) }) {
            if let text = DeskMessages.blocked(block, automatic: automatic) { showDesk(text) }
            return
        }
        deskRunning = true
        // Steht, bis das Ergebnis kommt (`deskFinished` blendet es aus) — auch wenn ein Lauf länger dauert.
        showDesk(DeskMessages.running, for: .seconds(600))
    }

    /// Popover beim Öffnen: Weicht die Anordnung vom Layout ab? nil = kein Layout.
    func deskDeviates() -> Bool? {
        desks.currentPlan()?.deviates
    }

    private func deskFinished(_ r: DeskRunResult) {
        deskRunning = false
        deskIssues = r.issues
        let names = deskNames
        let text = DeskMessages.issues(r.issues, names: names, autoTidy: prefs.deskAutoTidy) ?? DeskMessages.result(r, names: names)
        deskHUD.hide()
        showDesk(text, for: r.issues.isEmpty ? .seconds(8) : .seconds(20))
    }

    private func showDesk(_ text: String, for duration: Duration = .seconds(8)) {
        deskMessage = text
        guard let screen = Screens.all().first else { return }
        deskHUD.show(text, at: CGPoint(x: screen.visible.midX, y: screen.visible.midY), within: screen.visible, for: duration)
    }

    private var deskNames: DeskMessages.Names {
        DeskMessages.Names(
            app: { DeskLayouts.appName($0) },
            display: { id in
                NSScreen.screens.first { SpaceReader.displayIdentifier(of: $0) == id }?.localizedName ?? "dem anderen Bildschirm"
            })
    }

    /// Bildschirme 10 s ruhig, dann automatisch aufräumen. Jede weitere Änderung startet die Wartezeit neu.
    private func scheduleAutoTidy() {
        guard prefs.deskAutoTidy else { return }
        autoTidyTask?.cancel()
        autoTidyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.tidyUp(automatic: true)
        }
    }

    /// Spaces geändert: Hat der Nutzer die gemeldeten Schreibtische in Mission Control
    /// zurückgezogen, räumt Seam 4 s nach der letzten Änderung den Rest auf — nur mit
    /// eingeschalteter Automatik (code-audit 19.10.: sonst wirkte der Notschalter hier nicht) und
    /// in eigener Aufgabe, damit ein gleichzeitiger Bildschirmwechsel nicht verloren geht.
    private func spacesChanged() {
        guard running, prefs.deskAutoTidy, !deskIssues.isEmpty, !deskRunning else { return }
        afterFixTask?.cancel()
        afterFixTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            let issues = self.desks.currentPlan()?.issues ?? []
            self.deskIssues = issues
            guard issues.isEmpty else { return }
            if let last = self.lastAfterFix, Date().timeIntervalSince(last) < 30 { return }
            self.lastAfterFix = Date()
            self.tidyUp(automatic: false)
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

    /// Abdunkeln je Bildschirm, App, Space, Stärke (0.6): nur neu einsortieren und zeichnen,
    /// nicht neu aufbauen (kein Blitzen).
    func applyDimDetails() {
        guard running else { return }
        dimmer.refresh()
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
