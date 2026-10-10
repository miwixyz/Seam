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
///    wird **führend**. Nur seine Meldungen zählen ab dann (E6a). Ob verschoben oder
///    Größe geändert, entscheidet die rohe Größe (`Geometry.gestureMode`); danach liest
///    Seam bis zum Loslassen nichts mehr (Code-Audit 09.10., C2/P2).
/// 3. Größe geändert → beim LOSLASSEN die Nachbarn an der bewegten Kante bündig setzen.
///    Verschoben → Andockzone am Bildschirmrand anzeigen, beim Loslassen andocken.
///
/// **Nachbar beim Loslassen, nicht live** (Michael, 08.10.: „alles andere als flüssig“).
/// Live-Mitziehen fremder Fenster über die Bedienungshilfen war mit Outlook/Edge nicht
/// flüssig zu bekommen: kurze Gesten erreichten nur 3–13 Zwischenstände, Outlook verrät
/// seine Kante nur alle 43–99 ms. Lese-Faden, Konturen und Langsam-Erkennung sind
/// deshalb wieder ausgebaut (Verlauf: Projektdatei Seam, Chat-Übergabe 08.10.).
/// Fein verschieben geht per Tastatur: ⌃⌥S teilt, ⌃⌥⇧←/→ verschiebt die Naht.
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
        init(candidates: [(window: AXWindow, start: CGRect)], downPoint: CGPoint) {
            self.candidates = candidates
            self.downPoint = downPoint
        }
    }

    private var gesture: Gesture?
    /// Abschluss einer Geste auf eigener Warteschlange (Setzen mit Nachprüfung blockiert
    /// sonst den Hauptthread, Outlook antwortete bis 56 ms je Setzen).
    /// Gemeinsame Warteschlange der App (R4), über `WindowActions`.
    private var writer: NeighborWriter { actions.writer }
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

    // MARK: - Maus

    private func mouseDown() {
        endGesture()
        // Neue Geste: Seams eigene Nachsetz-Wiederholungen der letzten Geste abbrechen, sonst
        // hielte diese Geste deren Setz-Meldungen für eine Bewegung des Nutzers (R3).
        writer.cancelRetries()
        guard prefs.linkEdges || prefs.dragSnap || prefs.restoreOnDragOut else { return }
        let p = Screens.mouse
        let candidates = Self.windowsNear(p)
        guard !candidates.isEmpty else { return }
        let g = Gesture(candidates: candidates, downPoint: p)
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
                if let raw = w.frame {
                    let now = effectiveFrame(g, raw)
                    var frames: [Int: CGRect] = [:]
                    if prefs.linkEdges, ensureNeighbors(g), let neighbors = g.neighbors {
                        frames = Geometry.linkedFrames(start: g.start, now: now, neighbors: neighbors, gap: CGFloat(prefs.gap))
                            .filter { $0.value.width >= 80 && $0.value.height >= 60 }   // E6d
                    }
                    finish(leading: w, raw: raw, now: now, frames: frames, windows: g.neighborWindows)
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
        // Nach der Entscheidung wird nichts mehr gelesen: Der Rahmen zählt erst beim Loslassen
        // (P2: vorher 2 AX-Aufrufe je Meldung, Dutzende pro Sekunde in die gezogene App).
        guard g.mode == .undecided, let w = g.leading, CFEqual(w.element, element), let raw = w.frame else { return }
        switch Geometry.gestureMode(start: g.start, raw: raw) {
        case .resizing?: g.mode = .resizing
        case .moving?:
            g.mode = .moving
            restoreSizeIfSnapped(g, w: w, now: raw)
        case nil: break
        }
    }

    /// Rahmen, wie der Nutzer ihn gezogen hat: Kanten, die er nicht gepackt hat,
    /// bleiben, wo sie waren (Geometry.keepUngrabbedEdges, gemessen an macOS 27).
    private func effectiveFrame(_ g: Gesture, _ raw: CGRect) -> CGRect {
        Geometry.keepUngrabbedEdges(now: raw, start: g.start, grabbed: g.grabbed, slack: CGFloat(prefs.gap) + 6)
    }

    /// Magnet „ursprüngliche Größe wiederherstellen“: Ein angedocktes Fenster bekommt
    /// beim Herausziehen seine alte Größe, der Zeiger bleibt an derselben relativen Stelle.
    /// Über die Warteschlange und auf den sichtbaren Bereich begrenzt (Code-Audit 09.10., C7/S2:
    /// vorher synchron auf dem Hauptthread, bei hängender App bis ~1,25 s Stillstand mitten in der
    /// Geste, entgegen E6b/E5). Einmal setzen ohne Nachprüfung: Der Nutzer zieht ja weiter.
    private func restoreSizeIfSnapped(_ g: Gesture, w: AXWindow, now: CGRect) {
        guard prefs.restoreOnDragOut, let orig = actions.wasSnapped(w) else { return }
        let p = Screens.mouse
        let rel = now.width > 0 ? (p.x - now.minX) / now.width : 0.5
        var target = CGRect(x: p.x - rel * orig.width, y: now.minY, width: orig.width, height: orig.height)
        if let screen = Screens.best(for: now) { target = Geometry.clamp(target, to: screen.visible) }
        let goal = target
        writer.run { w.setFrame(goal) }
        actions.forget(w)
        g.restoredOriginal = orig
    }

    /// Nachbarn einmal je Geste suchen (beim Loslassen einer Größen-Geste).
    private func ensureNeighbors(_ g: Gesture) -> Bool {
        guard let w = g.leading else { return false }
        if g.neighbors == nil {
            let found = WindowFinder.neighbors(of: w, frame: g.start, gap: CGFloat(prefs.gap))
            g.neighbors = found.enumerated().map { Geometry.Neighbor(id: $0.offset, frame: $0.element.1) }
            g.neighborWindows = Dictionary(uniqueKeysWithValues: found.enumerated().map { ($0.offset, $0.element.0) })
            Self.log.notice("Mitziehen: \(found.count, privacy: .public) Nachbar(n) an der Kante")
        }
        return !(g.neighbors ?? []).isEmpty
    }

    /// Abschluss einer Größen-Geste, nacheinander auf der Warteschlange, jeder Endwert
    /// mit Nachprüfung (Edge/Outlook übernehmen ein einmaliges Setzen oft nicht).
    /// 1. Ungepackte Kante zurück, falls macOS sie an den Bildschirmrand gezogen hat.
    /// 2. Nachbarn auf ihre Endrahmen.
    /// 3. Hat ein Nachbar eine Mindestgröße: Kante dort halten, gezogenes Fenster anpassen.
    private func finish(leading w: AXWindow, raw: CGRect, now: CGRect,
                        frames: [Int: CGRect], windows: [Int: AXWindow]) {
        let log = Self.log, writer = self.writer, actions = self.actions
        let m = writer.mark()
        writer.run {
            // Bricht ab, sobald der Nutzer eine neue Geste beginnt (R3).
            let stillWanted = { writer.isCurrent(m) }
            var leading = now
            if !Geometry.close(raw, now) {
                let ist = NeighborWriter.setVerified(w, now, while: stillWanted)
                log.notice("Ungepackte Kante zurück: \(NSStringFromRect(raw), privacy: .public) → Ist \(ist.map(NSStringFromRect) ?? "–", privacy: .public)")
            }
            for (id, wanted) in frames.sorted(by: { $0.key < $1.key }) {
                let t0 = CFAbsoluteTimeGetCurrent()
                guard let nw = windows[id] else { continue }
                let (got, attempts) = NeighborWriter.setVerifiedCounting(nw, wanted, while: stillWanted)
                guard let actual = got else { continue }
                log.notice("Endwert Nachbar: \(attempts, privacy: .public) Versuch(e), \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000), privacy: .public) ms")
                if let fix = Geometry.resolveMinimum(leading: leading, wanted: wanted, actual: actual) {
                    let nIst = NeighborWriter.setVerified(nw, fix.neighbor)
                    leading = fix.leading
                    let lIst = NeighborWriter.setVerified(w, leading)
                    actions.announce(MinimumHit(wanted: wanted, actual: actual, fix: fix, neighborIst: nIst, leadingIst: lIst),
                                     neighbor: nw, other: w)
                    log.notice("Mindestgröße: Nachbar Soll \(NSStringFromRect(wanted), privacy: .public) Ist \(NSStringFromRect(actual), privacy: .public) → Nachbar \(nIst.map(NSStringFromRect) ?? "–", privacy: .public), gezogenes Fenster Soll \(NSStringFromRect(leading), privacy: .public) Ist \(lIst.map(NSStringFromRect) ?? "–", privacy: .public)")
                } else {
                    log.notice("Mitziehen Ende: Soll \(NSStringFromRect(wanted), privacy: .public) Ist \(NSStringFromRect(actual), privacy: .public)")
                }
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
        let hits = WindowList.onScreen().filter { $0.bounds.insetBy(dx: -grabRadius, dy: -grabRadius).contains(p) }
        // Erst über die Bedienungshilfen zuordnen, DANN auf drei begrenzen: Überlagerungen
        // wie HazeOver (ein Fenster über den ganzen Bildschirm, gemessen 08.10.) liegen
        // vorn in der Liste, sind aber keine verwaltbaren App-Fenster und würden sonst
        // einen Kandidatenplatz belegen. Startrahmen bewusst aus den Bedienungshilfen, nicht
        // aus der Fensterliste: `Geometry.gestureMode` vergleicht die Größe exakt, schon 1 pt
        // Abweichung zwischen beiden Quellen wäre ein Fehlalarm „Größe geändert“.
        var out: [(window: AXWindow, start: CGRect)] = []
        for e in hits where out.count < 3 {
            if let w = AXAccess.window(of: e.pid, matching: e.bounds), let f = w.frame,
               !out.contains(where: { $0.window == w }) {
                out.append((w, f))
            }
        }
        return out
    }
}
