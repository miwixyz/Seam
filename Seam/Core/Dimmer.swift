import AppKit
import OSLog

/// Wie ein Bildschirm abgedunkelt wird (je Bildschirm einstellbar, Michael 16.10.).
enum DimScreenMode: String, CaseIterable {
    /// Ganz dunkel, nur das aktive Fenster hell (wie bis 0.5).
    case dim
    /// Zusätzlich bleibt das oberste Fenster dieses Bildschirms hell.
    case topBright
    /// Dieser Bildschirm wird nie abgedunkelt.
    case off
}

/// Ein Bildschirm für die Rechnung: Lage (Bedienungshilfen-Koordinaten) und gewählte Art.
struct DimScreen: Equatable {
    let frame: CGRect
    let mode: DimScreenMode
}

/// Ein Malschritt im Abdunkel-Fenster (Bedienungshilfen-Koordinaten): hell = Loch, sonst dunkel.
struct DimPaint: Equatable {
    let rect: CGRect
    let bright: Bool
}

/// Was ein Abdunkel-Fenster zeigt: unter welchem Fenster (nil = ausgeblendet), welche Löcher, wie stark.
struct DimScreenPlan: Equatable {
    let target: Int?
    let paints: [DimPaint]
    let strength: Int
}

/// Unter welches Fenster gehört die Abdunklung? Reine Rechnung, getestet.
enum DimPlan {

    /// `stack`: Fenster der Ebene 0 von vorn nach hinten. Hell bleibt das oberste Fenster der
    /// vorderen App (auch Dialoge und Bedienfelder) und — bei einem Paar — der Partner.
    /// Rückgabe: die Nummer des untersten hellen Fensters, oder nil = nicht abdunkeln.
    /// Kleiner als 50 × 50 pt ist kein Fenster, unter das die Abdunklung gehört: Linkanzeige unten im
    /// Browser, Tooltips, Hover-Schilder. Gemessen 16.10. (Michaels Video, Helium): die Linkanzeige
    /// (212 × 43 pt, Deckkraft 0) wurde Ziel, verschwand im selben Moment, die Abdunklung landete ganz
    /// unten bzw. ging aus — der ganze Bildschirm blitzte ~0,2 s hell.
    static let minWindow: CGFloat = 50

    static func isRealWindow(_ w: StackWindow) -> Bool {
        w.bounds.width >= minWindow && w.bounds.height >= minWindow
    }

    static func target(stack: [StackWindow], frontPID: pid_t, partner: (pid: pid_t, frame: CGRect)?,
                       exclude: Set<Int>, focused: CGRect? = nil) -> Int? {
        let visible = stack.filter { !exclude.contains($0.number) && isRealWindow($0) }
        // Ab 0.6.1: das Fenster mit dem Fokus (über die Lage gefunden), nicht einfach das oberste der App.
        // Das oberste war bei Helium oft ein flüchtiges Zusatzfenster (Dialog im Ausblenden, Download-
        // Hinweis); verschwand es, fiel die Abdunklung nach unten (Messung 16.10., 17:12:51).
        // Zusatzfenster ÜBER dem Fokusfenster bleiben trotzdem hell, sie liegen über der Abdunklung.
        let byFocus = focused.flatMap { f in
            visible.firstIndex { $0.pid == frontPID && Geometry.close($0.bounds, f) }
        }
        guard let fi = byFocus ?? visible.firstIndex(where: { $0.pid == frontPID }) else { return nil }
        guard let partner,
              let pi = visible.firstIndex(where: { $0.pid == partner.pid && Geometry.close($0.bounds, partner.frame) }),
              pi > fi else { return visible[fi].number }
        return visible[pi].number
    }

    /// Liegt die Abdunklung direkt unter dem Ziel (eigene weitere Abdunkel-Fenster dazwischen zählen nicht)?
    static func isInPlace(stack: [StackWindow], target: Int, overlays: Set<Int>) -> Bool {
        guard let ti = stack.firstIndex(where: { $0.number == target }) else { return false }
        let rest = stack[(ti + 1)...]
        guard let next = rest.first else { return false }
        return overlays.contains(next.number)
    }

    /// Vorn ist kein Ziel (App ohne eigenes Fenster wie Menüleisten-Apps, Starter, Passwort-Manager,
    /// oder ihr Fenster hat noch keinen Fokus): Abdunklung stehen lassen?
    ///
    /// Bis 0.5.4 ging sie dann aus und kam mit der nächsten App wieder — bei 50 % Stärke ein
    /// Flackern des ganzen Hintergrunds, gemessen 10–25× je Stunde (Michael, 12.10., Variante a).
    /// Weg nur noch beim Schreibtisch (Finder ohne Fokusfenster, eigener Klick) und wenn das alte
    /// Ziel nicht mehr direkt über der Abdunklung liegt — sonst läge sie über allem.
    /// Ab 0.6 je Bildschirm: stehen lassen nur, wenn JEDES Ziel noch direkt darüber liegt.
    static func keepWithoutTarget(isDesktop: Bool, stack: [StackWindow], lastTargets: [Int],
                                  overlays: Set<Int>) -> Bool {
        guard !isDesktop, !lastTargets.isEmpty else { return false }
        return lastTargets.allSatisfy { isInPlace(stack: stack, target: $0, overlays: overlays) }
    }

    /// Sanft einblenden? Nur, wenn ein neues Ziel kommt UND die Abdunklung vorher nicht zu sehen war.
    ///
    /// Bis 0.5.5 wurde sie bei jedem neuen Ziel auf 0 gesetzt und neu eingeblendet, auch wenn sie
    /// schon stand: Bei jedem App-Wechsel per Klick war der ganze Hintergrund ~0,3 s hell (Video
    /// Michael 12.10., 15:57; gemessen Alpha 1 → 0,3 → 1 bei Outlook ↔ Edge). Steht sie schon, wird
    /// sie nur unter das neue Ziel geschoben.
    static func fadesIn(targetChanged: Bool, alreadyShown: Bool) -> Bool {
        targetChanged && !alreadyShown
    }

    /// Je Bildschirm (Michael, 16.10.): Unter welches Fenster gehört die Abdunklung jedes
    /// Bildschirms? `screens`/`modes` in derselben Reihenfolge wie die Abdunkel-Fenster.
    /// `.off` → nil (keine Abdunklung). Bildschirm des vorderen Fensters und `.dim` → `front`.
    /// `.topBright` → oberstes Fenster des Bildschirms (es zählt für den Bildschirm, auf dem der
    /// größte Teil liegt); ohne Fenster → `front` (ganz dunkel).
    static func screenTargets(stack: [StackWindow], screens: [DimScreen], front: Int,
                              exclude: Set<Int>, eligible: (StackWindow) -> Bool) -> [Int?] {
        let frames = screens.map(\.frame)
        let frontScreen = stack.first { $0.number == front }.flatMap { screenIndex(of: $0.bounds, in: frames) }
        return screens.indices.map { i in
            if screens[i].mode == .off { return nil }
            guard i != frontScreen, screens[i].mode == .topBright else { return front }
            return stack.first {
                !exclude.contains($0.number) && eligible($0) && screenIndex(of: $0.bounds, in: frames) == i
            }?.number ?? front
        }
    }

    /// Löcher im Abdunkel-Fenster (Apps nie abdunkeln, alle Fenster der aktiven App hell).
    /// Maler-Verfahren über die Fenster UNTER dem Ziel auf diesem Bildschirm, von hinten nach vorn:
    /// helles Fenster = Loch, ein anderes Fenster darüber = dort wieder dunkel. Vor dem hintersten
    /// hellen Fenster ist ohnehin alles dunkel; ein dunkles Fenster zählt nur, wenn es ein Loch
    /// darunter überdeckt. Leer = keine Löcher.
    static func paints(stack: [StackWindow], below target: Int, screen: CGRect, exclude: Set<Int>,
                       bright: (StackWindow) -> Bool) -> [DimPaint] {
        guard let ti = stack.firstIndex(where: { $0.number == target }) else { return [] }
        var out: [DimPaint] = []
        for w in stack[(ti + 1)...].reversed() where !exclude.contains(w.number) {
            let r = w.bounds.intersection(screen)
            guard !r.isNull, !r.isEmpty else { continue }
            if bright(w) {
                out.append(DimPaint(rect: r, bright: true))
            } else if out.contains(where: { $0.bright && $0.rect.intersects(r) }) {
                out.append(DimPaint(rect: r, bright: false))
            }
        }
        return out
    }

    /// Liegt auf diesem Bildschirm gerade ein Space ohne Abdunkeln vorn?
    static func spaceOff(_ spaces: [SpaceInfo], display: String?, offKeys: Set<String>) -> Bool {
        guard !offKeys.isEmpty, let c = SpaceNames.current(spaces, display: display) else { return false }
        return offKeys.contains(c.key)
    }

    /// Bildschirm mit der größten Überschneidung, nil = liegt auf keinem.
    static func screenIndex(of r: CGRect, in screens: [CGRect]) -> Int? {
        let areas = screens.map { s -> CGFloat in
            let x = s.intersection(r)
            return x.isNull ? 0 : x.width * x.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }
}

/// Hintergrund abdunkeln wie HazeOver (docs/SECURE-DESIGN.md E13).
///
/// Je Bildschirm ein randloses, halbdurchsichtiges Fenster, durch das Klicks gehen. Es wird in
/// der Stapelreihenfolge direkt UNTER das aktive Fenster einsortiert (bei einem Paar unter beide).
/// Gemessen 09.10.: `order(.below, relativeTo:)` mit der Nummer eines fremden Fensters wirkt,
/// die vordere App bleibt vorn. Seam liest dafür nur Nummer, Prozess und Lage aus der
/// Fensterliste, keine Titel.
@MainActor
final class Dimmer {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "abdunkeln")

    private let prefs: Preferences
    /// Partner eines Paars (E12), gesetzt von der Engine.
    var partnerOf: ((AXWindow) -> AXWindow?)?

    /// Ein Abdunkel-Fenster je Bildschirm, dazu dessen Kennung und Lage (gleiche Reihenfolge).
    private var overlays: [NSWindow] = []
    private var screens: [OverlayScreen] = []

    /// Bildschirm eines Abdunkel-Fensters: Kennung (UUID, Schlüssel der Einstellungen) und Lage.
    private struct OverlayScreen {
        let uuid: String?
        let ax: CGRect
        let appKit: CGRect
    }
    /// Oberstes helles Fenster der vorderen App (bzw. Paar-Partner).
    private var lastTarget: Int?
    /// Plan je Abdunkel-Fenster (Ziel, Löcher, Stärke), gleiche Reihenfolge wie `overlays`.
    private var lastPlans: [DimScreenPlan] = []
    /// Je Bildschirm: Space ohne Abdunkeln vorn? Beim letzten vollständigen Lauf gelesen,
    /// die Selbstheilung nutzt ihn weiter (Space-Wechsel melden sich selbst).
    private var lastSpaceOff: [Bool] = []
    /// Bundle-ID je Prozess, nur für „Apps nie abdunkeln“, je Lauf im Speicher (E13, 0.6).
    private var bundleIDs: [pid_t: String] = [:]
    /// Normale App (Dock-Symbol)? Über die Läufe gemerkt, damit die Selbstheilung 1×/s nicht jedes Mal
    /// `NSRunningApplication` fragt (Rafter-Review 16.10.). Beim App-Ende vergessen.
    private var regularApps: [pid_t: Bool] = [:]
    /// Nachkorrekturen in Folge (`scheduleVerify`), begrenzt gegen eine Schleife.
    private var verifyRetries = 0
    private var tokens: [NSObjectProtocol] = []
    /// Je App ein Beobachter, einmal angelegt und behalten (Code-Audit 09.10., P1: vorher bei
    /// JEDEM App-Wechsel abgebaut und neu angemeldet, gemessen 39 ms Hauptthread je Wechsel).
    /// Entfernt, wenn die App endet. Nur gespeichert, wenn mindestens eine Anmeldung klappte (R11).
    private var observers: [pid_t: AXObserver] = [:]
    /// Vordere App beim letzten vollständigen Lauf (für den günstigen Selbstheil-Takt, P4).
    private var lastFrontPID: pid_t?
    private var healTimer: Timer?

    init(prefs: Preferences) { self.prefs = prefs }

    // MARK: - Ein/Aus

    func apply() {
        if prefs.dimEnabled { start() } else { stop() }
    }

    private func start() {
        if tokens.isEmpty {
            let ws = NSWorkspace.shared.notificationCenter
            tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontAppChanged() }
            })
            tokens.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                // Prozessnummer kann später eine andere App bekommen: Bundle-ID vergessen.
                MainActor.assumeIsolated { self?.removeObserver(pid); self?.bundleIDs[pid] = nil; self?.regularApps[pid] = nil }
            })
            tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
            tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildOverlays(); self?.update() }
            })
            // Selbstheilung: verschluckte Meldungen, Fenster anderer Apps, die sich nach vorn drängen.
            // Günstiger Lauf ohne Bedienungshilfen, solange alles richtig liegt (P4/R2).
            let heal = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(heal: true) }
            }
            heal.tolerance = 0.3
            healTimer = heal
        }
        rebuildOverlays()
        frontAppChanged()
    }

    private func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        healTimer?.invalidate()
        healTimer = nil
        for pid in Array(observers.keys) { removeObserver(pid) }
        lastFrontPID = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        screens = []
        lastTarget = nil
        lastPlans = []
        lastSpaceOff = []
        bundleIDs = [:]
        regularApps = [:]
    }

    /// Von außen anstoßen (Paar-Partner angehoben, Einstellung je Bildschirm/App/Space geändert).
    /// Nur neu einsortieren und zeichnen, nicht neu aufbauen: kein Blitzen.
    func refresh() {
        guard prefs.dimEnabled else { return }
        update()
    }

    // MARK: - Auslöser

    private func frontAppChanged() {
        attachObserver()
        // Die Aktivierung sortiert die Fenster erst kurz nach der Meldung um (gemessen 09.10.,
        // ~26 ms). Darum jetzt, nach 150 ms und nach 450 ms (dann ist auch ein Paar-Partner oben).
        update()
        for delay in [0.15, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.update() }
            }
        }
    }

    /// Fokus/neue Fenster innerhalb der vorderen App. Einmal je App angelegt (P1).
    private func attachObserver() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            MainActor.assumeIsolated {
                let d = Unmanaged<Dimmer>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak d] in
                    MainActor.assumeIsolated { d?.update() }
                }
            }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, AXWindow.timeout)
        let ok = [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXMainWindowChangedNotification]
            .map { AXObserverAddNotification(obs, el, $0 as CFString, me) == .success }
            .contains(true)
        // Nichts angemeldet (App antwortet noch nicht): nicht merken, nächste Aktivierung versucht neu (R11).
        guard ok else {
            Self.log.notice("Abdunkeln: Beobachter für pid \(pid) nicht angemeldet, später neu")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observers[pid] = obs
    }

    private func removeObserver(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        // Nicht im eigenen Rückruf freigeben (wie PairKeeper, rafter-code-review 09.10.).
        DispatchQueue.main.async { withExtendedLifetime(obs) {} }
    }

    // MARK: - Einsortieren

    /// `heal`: Selbstheil-Takt. Liegt die Abdunklung noch richtig unter demselben Ziel und ist
    /// dieselbe App vorn, endet der Lauf ohne Bedienungshilfen-Aufruf (P4/R2: vorher jede Sekunde
    /// eine Abfrage in die vordere App, bei hängender App bis 0,25–0,75 s Hauptthread).
    private func update(heal: Bool = false) {
        guard prefs.dimEnabled, !overlays.isEmpty else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return hide("keine vordere App") }
        let pid = app.processIdentifier
        let own = Set(overlays.map(\.windowNumber))
        let stack = WindowList.onScreen(excludingOwn: false)
        if heal, isSettled(front: pid, stack: stack, own: own) { return }
        lastFrontPID = pid
        let me = ProcessInfo.processInfo.processIdentifier
        let focused = pid == me ? nil : AXAccess.focusedWindow(of: pid)
        // Schreibtisch vorn (Finder ohne Fokusfenster): nicht abdunkeln. Jede andere App ohne
        // Fokusfenster geht ab 0.6.1 weiter über die Fensterliste: macOS meldet beim Öffnen und
        // Schließen von Zusatzfenstern (Sichern-Dialog, Linkanzeige, Download-Liste) kurz kein
        // Fokusfenster; bis 0.6.0 ging die Abdunklung dann aus und wieder an (Video 16.10.).
        if focused == nil, pid != me, app.bundleIdentifier == "com.apple.finder" {
            return keepOrHide(app, focused: false, stack: stack, own: own, reason: "kein Fokusfenster")
        }
        var partner: (pid_t, CGRect)?
        if let f = focused, let p = partnerOf?(f), let pf = p.frame { partner = (p.pid, pf) }
        // Kurz kein Fokusfenster (Zusatzfenster geht auf oder zu): altes Ziel behalten, solange es
        // noch da ist und zur vorderen App gehört — nicht auf ein flüchtiges Fenster springen.
        let keptTarget = focused == nil ? lastTarget.flatMap { lt in
            stack.contains { $0.number == lt && $0.pid == pid } ? lt : nil
        } : nil
        guard let target = keptTarget ?? DimPlan.target(stack: stack, frontPID: pid, partner: partner, exclude: own,
                                                        focused: focused?.frame) else {
            return keepOrHide(app, focused: focused != nil, stack: stack, own: own, reason: "kein Fenster der vorderen App")
        }
        let spaceOff = currentSpaceOff()
        lastSpaceOff = spaceOff
        let plans = makePlans(front: target, frontPID: pid, stack: stack, own: own, spaceOff: spaceOff)
        if target == lastTarget, plans == lastPlans, allInPlace(plans, stack: stack, own: own) { return }
        place(plans, front: target)
    }

    /// Plan je Abdunkel-Fenster aus den Einstellungen je Bildschirm, App und Space (0.6, E13).
    /// Auf anderen Bildschirmen zählt als „oberstes Fenster“ nur eines einer normalen App
    /// (Dock-Symbol), mindestens 50 × 50 pt, nicht Seams eigenes. Löcher bekommen Fenster der
    /// vorderen App („alle Fenster der aktiven App hell“) und der Apps in „nie abdunkeln“.
    private func makePlans(front: Int, frontPID: pid_t, stack: [StackWindow], own: Set<Int>,
                           spaceOff: [Bool]) -> [DimScreenPlan] {
        let modes = screens.indices.map { i -> DimScreenMode in
            i < spaceOff.count && spaceOff[i] ? .off : prefs.dimMode(for: screens[i].uuid)
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let setup = screens.indices.map { DimScreen(frame: screens[$0].ax, mode: modes[$0]) }
        let targets = DimPlan.screenTargets(stack: stack, screens: setup, front: front, exclude: own) { w in
            guard w.pid != me, DimPlan.isRealWindow(w) else { return false }
            if let r = regularApps[w.pid] { return r }
            let r = WindowList.isRegularApp(w.pid)
            regularApps[w.pid] = r
            return r
        }
        let allFront = prefs.dimActiveAppAll
        let never = Set(prefs.dimNeverApps)
        return screens.indices.map { i in
            let strength = prefs.dimStrength(for: screens[i].uuid)
            guard let t = targets[i] else { return DimScreenPlan(target: nil, paints: [], strength: strength) }
            let paints = (allFront || !never.isEmpty)
                ? DimPlan.paints(stack: stack, below: t, screen: screens[i].ax, exclude: own) { w in
                    (allFront && w.pid == frontPID) || (!never.isEmpty && never.contains(bundleID(w.pid)))
                }
                : []
            return DimScreenPlan(target: t, paints: paints, strength: strength)
        }
    }

    /// Bundle-ID nur zum Vergleich mit „nie abdunkeln“, je Lauf zwischengespeichert, nie protokolliert.
    private func bundleID(_ pid: pid_t) -> String {
        if let id = bundleIDs[pid] { return id }
        // Kein Ergebnis (Prozess startet noch): nicht merken, sonst bliebe die App bis zu ihrem Ende dunkel.
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return "" }
        bundleIDs[pid] = id
        return id
    }

    /// Je Bildschirm: liegt ein Space ohne Abdunkeln vorn? Liest Spaces nur, wenn welche gewählt sind.
    private func currentSpaceOff() -> [Bool] {
        let off = Set(prefs.dimOffSpaces)
        guard !off.isEmpty, let spaces = SpaceReader.read() else { return screens.map { _ in false } }
        return screens.map { DimPlan.spaceOff(spaces, display: $0.uuid, offKeys: off) }
    }

    /// Ziele der sichtbaren Abdunkel-Fenster.
    private func activeTargets(_ plans: [DimScreenPlan]) -> [Int] { plans.compactMap(\.target) }

    private func allInPlace(_ plans: [DimScreenPlan], stack: [StackWindow], own: Set<Int>) -> Bool {
        Set(activeTargets(plans)).allSatisfy { DimPlan.isInPlace(stack: stack, target: $0, overlays: own) }
    }

    /// Abdunkel-Fenster unter ihr Ziel einsortieren (oder ausblenden), Löcher und Stärke zeichnen;
    /// nur aus dem Unsichtbaren sanft einblenden (`DimPlan.fadesIn`). Steht die Abdunklung schon,
    /// wird sie nur verschoben — kein Blitzen.
    private func place(_ plans: [DimScreenPlan], front: Int) {
        let changed = front != lastTarget || plans.map(\.target) != lastPlans.map(\.target)
        let shown = overlays.contains { $0.isVisible && $0.alphaValue > 0.5 }
        let fade = DimPlan.fadesIn(targetChanged: changed, alreadyShown: shown)
        lastTarget = front
        lastPlans = plans
        let h = Screens.primaryHeight
        for (i, o) in overlays.enumerated() where i < plans.count && i < screens.count {
            let p = plans[i]
            guard let t = p.target else {
                o.orderOut(nil)
                continue
            }
            let origin = screens[i].appKit.origin
            (o.contentView as? DimView)?.show(
                color: Self.color(p.strength),
                paints: p.paints.map {
                    let r = Geometry.toAppKit($0.rect, primaryHeight: h)
                    return DimPaint(rect: r.offsetBy(dx: -origin.x, dy: -origin.y), bright: $0.bright)
                })
            if fade { o.alphaValue = 0 }
            o.order(.below, relativeTo: t)
        }
        scheduleVerify()
        guard fade else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for o in overlays { o.animator().alphaValue = 1 }
        }
    }

    /// Nach dem Einsortieren nachsehen, ob die Abdunklung wirklich unter ihrem Ziel liegt. Schließt sich
    /// das Ziel zwischen Lesen der Fensterliste und Einsortieren, legt macOS sie ganz nach unten
    /// (gemessen 16.10.: 130 ms hell, bis die Selbstheilung kam). Höchstens drei Versuche am Stück.
    private func scheduleVerify() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lastTarget != nil else { return }
                let own = Set(self.overlays.map(\.windowNumber))
                if self.allInPlace(self.lastPlans, stack: WindowList.onScreen(excludingOwn: false), own: own) {
                    self.verifyRetries = 0
                } else if self.verifyRetries < 3 {
                    self.verifyRetries += 1
                    self.update()
                }
            }
        }
    }

    /// Gleiche App vorn und jede Abdunklung liegt noch direkt unter demselben Ziel, mit denselben
    /// Löchern? Rechnet den Plan nur aus der Fensterliste nach (kein AX) — sonst bliebe ein auf
    /// einem anderen Bildschirm geschlossenes oder verschobenes Fenster unbemerkt.
    private func isSettled(front pid: pid_t, stack: [StackWindow], own: Set<Int>) -> Bool {
        guard pid == lastFrontPID, let t = lastTarget else { return false }
        return makePlans(front: t, frontPID: pid, stack: stack, own: own, spaceOff: lastSpaceOff) == lastPlans
            && allInPlace(lastPlans, stack: stack, own: own)
    }

    /// Kein Ziel vorn: stehen lassen oder aufheben (`DimPlan.keepWithoutTarget`). Protokolliert wird
    /// nur die Prozessnummer, kein App-Name (E13: fürs Abdunkeln nur Nummer, Prozess, Lage).
    /// Die Kennung der vorderen App dient allein dem Vergleich „ist es der Finder?“ (Schreibtisch).
    private func keepOrHide(_ app: NSRunningApplication, focused: Bool, stack: [StackWindow], own: Set<Int>,
                            reason: String) {
        let pid = app.processIdentifier
        let desktop = app.bundleIdentifier == "com.apple.finder" && !focused
        if lastTarget != nil,
           DimPlan.keepWithoutTarget(isDesktop: desktop, stack: stack, lastTargets: activeTargets(lastPlans), overlays: own) {
            Self.log.notice("Abdunklung bleibt: \(reason, privacy: .public) (pid \(pid))")
            return
        }
        hide("\(reason) (pid \(pid))")
    }

    private func hide(_ reason: String) {
        guard lastTarget != nil || overlays.contains(where: \.isVisible) else { return }
        lastTarget = nil
        lastPlans = []
        overlays.forEach { $0.orderOut(nil) }
        Self.log.notice("Abdunklung aus: \(reason, privacy: .public)")
    }

    // MARK: - Fenster

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        let h = Screens.primaryHeight
        screens = NSScreen.screens.map {
            OverlayScreen(uuid: SpaceReader.displayIdentifier(of: $0), ax: Geometry.toAX($0.frame, primaryHeight: h),
                          appKit: $0.frame)
        }
        overlays = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            // Farbe zeichnet die DimView (mit Löchern), das Fenster selbst ist durchsichtig.
            w.backgroundColor = .clear
            w.contentView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .normal
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.setFrame(screen.frame, display: false)
            return w
        }
        lastTarget = nil
        lastPlans = []
    }

    private static func color(_ percent: Int) -> NSColor {
        NSColor.black.withAlphaComponent(CGFloat(percent) / 100)
    }
}

/// Inhalt eines Abdunkel-Fensters: ganze Fläche in der Abdunkel-Farbe, darauf die Malschritte
/// (`DimPlan.paints`, schon in Fenster-Koordinaten) — hell = Loch, sonst wieder dunkel.
/// Neu gezeichnet wird nur, wenn sich Farbe oder Löcher ändern.
final class DimView: NSView {
    private var color = NSColor.clear
    private var paints: [DimPaint] = []

    func show(color: NSColor, paints: [DimPaint]) {
        guard color != self.color || paints != self.paints else { return }
        self.color = color
        self.paints = paints
        needsDisplay = true
        #if DEBUG
        dumpIfRequested()
        #endif
    }

    #if DEBUG
    /// Nur Debug: `-dumpDim <ordner>` legt nach jeder Änderung das gezeichnete Bild als
    /// `dim-<Bildschirmbreite>.png` ab (ein Viertel groß). Messpunkt für den Sichttest — Claude darf
    /// keine Bildschirmfotos machen; so lässt sich prüfen, ob die Löcher an der richtigen Stelle sitzen.
    private func dumpIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-dumpDim"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1]).appendingPathComponent("dim-\(Int(bounds.width)).png")
        DispatchQueue.main.async { [weak self] in
            guard let self, let rep = self.bitmapImageRepForCachingDisplay(in: self.bounds) else { return }
            self.cacheDisplay(in: self.bounds, to: rep)
            let small = NSImage(size: NSSize(width: self.bounds.width / 4, height: self.bounds.height / 4))
            small.lockFocus()
            rep.draw(in: NSRect(origin: .zero, size: small.size))
            small.unlockFocus()
            guard let tiff = small.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }
    #endif

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // `.copy` setzt die Deckkraft, statt sie zu stapeln: „wieder dunkel“ über schon dunkler Fläche
        // ergab sonst 0,75 statt 0,5 (gemessen 16.10. am Dump: Tippi und Finder über einem Loch).
        ctx.setBlendMode(.copy)
        ctx.setFillColor(color.cgColor)
        ctx.fill(bounds)
        for p in paints {
            if p.bright {
                ctx.clear(p.rect)
            } else {
                ctx.fill(p.rect)
            }
        }
    }
}
