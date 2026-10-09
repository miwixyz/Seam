import AppKit
import OSLog

/// Unter welches Fenster gehört die Abdunklung? Reine Rechnung, getestet.
enum DimPlan {

    /// `stack`: Fenster der Ebene 0 von vorn nach hinten. Hell bleibt das oberste Fenster der
    /// vorderen App (auch Dialoge und Bedienfelder) und — bei einem Paar — der Partner.
    /// Rückgabe: die Nummer des untersten hellen Fensters, oder nil = nicht abdunkeln.
    static func target(stack: [StackWindow], frontPID: pid_t, partner: (pid: pid_t, frame: CGRect)?,
                       exclude: Set<Int>) -> Int? {
        let visible = stack.filter { !exclude.contains($0.number) }
        guard let fi = visible.firstIndex(where: { $0.pid == frontPID }) else { return nil }
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

    private var overlays: [NSWindow] = []
    private var lastTarget: Int?
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
                MainActor.assumeIsolated { self?.removeObserver(pid) }
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
        lastTarget = nil
    }

    /// Stärke geändert.
    func strengthChanged() {
        for o in overlays { o.backgroundColor = Self.color(prefs.dimStrength) }
    }

    /// Von außen anstoßen (z. B. nachdem ein Paar-Partner angehoben wurde).
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
        // Schreibtisch vorn (Finder ohne Fokusfenster): nicht abdunkeln.
        let focused = pid == ProcessInfo.processInfo.processIdentifier ? nil : AXAccess.focusedWindow(of: pid)
        if focused == nil && pid != ProcessInfo.processInfo.processIdentifier { return hide("kein Fokusfenster") }
        var partner: (pid_t, CGRect)?
        if let f = focused, let p = partnerOf?(f), let pf = p.frame { partner = (p.pid, pf) }
        guard let target = DimPlan.target(stack: stack, frontPID: pid, partner: partner, exclude: own) else {
            return hide("kein Fenster der vorderen App")
        }
        if target == lastTarget, DimPlan.isInPlace(stack: stack, target: target, overlays: own) { return }
        place(below: target)
    }

    /// Abdunkel-Fenster unter `target` einsortieren; bei neuem Ziel sanft einblenden.
    private func place(below target: Int) {
        let changed = target != lastTarget
        lastTarget = target
        for o in overlays {
            if changed { o.alphaValue = 0 }
            o.order(.below, relativeTo: target)
        }
        guard changed else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for o in overlays { o.animator().alphaValue = 1 }
        }
    }

    /// Gleiche App vorn und die Abdunklung liegt noch direkt unter demselben Ziel?
    private func isSettled(front pid: pid_t, stack: [StackWindow], own: Set<Int>) -> Bool {
        guard pid == lastFrontPID, let t = lastTarget else { return false }
        return DimPlan.isInPlace(stack: stack, target: t, overlays: own)
    }

    private func hide(_ reason: String) {
        guard lastTarget != nil || overlays.contains(where: \.isVisible) else { return }
        lastTarget = nil
        overlays.forEach { $0.orderOut(nil) }
        Self.log.notice("Abdunklung aus: \(reason, privacy: .public)")
    }

    // MARK: - Fenster

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = Self.color(prefs.dimStrength)
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .normal
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.setFrame(screen.frame, display: false)
            return w
        }
        lastTarget = nil
    }

    private static func color(_ percent: Int) -> NSColor {
        NSColor.black.withAlphaComponent(CGFloat(percent) / 100)
    }
}
