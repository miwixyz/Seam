import AppKit
import OSLog

/// Andocken per Ziehen und Mitziehen an gemeinsamen Kanten.
///
/// Ablauf je Geste:
/// 1. **Maustaste unten** (passiver Beobachter, docs/SECURE-DESIGN.md E2): alle
///    Fenster in Zeigernähe werden Kandidaten. Nicht nur das Fenster unter dem
///    Zeiger: Der Griff zum Größeziehen liegt bei macOS ein paar Pixel AUSSERHALB
///    des Fensters, beim Packen einer gemeinsamen Kante also im Spalt oder schon
///    über dem Nachbarn.
/// 2. Das erste Kandidatenfenster, das „verschoben“ oder „Größe geändert“ meldet,
///    wird **führend**. Nur seine Meldungen zählen ab dann (E6a: keine Rückkopplung
///    über die nachgestellten Nachbarn, die ja ebenfalls beobachtet werden).
/// 3. Größe geändert → Nachbarn an der bewegten Kante nachstellen.
///    Verschoben → Andockzone am Bildschirmrand anzeigen, beim Loslassen andocken.
@MainActor
final class DragController {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "ziehen")

    private let prefs: Preferences
    private let actions: WindowActions
    private let overlay = SnapOverlay()
    private var monitors: [Any] = []

    private enum Mode { case undecided, moving, resizing }

    private final class Gesture {
        var candidates: [(window: AXWindow, start: CGRect)]
        /// Klickpunkt beim Gestenbeginn (für „welche Kante wurde gepackt?“).
        let downPoint: CGPoint
        var grabbed: [Geometry.Edge] = []
        var observers: [AXObserver] = []
        var leading: AXWindow?
        var start: CGRect = .zero
        var mode: Mode = .undecided
        var neighbors: [Geometry.Neighbor]?
        var neighborWindows: [Int: AXWindow] = [:]
        var engaged = false
        var pending: (Command, Screens.Info)?
        /// Ursprüngliche Größe, falls beim Herausziehen wiederhergestellt.
        var restoredOriginal: CGRect?
        var linkEvents = 0
        // Messpunkt (08.10., „Edge und Outlook haken“): unterscheidet „App meldet
        // selten“ von „Nachstellen blockiert Seam“.
        var mouseDrags = 0
        var resizeNotifications = 0
        var firstNotification: CFAbsoluteTime = 0
        var lastNotification: CFAbsoluteTime = 0
        init(candidates: [(window: AXWindow, start: CGRect)], downPoint: CGPoint) {
            self.candidates = candidates
            self.downPoint = downPoint
        }
    }

    private var gesture: Gesture?

    /// Nachstellen auf eigener Warteschlange, neuester Wert gewinnt (E6c, ersetzt die
    /// frühere 8-ms-Bremse, die den letzten Wert eines Meldungsstoßes verwarf).
    private let writer = NeighborWriter()
    /// So weit um den Zeiger werden Fenster als Kandidaten gesucht.
    private static let grabRadius: CGFloat = 8

    init(prefs: Preferences, actions: WindowActions) {
        self.prefs = prefs
        self.actions = actions
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, @MainActor (DragController) -> Void)] = [
            (.leftMouseDown, { $0.mouseDown() }),
            (.leftMouseDragged, { $0.mouseDragged() }),
            (.leftMouseUp, { $0.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { if let self { handler(self) } }
            }) { monitors.append(m) }
        }
        Self.log.notice("Maus-Beobachter aktiv: \(self.monitors.count, privacy: .public)/3")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        endGesture()
    }

    // MARK: - Maus

    private func mouseDown() {
        endGesture()
        guard prefs.linkEdges || prefs.dragSnap || prefs.restoreOnDragOut else { return }
        let p = Screens.mouse
        let candidates = Self.windowsNear(p)
        guard !candidates.isEmpty else { return }
        let g = Gesture(candidates: candidates, downPoint: p)
        gesture = g
        observe(g)
    }

    private func mouseDragged() {
        gesture?.mouseDrags += 1
        guard let g = gesture, g.mode == .moving, prefs.dragSnap else { return }
        let p = Screens.mouse
        guard let screen = Screens.containing(p) else { return }
        let o = screen.orientation
        let cmd = Geometry.activeCommand(at: p, screen: screen.frame, o, engaged: g.engaged)
        g.engaged = cmd != nil
        if let cmd, let cells = Layout.spec(cmd, o)?.target {
            overlay.show(Geometry.rect(for: cells, in: screen.visible, o, gap: CGFloat(prefs.gap)))
            g.pending = (cmd, screen)
        } else {
            overlay.hide()
            g.pending = nil
        }
    }

    private func mouseUp() {
        guard let g = gesture else { return }
        overlay.hide()
        if let w = g.leading {
            switch g.mode {
            case .moving:
                if let (cmd, screen) = g.pending, let cur = w.frame {
                    actions.apply(cmd, to: w, current: cur, screen: screen, before: g.restoredOriginal ?? g.start)
                }
            case .resizing:
                if let raw = w.frame {
                    let now = effectiveFrame(g, raw)
                    // macOS hat eine nicht gepackte Kante an den Bildschirmrand gezogen: zurück.
                    if now != raw {
                        w.setFrame(now)
                        Self.log.notice("Ungepackte Kante zurückgesetzt: \(NSStringFromRect(raw), privacy: .public) → \(NSStringFromRect(now), privacy: .public)")
                    }
                    if prefs.linkEdges { applyLink(g, now: now, final: true) }
                    logResizeStats(g, leading: w)
                }
            case .undecided:
                break
            }
        }
        endGesture()
    }

    // MARK: - Fenster-Meldungen

    private func windowChanged(_ element: AXUIElement) {
        guard let g = gesture else { return }
        if g.leading == nil {
            guard let c = g.candidates.first(where: { CFEqual($0.window.element, element) }) else { return }
            g.leading = c.window
            g.start = c.start
            g.grabbed = Geometry.grabbedEdges(at: g.downPoint, frame: c.start, radius: Self.grabRadius + 2)
        }
        guard let w = g.leading, CFEqual(w.element, element), let raw = w.frame else { return }
        let now = effectiveFrame(g, raw)

        if !Geometry.movedEdges(from: g.start, to: now).isEmpty {
            if g.mode == .undecided { g.mode = .resizing }
            let t = CFAbsoluteTimeGetCurrent()
            if g.resizeNotifications == 0 { g.firstNotification = t }
            g.resizeNotifications += 1
            g.lastNotification = t
            if g.mode == .resizing, prefs.linkEdges { applyLink(g, now: now, final: false) }
        } else if now.origin != g.start.origin, g.mode == .undecided {
            g.mode = .moving
            restoreSizeIfSnapped(g, w: w, now: now)
        }
    }

    private func logResizeStats(_ g: Gesture, leading w: AXWindow) {
        func app(_ pid: pid_t) -> String { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "\(pid)" }
        let neighbors = Set(g.neighborWindows.values.map { app($0.pid) }).sorted().joined(separator: ",")
        let dur = g.lastNotification - g.firstNotification
        let st = writer.takeStats()
        Self.log.notice("Messung Größeziehen: gezogen \(app(w.pid), privacy: .public) → Nachbarn \(neighbors.isEmpty ? "–" : neighbors, privacy: .public) | Mausschritte \(g.mouseDrags, privacy: .public), Meldungen \(g.resizeNotifications, privacy: .public) in \(Int(dur * 1000), privacy: .public) ms, eingereicht \(g.linkEvents, privacy: .public), gesetzt \(st.count, privacy: .public), Setzen Ø \(st.avgMs, privacy: .public) ms max \(st.maxMs, privacy: .public) ms")
    }

    /// Rahmen, wie der Nutzer ihn gezogen hat: Kanten, die er nicht gepackt hat,
    /// bleiben, wo sie waren (Geometry.keepUngrabbedEdges, gemessen an macOS 27).
    private func effectiveFrame(_ g: Gesture, _ raw: CGRect) -> CGRect {
        Geometry.keepUngrabbedEdges(now: raw, start: g.start, grabbed: g.grabbed, slack: CGFloat(prefs.gap) + 6)
    }

    /// Magnet „ursprüngliche Größe wiederherstellen“: Ein angedocktes Fenster bekommt
    /// beim Herausziehen seine alte Größe, der Zeiger bleibt an derselben relativen Stelle.
    private func restoreSizeIfSnapped(_ g: Gesture, w: AXWindow, now: CGRect) {
        guard prefs.restoreOnDragOut, let orig = actions.wasSnapped(w) else { return }
        let p = Screens.mouse
        let rel = now.width > 0 ? (p.x - now.minX) / now.width : 0.5
        w.setFrame(CGRect(x: p.x - rel * orig.width, y: now.minY, width: orig.width, height: orig.height))
        actions.forget(w)
        g.restoredOriginal = orig
    }

    private func applyLink(_ g: Gesture, now: CGRect, final: Bool) {
        guard let w = g.leading else { return }
        if g.neighbors == nil {
            let found = WindowFinder.neighbors(of: w, frame: g.start, gap: CGFloat(prefs.gap))
            g.neighbors = found.enumerated().map { Geometry.Neighbor(id: $0.offset, frame: $0.element.1) }
            g.neighborWindows = Dictionary(uniqueKeysWithValues: found.enumerated().map { ($0.offset, $0.element.0) })
            Self.log.notice("Mitziehen: \(found.count, privacy: .public) Nachbar(n) an der Kante")
        }
        guard let neighbors = g.neighbors, !neighbors.isEmpty else { return }
        g.linkEvents += 1
        let frames = Geometry.linkedFrames(start: g.start, now: now, neighbors: neighbors, gap: CGFloat(prefs.gap))
            .filter { $0.value.width >= 80 && $0.value.height >= 60 }   // E6d: nie auf Splitter zusammendrücken

        guard final else {
            // Während des Ziehens: auf eigener Warteschlange, neuester Wert gewinnt.
            var batch: [Int: (AXWindow, CGRect)] = [:]
            for (id, r) in frames { if let nw = g.neighborWindows[id] { batch[id] = (nw, r) } }
            writer.submit(batch)
            return
        }

        // Ende: Zwischenstände abwarten, dann setzen und zurücklesen.
        writer.flush()
        var leading = now
        for (id, wanted) in frames.sorted(by: { $0.key < $1.key }) {
            guard let nw = g.neighborWindows[id], let actual = nw.setFrame(wanted) else { continue }
            if let fix = Geometry.resolveMinimum(leading: leading, wanted: wanted, actual: actual) {
                // Mindestgröße des Nachbarn: Kante bleibt dort stehen, nichts überlappt.
                nw.setFrame(fix.neighbor)
                leading = fix.leading
                w.setFrame(leading)
                Self.log.notice("Mindestgröße: Nachbar Soll \(NSStringFromRect(wanted), privacy: .public) Ist \(NSStringFromRect(actual), privacy: .public) → Kante gehalten, gezogenes Fenster \(NSStringFromRect(leading), privacy: .public)")
            } else {
                Self.log.notice("Mitziehen Ende: Soll \(NSStringFromRect(wanted), privacy: .public) Ist \(NSStringFromRect(actual), privacy: .public)")
            }
        }
    }

    // MARK: - Beobachter

    private func observe(_ g: Gesture) {
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            MainActor.assumeIsolated {
                Unmanaged<DragController>.fromOpaque(refcon).takeUnretainedValue().windowChanged(element)
            }
        }
        for pid in Set(g.candidates.map(\.window.pid)) {
            var obs: AXObserver?
            guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { continue }
            for c in g.candidates where c.window.pid == pid {
                AXObserverAddNotification(obs, c.window.element, kAXMovedNotification as CFString, me)
                AXObserverAddNotification(obs, c.window.element, kAXResizedNotification as CFString, me)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            g.observers.append(obs)
        }
    }

    private func endGesture() {
        guard let g = gesture else { return }
        for obs in g.observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        g.observers = []
        gesture = nil
    }

    /// Fenster, deren Rahmen (um `grabRadius` erweitert) den Zeiger enthält, von vorn
    /// nach hinten, höchstens drei. Lage und Prozess aus der Fensterliste des Systems,
    /// die AX-Referenz dann über den Rahmen.
    private static func windowsNear(_ p: CGPoint) -> [(window: AXWindow, start: CGRect)] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var hits: [(pid_t, CGRect)] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b),
                  bounds.insetBy(dx: -grabRadius, dy: -grabRadius).contains(p) else { continue }
            hits.append((pid, bounds))
        }
        // Erst über die Bedienungshilfen zuordnen, DANN auf drei begrenzen: Überlagerungen
        // wie HazeOver (ein Fenster über den ganzen Bildschirm, gemessen 08.10.) liegen
        // vorn in der Liste, sind aber keine verwaltbaren App-Fenster und würden sonst
        // einen Kandidatenplatz belegen.
        var out: [(window: AXWindow, start: CGRect)] = []
        for (pid, bounds) in hits where out.count < 3 {
            if let w = AXAccess.windows(of: pid).first(where: { win in
                guard let f = win.frame else { return false }
                return abs(f.minX - bounds.minX) <= 2 && abs(f.minY - bounds.minY) <= 2
                    && abs(f.width - bounds.width) <= 2 && abs(f.height - bounds.height) <= 2
            }), let f = w.frame, !out.contains(where: { $0.window == w }) {
                out.append((w, f))
            }
        }
        return out
    }
}
