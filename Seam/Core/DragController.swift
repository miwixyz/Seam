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
        var lastApply: CFAbsoluteTime = 0
        var linkEvents = 0
        init(candidates: [(window: AXWindow, start: CGRect)]) { self.candidates = candidates }
    }

    private var gesture: Gesture?

    /// Höchstens eine Nachstellung je ~8 ms (E6c). Die letzte kommt beim Loslassen immer.
    private static let minInterval: CFAbsoluteTime = 0.008
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
        let g = Gesture(candidates: candidates)
        gesture = g
        observe(g)
    }

    private func mouseDragged() {
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
                if prefs.linkEdges, let now = w.frame { applyLink(g, now: now, final: true) }
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
        }
        guard let w = g.leading, CFEqual(w.element, element), let now = w.frame else { return }

        if !Geometry.movedEdges(from: g.start, to: now).isEmpty {
            if g.mode == .undecided { g.mode = .resizing }
            if g.mode == .resizing, prefs.linkEdges { applyLink(g, now: now, final: false) }
        } else if now.origin != g.start.origin, g.mode == .undecided {
            g.mode = .moving
            restoreSizeIfSnapped(g, w: w, now: now)
        }
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
        let t = CFAbsoluteTimeGetCurrent()
        guard final || t - g.lastApply >= Self.minInterval else { return }
        g.lastApply = t
        g.linkEvents += 1
        let frames = Geometry.linkedFrames(start: g.start, now: now, neighbors: neighbors, gap: CGFloat(prefs.gap))
        for (id, r) in frames {
            // E6d: Ein Nachbar, der dabei unter eine Mindestgröße fiele, bleibt stehen.
            guard r.width >= 80, r.height >= 60, let nw = g.neighborWindows[id] else { continue }
            if final {
                let ist = nw.setFrame(r)
                Self.log.notice("Mitziehen Ende: Soll \(NSStringFromRect(r), privacy: .public) Ist \(ist.map(NSStringFromRect) ?? "–", privacy: .public), Nachstellungen \(g.linkEvents, privacy: .public)")
            } else {
                nw.setFrameLive(r)
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
            if hits.count == 3 { break }
        }
        var out: [(window: AXWindow, start: CGRect)] = []
        for (pid, bounds) in hits {
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
