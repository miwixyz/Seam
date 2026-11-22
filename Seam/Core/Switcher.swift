import AppKit
import OSLog

/// Fensterumschalter (E21): ⌘Tab zeigt alle Fenster, ⌘< die Fenster der vorderen App.
/// Gedrückt halten und Tab wiederholen = weiter, ⇧ = zurück, loslassen = Fenster nach vorn.
///
/// E21d: Geöffnet wird über registrierte Kürzel (`Hotkeys`), das Loslassen von ⌘ liest Seam aus
/// `NSEvent.modifierFlags` (nur Sondertasten-Zustand). Pfeile, Esc, Return und Q erreichen Seam nur,
/// weil das eigene Panel Tastaturfokus hat.
@MainActor
final class Switcher {

    enum Mode { case all, frontApp }

    static let next = KeyCombo(keyCode: 48, modifiers: 256)              // ⌘Tab
    static let previous = KeyCombo(keyCode: 48, modifiers: 256 | 512)    // ⇧⌘Tab
    static let nextInApp = KeyCombo(keyCode: 10, modifiers: 256)         // ⌘< (ISO-Taste links neben Y)
    static let previousInApp = KeyCombo(keyCode: 10, modifiers: 256 | 512)
    /// Je nach ISO-Tastatur liefert macOS für „<“ Code 10 oder 50 (Taste über Tab) — beide anmelden.
    static let nextInAppAlt = KeyCombo(keyCode: 50, modifiers: 256)
    static let previousInAppAlt = KeyCombo(keyCode: 50, modifiers: 256 | 512)
    static let keys: Set<KeyCombo> = [next, previous, nextInApp, previousInApp, nextInAppAlt, previousInAppAlt]

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "umschalter")
    /// Erst so spät zeigen: Kurzes ⌘Tab wechselt ohne Aufblitzen zum letzten Fenster (wie macOS).
    private static let showDelay: TimeInterval = 0.1
    private static let maxOpen: TimeInterval = 30

    private let prefs: Preferences
    private let model = PreviewModel()
    private lazy var panel: PreviewPanel = makePanel()
    private var mode: Mode?
    private var openedAt = Date()
    private var poll: Timer?
    private var loaded = false
    private var pending = PendingSteps()
    private var previousApp: NSRunningApplication?
    private var loadTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?

    /// Apps in der Reihenfolge der Nutzung (zuletzt aktiv zuerst), von macOS gemeldet. Nur Prozessnummern.
    private var appOrder: [pid_t] = []
    private var activationToken: NSObjectProtocol?

    init(prefs: Preferences) {
        self.prefs = prefs
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { appOrder = [front] }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                  pid != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.noteActivated(pid) }
        }
        model.onHover = { [weak self] i in self?.model.selection = i }
        model.onClick = { [weak self] i in
            self?.model.selection = i
            self?.commit()
        }
    }

    private func noteActivated(_ pid: pid_t) {
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        if appOrder.count > 100 { appOrder.removeLast() }
    }

    /// Umschalter ist offen (E24a: dann zeigt das Kürzel-Blatt nichts).
    var isOpen: Bool { mode != nil }

    /// Kürzel gedrückt. true = gehört dem Umschalter.
    func handle(_ key: KeyCombo) -> Bool {
        guard prefs.switcherEnabled, Self.keys.contains(key) else { return false }
        let back = key.modifiers & 512 != 0
        let wanted: Mode = key.keyCode == 48 ? .all : .frontApp
        Self.log.notice("Kürzel Umschalter: \(key.label, privacy: .public)")
        if mode == nil { open(wanted) }
        step(back ? -1 : 1)
        return true
    }

    // MARK: Öffnen, Schritt, Schließen

    private func open(_ m: Mode) {
        mode = m
        openedAt = Date()
        loaded = false
        pending = PendingSteps()
        previousApp = NSWorkspace.shared.frontmostApplication
        startPolling()
        let pid = m == .frontApp ? previousApp?.processIdentifier : nil
        if m == .frontApp, pid == nil { close(); return }
        // Vorderste App immer zuerst, auch wenn Seam ihre Aktivierung verpasst hat.
        if let front = previousApp?.processIdentifier { noteActivated(front) }
        let order = appOrder
        loadTask = Task { [weak self, prefs] in
            let list = await WindowCatalog.windows(pid: pid, currentSpaceOnly: prefs.switcherCurrentSpaceOnly, appOrder: order)
            self?.loaded(list)
        }
    }

    private func loaded(_ list: [CatalogWindow]) {
        guard mode != nil else { return }
        guard !list.isEmpty else { close(); return }
        loaded = true
        let steps = pending.steps
        pending = PendingSteps()
        let start = Self.start(steps: steps, list: list, mode: mode ?? .all, front: previousApp?.processIdentifier)
        let screen = Screens.containing(Screens.mouse) ?? Screens.all().first
        let columns = Self.columns(count: list.count, tileWidth: prefs.previewSize.tileWidth,
                                   maxWidth: (screen?.visible.width ?? 1200) * 0.92)
        model.showsSelection = true
        model.reset(list, size: prefs.previewSize, columns: columns, selection: start)
        if !Self.modifierHeld {
            commit()                         // schon losgelassen, bevor die Liste da war
            return
        }
        let wait = max(0, Self.showDelay - Date().timeIntervalSince(openedAt))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, self.mode != nil else { return }
            self.show(on: screen)
        }
    }

    private func step(_ delta: Int) {
        guard loaded else { pending.press(delta); return }
        model.selection = Self.wrap(model.selection + delta, count: model.windows.count)
    }

    /// Ausgewähltes Fenster nach vorn.
    private func commit() {
        let target = model.windows.indices.contains(model.selection) ? model.windows[model.selection] : nil
        close()
        if let target { WindowCatalog.activate(target) }
    }

    /// Esc: nichts wechseln, die vorher aktive App behält den Fokus.
    private func cancel() {
        close()
        previousApp?.activate()
    }

    private func close() {
        mode = nil
        poll?.invalidate()
        poll = nil
        loadTask?.cancel()
        imageTask?.cancel()
        panel.acceptsKey = false
        panel.orderOut(nil)
    }

    private func show(on screen: Screens.Info?) {
        guard let screen else { return }
        panel.acceptsKey = true
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.fittingSize
        size.width = min(size.width, screen.visible.width * 0.95)
        size.height = min(size.height, screen.visible.height * 0.9)
        let rect = CGRect(x: screen.visible.midX - size.width / 2, y: screen.visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        panel.setFrame(Geometry.toAppKit(rect, primaryHeight: Screens.primaryHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        let list = model.windows, tile = prefs.previewSize.tileWidth
        imageTask = Task { [weak self] in
            await WindowCatalog.captureImages(for: list, tileWidth: tile) { id, image in self?.model.images[id] = image }
        }
    }

    // MARK: Tasten im eigenen Panel (E21d)

    private func makePanel() -> PreviewPanel {
        let p = PreviewPanel.make(model: model)
        p.onKey = { [weak self] e in self?.key(e) }
        return p
    }

    private func key(_ e: NSEvent) {
        let cols = model.columns
        switch e.keyCode {
        case 53: cancel()                                  // Esc
        case 36, 76: commit()                              // Return, Enter
        case 123: step(-1)                                 // ←
        case 124: step(1)                                  // →
        case 126: step(-cols)                              // ↑
        case 125: step(cols)                               // ↓
        case 12: quitSelectedApp()                         // Q (gleiche Taste auf US und DE)
        default: break
        }
    }

    /// E21f: App des markierten Eintrags beenden; die App fragt selbst nach ungesicherten Dokumenten.
    private func quitSelectedApp() {
        guard model.windows.indices.contains(model.selection) else { return }
        let pid = model.windows[model.selection].pid
        NSRunningApplication(processIdentifier: pid)?.terminate()
        let rest = model.windows.filter { $0.pid != pid }
        guard !rest.isEmpty else { close(); return }
        model.windows = rest
        model.selection = min(model.selection, rest.count - 1)
    }

    // MARK: Loslassen von ⌘ (E21d)

    private static var modifierHeld: Bool { NSEvent.modifierFlags.contains(.command) }

    private func startPolling() {
        poll?.invalidate()
        let t = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func tick() {
        guard mode != nil else { return }
        if Date().timeIntervalSince(openedAt) > Self.maxOpen { cancel(); return }
        if !Self.modifierHeld {
            if loaded { commit() } else { pending.release() }
        }
    }

    // MARK: Rechnen (getestet)

    /// Tab-Schritte, bevor die Liste geladen ist. Nach dem Loslassen von ⌘ ist die Geste zu Ende:
    /// Weitere Drücke zählen nicht mehr dazu (Audit 18.11.: zweimal schnell ⌘Tab sprang zum dritten Fenster).
    struct PendingSteps {
        private(set) var steps = 0
        private var released = false
        mutating func press(_ delta: Int) { if !released { steps += delta } }
        mutating func release() { released = true }
    }

    /// Startauswahl nach `steps` Tab-Schritten. ⌘Tab vorwärts: der erste Schritt springt über die
    /// übrigen Fenster der vorderen App zur zuletzt benutzten App (wie macOS). ⌘< und rückwärts: Eintrag für Eintrag.
    nonisolated static func start(steps: Int, list: [CatalogWindow], mode: Mode, front frontPID: pid_t? = nil) -> Int {
        guard mode == .all, steps > 0, let front = list.first?.pid else { return wrap(steps, count: list.count) }
        // Vordere App hat kein Fenster in der Liste: Die erste App der Liste ist schon die zuletzt benutzte.
        if let frontPID, front != frontPID { return wrap(steps - 1, count: list.count) }
        guard let other = list.firstIndex(where: { $0.pid != front }) else { return wrap(steps, count: list.count) }
        return wrap(other + steps - 1, count: list.count)
    }

    nonisolated static func wrap(_ i: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((i % count) + count) % count
    }

    nonisolated static func columns(count: Int, tileWidth: CGFloat, maxWidth: CGFloat) -> Int {
        let outer = tileWidth + 14 + WindowGridView.spacing
        let fit = max(1, Int((maxWidth - 2 * WindowGridView.padding) / outer))
        return max(1, min(count, fit))
    }
}
