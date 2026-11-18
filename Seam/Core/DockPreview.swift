import AppKit
import OSLog

/// Dock-Vorschau (E21): Ruht der Zeiger auf einem App-Symbol im Dock, zeigt Seam deren Fenster.
/// Klick = Fenster nach vorn. E21e: Das Dock wird nur gelesen (welches Symbol ist ausgewählt,
/// welche App, wo), über einen AX-Beobachter an seiner Symbolliste.
@MainActor
final class DockPreview {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "dock")
    nonisolated private static let gap: CGFloat = 8

    private let prefs: Preferences
    private let model = PreviewModel()
    private lazy var panel: PreviewPanel = PreviewPanel.make(model: model)
    private var observer: AXObserver?
    private var list: AXUIElement?
    private var dockPID: pid_t?
    private var shownPID: pid_t?
    private var iconFrame: CGRect = .zero
    private var hoverTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var leaveTimer: Timer?
    private var misses = 0
    private var launchToken: NSObjectProtocol?

    init(prefs: Preferences) {
        self.prefs = prefs
        model.showsSelection = false
        model.onHover = { [weak self] i in
            self?.model.showsSelection = true
            self?.model.selection = i
        }
        model.onClick = { [weak self] i in
            guard let self, self.model.windows.indices.contains(i) else { return }
            let w = self.model.windows[i]
            self.hide()
            WindowCatalog.activate(w)
        }
    }

    // MARK: An- und Abschalten

    func apply() {
        if prefs.dockPreviewEnabled { start() } else { stop() }
    }

    private func start() {
        guard observer == nil else { return }
        attach()
        // Startet das Dock neu (z. B. „Spaces in fester Reihenfolge“), stirbt der Beobachter mit.
        launchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            MainActor.assumeIsolated {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))   // Symbolliste baut sich erst auf
                    self?.detach()
                    if self?.prefs.dockPreviewEnabled == true { self?.attach() }
                }
            }
        }
    }

    private func stop() {
        detach()
        if let launchToken { NSWorkspace.shared.notificationCenter.removeObserver(launchToken) }
        launchToken = nil
        hide()
    }

    private func attach() {
        guard let pid = AXAccess.dockProcess(), let list = AXAccess.dockList(pid) else {
            Self.log.error("Dock-Symbolliste nicht gefunden")
            return
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            MainActor.assumeIsolated {
                Unmanaged<DockPreview>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
            }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let status = AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, me)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        self.list = list
        dockPID = pid
        Self.log.notice("Dock beobachtet (Anmeldung: \(status.rawValue, privacy: .public))")
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        list = nil
        dockPID = nil
    }

    // MARK: Zeiger auf einem Symbol

    private func selectionChanged() {
        guard let list, let hovered = AXAccess.dockHoveredApp(in: list) else {
            hoverTask?.cancel()                  // weg vom Symbol: das Panel schließt der Zeiger-Check
            return
        }
        let target = hovered.url.standardizedFileURL
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == target && $0.activationPolicy == .regular
        }) else {
            hoverTask?.cancel()
            hide()
            return
        }
        let pid = app.processIdentifier
        if pid == shownPID, panel.isVisible { return }
        hoverTask?.cancel()
        let delay = prefs.dockPreviewDelay
        hoverTask = Task { [weak self, prefs] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            let windows = await WindowCatalog.windows(pid: pid, currentSpaceOnly: prefs.dockPreviewCurrentSpaceOnly)
            guard !Task.isCancelled, let self else { return }
            // Zeiger noch auf demselben Symbol?
            guard let list = self.list, let now = AXAccess.dockHoveredApp(in: list),
                  now.url.standardizedFileURL == target else { return }
            if windows.isEmpty { self.hide(); return }
            self.show(windows, pid: pid, icon: now.frame)
        }
    }

    private func show(_ windows: [CatalogWindow], pid: pid_t, icon: CGRect) {
        guard let screen = Screens.containing(CGPoint(x: icon.midX, y: icon.midY)) ?? Screens.all().first else { return }
        imageTask?.cancel()
        shownPID = pid
        iconFrame = icon
        let columns = Switcher.columns(count: windows.count, tileWidth: prefs.previewSize.tileWidth,
                                       maxWidth: screen.frame.width * 0.9)
        model.showsSelection = false
        model.reset(windows, size: prefs.previewSize, columns: columns, selection: -1)
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.fittingSize
        size.width = min(size.width, screen.frame.width * 0.95)
        size.height = min(size.height, screen.frame.height * 0.8)
        let rect = Geometry.clamp(Self.placement(size: size, icon: icon, screen: screen.frame), to: screen.frame)
        panel.setFrame(Geometry.toAppKit(rect, primaryHeight: Screens.primaryHeight), display: true)
        panel.orderFrontRegardless()
        startLeaveCheck()
        imageTask = Task { [weak self] in
            await WindowCatalog.captureImages(for: windows) { id, image in self?.model.images[id] = image }
        }
    }

    private func hide() {
        hoverTask?.cancel()
        imageTask?.cancel()
        leaveTimer?.invalidate()
        leaveTimer = nil
        shownPID = nil
        panel.orderOut(nil)
    }

    /// Panel bleibt, solange der Zeiger auf Symbol, Panel oder dem Weg dazwischen ist.
    private func startLeaveCheck() {
        leaveTimer?.invalidate()
        misses = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(t, forMode: .common)
        leaveTimer = t
    }

    private func checkPointer() {
        let panelAX = Geometry.toAX(panel.frame, primaryHeight: Screens.primaryHeight)
        let keep = panelAX.union(iconFrame).insetBy(dx: -6, dy: -6)
        if keep.contains(Screens.mouse) { misses = 0; return }
        misses += 1
        if misses >= 2 { hide() }
    }

    /// Lage des Panels: auf der dem Dock abgewandten Seite des Symbols, mittig dazu.
    /// Das Dock liegt an der Bildschirmkante, der das Symbol am nächsten ist.
    nonisolated static func placement(size: CGSize, icon: CGRect, screen: CGRect) -> CGRect {
        let bottom = screen.maxY - icon.maxY, left = icon.minX - screen.minX, right = screen.maxX - icon.maxX
        if left < bottom, left <= right {
            return CGRect(x: icon.maxX + gap, y: icon.midY - size.height / 2, width: size.width, height: size.height)
        }
        if right < bottom {
            return CGRect(x: icon.minX - gap - size.width, y: icon.midY - size.height / 2, width: size.width, height: size.height)
        }
        return CGRect(x: icon.midX - size.width / 2, y: icon.minY - gap - size.height, width: size.width, height: size.height)
    }
}
