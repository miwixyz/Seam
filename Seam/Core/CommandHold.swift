import AppKit
import OSLog

/// Kürzel-Blatt (docs/SECURE-DESIGN.md E24a): erkennt „⌘ allein gehalten“ und zeigt dann die Kürzel der
/// vordersten App.
///
/// **Einzige Datei mit einem `flagsChanged`-Monitor** (Ausnahme in der Lint-Regel
/// `keine_synthetischen_ereignisse`). Der Handler liest ausschließlich `modifierFlags`, nie Zeichen
/// oder Tastennummern; die Regel `commandhold_nur_flags` verbietet den Zugriff darauf. Der Monitor ist
/// passiv: Er kann nichts schlucken oder verändern. Die Maus beobachtet derselbe passive Weg wie in E2.
@MainActor
final class CommandHold {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "kuerzelblatt")
    /// Früheste Zeit nach dem ⌘-Druck, zu der gelesen wird: ein kurzes ⌘C löst keinen Lesevorgang aus.
    nonisolated static let minGrace: TimeInterval = 0.2
    /// So lange vor Ablauf der Haltezeit beginnt das Lesen (gemessen 122–485 ms je Menübaum).
    nonisolated static let readAhead: TimeInterval = 0.4
    /// Das Blatt schließt sich nach so langer Zeit von selbst (E24, Grenze 3).
    private static let maxVisible: Duration = .seconds(30)

    private let prefs: Preferences
    private let sheet = ShortcutSheet()
    private var flagsMonitor: Any?
    private var mouseMonitors: [Any] = []
    private var holdTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// ⌘ ist gerade allein gehalten (nur dieser Wahrheitswert, keine Zeiten, E24a).
    private var held = false
    /// Mausklick oder Umschalter während des Haltens: bis zum Loslassen nichts mehr zeigen.
    private var suppressed = false
    private var generation = 0
    /// Ein Lesevorgang läuft noch (E24b: nie zwei gleichzeitig).
    private var reading = false
    /// Gesetzt von Seam: Umschalter (E21) offen → kein Blatt.
    var isBlocked: () -> Bool = { false }

    init(prefs: Preferences) { self.prefs = prefs }

    // MARK: An- und Abschalten

    func apply() {
        if prefs.commandSheetEnabled { start() } else { stop() }
    }

    private func start() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let alone = Self.isCommandAlone(event.modifierFlags)
            MainActor.assumeIsolated { self?.update(commandAlone: alone) }
        }
        let clicks: [NSEvent.EventTypeMask] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        for mask in clicks {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt() }
            }) { mouseMonitors.append(m) }
        }
        Self.log.notice("Kürzel-Blatt an")
    }

    private func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors = []
        held = false
        suppressed = false
        generation &+= 1
        holdTask?.cancel()
        hide()
    }

    // MARK: Entscheidungen (ohne Zustand, getestet)

    /// „⌘ allein“: ⌘ gedrückt, kein ⇧, ⌥, ⌃. Feststell- und Fn-Taste zählen nicht mit.
    nonisolated static func isCommandAlone(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .shift, .option, .control]) == .command
    }

    /// Wann das Lesen beginnt, gemessen ab ⌘-Druck.
    nonisolated static func readLead(delay: TimeInterval) -> TimeInterval {
        max(minGrace, delay - readAhead)
    }

    /// Nie in Seam selbst, im Anmeldefenster und im Sicherheitsdialog (E4, E24 Negativraum 3).
    nonisolated static func mayShow(bundleID: String?, own: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID != own && !["com.apple.loginwindow", "com.apple.SecurityAgent"].contains(bundleID)
    }

    // MARK: Ablauf

    private func update(commandAlone: Bool) {
        if commandAlone {
            guard !held else { return }
            held = true
            suppressed = false
            beginHold()
        } else {
            // ⌘ losgelassen oder ein weiteres Sondertaste dazu: Blatt weg.
            held = false
            suppressed = false
            generation &+= 1
            holdTask?.cancel()
            hide()
        }
    }

    private func interrupt() {
        guard held else { return }
        suppressed = true
        holdTask?.cancel()
        hide()
    }

    private func beginHold() {
        generation &+= 1
        let gen = generation
        let delay = Double(prefs.commandSheetDelay) / 1000
        let lead = Self.readLead(delay: delay)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(lead))
            guard let self, self.stillHeld(gen), let target = self.target() else { return }
            let started = Date()
            // E24b: nur ein Lesevorgang gleichzeitig. Läuft noch einer (hängende App), gibt es kein Blatt.
            guard let read = self.startRead(pid: target.pid) else { return }
            try? await Task.sleep(for: .seconds(max(0, delay - lead)))
            let result = await read.value
            guard self.stillHeld(gen) else { return }
            self.present(result, app: target, started: started)
        }
    }

    /// Liest im Hintergrund. `reading` fällt erst, wenn der Lesevorgang wirklich fertig ist, auch wenn
    /// das Halten längst vorbei und die Aufgabe abgebrochen ist.
    private func startRead(pid: pid_t) -> Task<MenuRead?, Never>? {
        guard !reading else { return nil }
        reading = true
        return Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { AXAccess.menuShortcuts(pid: pid) }.value
            self?.reading = false
            return result
        }
    }

    private func stillHeld(_ gen: Int) -> Bool {
        held && !suppressed && generation == gen && !Task.isCancelled
    }

    private struct Target { let pid: pid_t; let name: String; let bundleID: String }

    private func target() -> Target? {
        guard AXAccess.isTrusted, !isBlocked(), !sheet.isVisible,
              let app = NSWorkspace.shared.frontmostApplication,
              Self.mayShow(bundleID: app.bundleIdentifier, own: Bundle.main.bundleIdentifier),
              let id = app.bundleIdentifier else { return nil }
        return Target(pid: app.processIdentifier, name: app.localizedName ?? id, bundleID: id)
    }

    private func present(_ read: MenuRead?, app: Target, started: Date) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        guard let read, !read.sections.isEmpty else {
            // E24e: nur Bundle-ID und Zahlen, nie Titel.
            Self.log.notice("Kein Blatt für \(app.bundleID, privacy: .public): nichts zu zeigen (\(ms, privacy: .public) ms)")
            return
        }
        // Vorn ist noch dieselbe App? Sonst (z. B. macOS-⌘Tab mitten im Halten) wäre das Blatt von gestern.
        guard !isBlocked(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid else { return }
        let focus = read.focusFrame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? Screens.mouse
        guard let screen = Screens.containing(focus) ?? Screens.all().first else { return }
        sheet.show(app: app.name, sections: read.sections, truncated: read.truncated, on: screen)
        let count = read.sections.reduce(0) { $0 + $1.items.count }
        Self.log.notice("Blatt gezeigt für \(app.bundleID, privacy: .public): \(count, privacy: .public) Einträge, \(ms, privacy: .public) ms")
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            // Gürtel und Hosenträger: ging das Loslassen von ⌘ verloren (Sperrbildschirm, Eingabe-
            // wechsel), fragt das Blatt den Zustand selbst ab (`NSEvent.modifierFlags`, ohne Freigabe).
            let step = Duration.milliseconds(250)
            var waited = Duration.zero
            while waited < Self.maxVisible {
                try? await Task.sleep(for: step)
                waited += step
                guard !Task.isCancelled else { return }
                if !Self.isCommandAlone(NSEvent.modifierFlags) {
                    self?.held = false
                    self?.suppressed = false
                    break
                }
            }
            self?.hide()
        }
    }

    private func hide() {
        watchdog?.cancel()
        watchdog = nil
        if sheet.isVisible { Self.log.notice("Blatt versteckt") }
        sheet.hide()
    }
}
