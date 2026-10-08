import AppKit
import OSLog

/// Ein Eintrag der Fensterliste des Systems (nur Nummer, Prozess, Lage — keine Titel, E13).
struct StackWindow: Equatable {
    let number: Int
    let pid: pid_t
    let bounds: CGRect
}

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
              let pi = visible.firstIndex(where: { $0.pid == partner.pid && close($0.bounds, partner.frame) }),
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

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
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
    private var observer: (pid: pid_t, obs: AXObserver)?
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
            tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
            tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildOverlays(); self?.update() }
            })
            // Selbstheilung: verschluckte Meldungen, Fenster anderer Apps, die sich nach vorn drängen.
            healTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        rebuildOverlays()
        frontAppChanged()
    }

    private func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        healTimer?.invalidate()
        healTimer = nil
        detachObserver()
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

    /// Fokus/neue Fenster innerhalb der vorderen App.
    private func attachObserver() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if observer?.pid == pid { return }
        detachObserver()
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
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
        for n in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = (pid, obs)
    }

    private func detachObserver() {
        guard let o = observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o.obs), .commonModes)
        let retired = o.obs
        observer = nil
        // Nicht im eigenen Rückruf freigeben (wie PairKeeper, rafter-code-review 09.10.).
        DispatchQueue.main.async { withExtendedLifetime(retired) {} }
    }

    // MARK: - Einsortieren

    private func update() {
        guard prefs.dimEnabled, !overlays.isEmpty else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return hide("keine vordere App") }
        let pid = app.processIdentifier
        let own = Set(overlays.map(\.windowNumber))
        let stack = Self.stack()
        // Schreibtisch vorn (Finder ohne Fokusfenster): nicht abdunkeln.
        let focused = pid == ProcessInfo.processInfo.processIdentifier ? nil : AXAccess.focusedWindow(of: pid)
        if focused == nil && pid != ProcessInfo.processInfo.processIdentifier { return hide("kein Fokusfenster") }
        var partner: (pid_t, CGRect)?
        if let f = focused, let p = partnerOf?(f), let pf = p.frame { partner = (p.pid, pf) }
        guard let target = DimPlan.target(stack: stack, frontPID: pid, partner: partner, exclude: own) else {
            return hide("kein Fenster der vorderen App")
        }
        if target == lastTarget, DimPlan.isInPlace(stack: stack, target: target, overlays: own) { return }
        let changed = target != lastTarget
        lastTarget = target
        for o in overlays {
            if changed { o.alphaValue = 0 }
            o.order(.below, relativeTo: target)
        }
        if changed {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                for o in overlays { o.animator().alphaValue = 1 }
            }
        }
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

    /// Fensterliste Ebene 0, vorn zuerst. Nur Nummer, Prozess, Lage (E13).
    private static func stack() -> [StackWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return nil }
            return StackWindow(number: n, pid: pid, bounds: bounds)
        }
    }
}
