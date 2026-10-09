import AppKit
import OSLog

/// Führt Kommandos auf einem Fenster aus und merkt sich dessen ursprüngliche Größe.
@MainActor
final class WindowActions {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "aktion")
    private let prefs: Preferences
    /// Gemeinsame Schreib-Warteschlange der App (R4), auch von DragController genutzt.
    let writer = NeighborWriter()

    /// Rahmen vor dem ersten Andocken. Nur im Speicher, an die AX-Referenz
    /// gebunden, nach einem Neustart weg (docs/SECURE-DESIGN.md E10).
    private var original: [AXWindow: CGRect] = [:]

    /// ⌃⌥S hat ein Paar gebildet (E12). Gesetzt von der Engine (`PairKeeper.pair`). Aufgerufen
    /// erst, NACHDEM beide Rahmen gesetzt sind (Code-Audit 09.10., C6: vorher sofort, ein
    /// Aktivierungs-Anlass dazwischen sah die alten Rahmen und löste das Paar gleich wieder auf).
    var onSplit: ((AXWindow, AXWindow) -> Void)?

    /// Zuletzt in Auftrag gegebene Soll-Rahmen, bis der Writer sie gesetzt hat (Code-Audit 09.10.,
    /// R5: zweimal schnell ⌃⌥⇧→ las beim zweiten Druck noch den alten Rahmen, eine Stufe ging verloren).
    private var planned: [AXWindow: CGRect] = [:]

    init(prefs: Preferences) { self.prefs = prefs }

    /// Rahmen fürs Rechnen: der noch nicht gesetzte Soll-Rahmen, sonst der gelesene.
    private func frame(of w: AXWindow) -> CGRect? { planned[w] ?? w.frame }

    /// Tastenkürzel: wirkt auf das fokussierte Fenster. Den Befehl bestimmt die Ausrichtung des
    /// Bildschirms, auf dem das Fenster liegt (Kürzel gibt es je Ausrichtung).
    func perform(_ key: KeyCombo) {
        guard let w = AXAccess.focusedWindow(), let f = frame(of: w), let screen = Screens.best(for: f) else {
            Self.log.notice("Kürzel \(key.label, privacy: .public): kein verwaltbares Fenster im Fokus")
            return
        }
        guard let cmd = Layout.command(for: key, screen.orientation) else {
            Self.log.notice("Kürzel \(key.label, privacy: .public): auf diesem Bildschirm nicht belegt")
            return
        }
        run(cmd, on: w, frame: f, screen: screen)
    }

    /// Befehl aus dem Popover (0.4): direkt der Befehl, nicht das Kürzel. Code-Audit 09.10., C1:
    /// vorher wurde das Kürzel nach der Bildschirmausrichtung aufgelöst, auf einem Hochkant-
    /// Bildschirm taten manche Kacheln nichts oder etwas anderes.
    func perform(_ cmd: Command, on w: AXWindow) {
        guard let f = frame(of: w), let screen = Screens.best(for: f) else {
            Self.log.notice("\(cmd.rawValue, privacy: .public): Rahmen von \(w.logName, privacy: .public) nicht lesbar")
            return
        }
        run(cmd, on: w, frame: f, screen: screen)
    }

    private func run(_ cmd: Command, on w: AXWindow, frame f: CGRect, screen: Screens.Info) {
        switch cmd {
        case .split: split(w, f, screen)
        case .seamLeft: moveSeam(w, f, screen, direction: -1)
        case .seamRight: moveSeam(w, f, screen, direction: 1)
        default: apply(cmd, to: w, current: f, screen: screen, before: f)
        }
    }

    // MARK: - Geteilter Bildschirm (Michael, 08.10.)

    /// Zuletzt geteiltes Paar. Hilft „Naht verschieben“, wenn die Fenster nicht mehr
    /// bündig stehen. Nur im Speicher (E10).
    private var lastPair: (AXWindow, AXWindow)?

    /// ⌃⌥S: aktives Fenster und das nächste dahinter teilen sich den Bildschirm, beide
    /// volle Höhe, Naht in der Mitte. **Jedes bleibt auf seiner Seite:** Wer weiter links
    /// (hochkant: oben) steht, kommt links hin. Michael, 08.10.: Zuerst kam immer das aktive
    /// Fenster nach links, „Outlook springt von links nach rechts“.
    private func split(_ w: AXWindow, _ f: CGRect, _ screen: Screens.Info) {
        guard let (partner, pf) = WindowFinder.nextWindow(after: w, frame: f, on: screen.frame) else {
            Self.log.notice("Teilen: kein zweites Fenster auf diesem Bildschirm")
            return
        }
        if original[w] == nil { original[w] = f }
        if original[partner] == nil { original[partner] = pf }
        let wFirst = Geometry.comesFirst(f, before: pf, screen.orientation)
        let (first, second) = wFirst ? (w, partner) : (partner, w)
        lastPair = (first, second)
        let (a, b) = Geometry.splitFrames(at: 12, in: screen.visible, screen.orientation, gap: CGFloat(prefs.gap))
        setPair((first, a), (second, b), name: "Teilen") { [weak self] in self?.onSplit?(first, second) }
    }

    /// ⌃⌥⇧← / → : Naht zur nächsten festen Stufe (⅓ ⅜ ½ ⅝ ⅔). Beide Fenster in einem
    /// Schritt; jedes behält seine eigene Höhe (bzw. Breite hochkant).
    private func moveSeam(_ w: AXWindow, _ f: CGRect, _ screen: Screens.Info, direction: Int) {
        let gap = CGFloat(prefs.gap), o = screen.orientation, v = screen.visible
        guard let (other, of) = seamPartner(of: w, frame: f, gap: gap, orientation: o) else {
            Self.log.notice("Naht: kein Nachbar an einer gemeinsamen Kante, erst ⌃⌥S")
            return
        }
        let wFirst = Geometry.comesFirst(f, before: of, o)
        let (first, ff) = wFirst ? (w, f) : (other, of)
        let (second, sf) = wFirst ? (other, of) : (w, f)
        let seamPx = o == .landscape ? ff.maxX + gap / 2 : ff.maxY + gap / 2
        let cell = o == .landscape ? v.width / 24 : v.height / 24
        let current = (seamPx - (o == .landscape ? v.minX : v.minY)) / cell
        guard let stop = Geometry.nextSeamStop(current: current, direction: direction) else {
            Self.log.notice("Naht: schon an der äußersten Stufe")
            return
        }
        let (a, b) = Geometry.splitFrames(at: stop, in: v, o, gap: gap)
        let fa = o == .landscape ? CGRect(x: a.minX, y: ff.minY, width: a.width, height: ff.height)
                                 : CGRect(x: ff.minX, y: a.minY, width: ff.width, height: a.height)
        let fb = o == .landscape ? CGRect(x: b.minX, y: sf.minY, width: b.width, height: sf.height)
                                 : CGRect(x: sf.minX, y: b.minY, width: sf.width, height: b.height)
        lastPair = (first, second)
        setPair((first, fa), (second, fb), name: "Naht \(stop)/24")
    }

    /// Partner für die Naht: ein bündiger Nachbar auf der passenden Achse, sonst das
    /// zuletzt geteilte Paar.
    private func seamPartner(of w: AXWindow, frame f: CGRect, gap: CGFloat, orientation o: Orientation) -> (AXWindow, CGRect)? {
        let side: [Geometry.Edge] = o == .landscape ? [.left, .right] : [.top, .bottom]
        for (n, nf) in WindowFinder.neighbors(of: w, frame: f, gap: gap)
        where side.contains(where: { Geometry.isFacing(nf, to: f, gap: gap, edge: $0) }) {
            return (n, planned[n] ?? nf)
        }
        if let (a, b) = lastPair, a == w || b == w {
            let other = a == w ? b : a
            if let of = frame(of: other) { return (other, of) }
        }
        return nil
    }

    /// Setzt zwei Fenster nacheinander mit Nachprüfung. Hat eines eine Mindestgröße,
    /// bleibt die Naht dort stehen und das andere passt sich an (wie beim Ziehen).
    private func setPair(_ first: (AXWindow, CGRect), _ second: (AXWindow, CGRect), name: String,
                         done: (@MainActor @Sendable () -> Void)? = nil) {
        let log = Self.log
        let jobs = [first, second]
        plan(jobs)
        writer.run { [weak self] in
            let a1 = NeighborWriter.setVerified(first.0, first.1)
            let a2 = NeighborWriter.setVerified(second.0, second.1)
            if let a2, let fix = Geometry.resolveMinimum(leading: first.1, wanted: second.1, actual: a2) {
                NeighborWriter.setVerified(second.0, fix.neighbor)
                NeighborWriter.setVerified(first.0, fix.leading)
                log.notice("\(name, privacy: .public): Mindestgröße rechts/unten, Naht gehalten")
            } else if let a1, let fix = Geometry.resolveMinimum(leading: second.1, wanted: first.1, actual: a1) {
                NeighborWriter.setVerified(first.0, fix.neighbor)
                NeighborWriter.setVerified(second.0, fix.leading)
                log.notice("\(name, privacy: .public): Mindestgröße links/oben, Naht gehalten")
            }
            log.notice("\(name, privacy: .public): \(first.0.logName, privacy: .public) + \(second.0.logName, privacy: .public) | Soll \(NSStringFromRect(first.1), privacy: .public) + \(NSStringFromRect(second.1), privacy: .public), Ist \(a1.map(NSStringFromRect) ?? "–", privacy: .public) + \(a2.map(NSStringFromRect) ?? "–", privacy: .public)")
            Task { @MainActor in
                self?.unplan(jobs)
                done?()
            }
        }
    }

    private func plan(_ jobs: [(AXWindow, CGRect)]) {
        for (w, r) in jobs { planned[w] = r }
    }

    /// Nur entfernen, was noch von DIESEM Auftrag stammt (ein neuerer hat Vorrang).
    private func unplan(_ jobs: [(AXWindow, CGRect)]) {
        for (w, r) in jobs where planned[w] == r { planned[w] = nil }
    }

    /// `before` = Rahmen vor der Geste (beim Andocken per Ziehen der Rahmen vor dem Ziehen).
    func apply(_ cmd: Command, to w: AXWindow, current f: CGRect, screen: Screens.Info, before: CGRect) {
        let gap = CGFloat(prefs.gap)
        let target: CGRect?
        switch cmd {
        case .restore:
            target = original.removeValue(forKey: w).map { Geometry.clamp($0, to: screen.visible) }
            if target == nil { Self.log.notice("restore: keine ursprüngliche Größe gemerkt für \(w.logName, privacy: .public)") }
        case .center:
            target = Geometry.centered(f, in: screen.visible)
        case .nextDisplay, .previousDisplay:
            let all = Screens.ordered()
            guard all.count > 1, let i = all.firstIndex(of: screen) else {
                Self.log.notice("\(cmd.rawValue, privacy: .public): nur ein Bildschirm")
                return
            }
            let j = (i + (cmd == .nextDisplay ? 1 : all.count - 1)) % all.count
            target = Geometry.transfer(f, from: screen.visible, to: all[j].visible)
        default:
            guard let cells = Layout.spec(cmd, screen.orientation)?.target else {
                Self.log.notice("\(cmd.rawValue, privacy: .public): keine Zielfläche für diese Ausrichtung")
                return
            }
            if original[w] == nil { original[w] = before }
            target = Geometry.rect(for: cells, in: screen.visible, screen.orientation, gap: gap)
        }
        // Nachbarn mitsetzen: nur bei festen Flächen (Hälften, Viertel, Drittel), nicht
        // beim Zentrieren, Wiederherstellen oder Bildschirmwechsel.
        let partners: [(AXWindow, CGRect)]
        if let t = target, Layout.spec(cmd, screen.orientation)?.target != nil {
            partners = WindowFinder.complements(target: Geometry.clamp(t, to: screen.visible), visible: screen.visible,
                                                moving: w, movingFrame: f, gap: gap)
        } else {
            partners = []
        }
        guard let target else { return }
        let goal = Geometry.clamp(target, to: screen.visible)
        let log = Self.log, name = cmd.rawValue
        let jobs = [(w, goal)] + partners
        plan(jobs)
        // Mit Nachprüfung auf der Warteschlange: Edge landete beim ersten ⌃⌥→ auf
        // x 2449 / Breite 991 statt x 1723 / 1712 (gemessen 08.10.).
        writer.run { [weak self] in
            let result = NeighborWriter.setVerified(w, goal)
            // Messpunkt: Soll und Ist. Weicht die App ab (Mindestgröße), steht es hier.
            log.notice("\(name, privacy: .public): Soll \(NSStringFromRect(goal), privacy: .public) Ist \(result.map(NSStringFromRect) ?? "–", privacy: .public)")
            for (pw, pr) in partners {
                let ist = NeighborWriter.setVerified(pw, pr)
                log.notice("\(name, privacy: .public): Nachbar \(pw.logName, privacy: .public) mitgesetzt, Soll \(NSStringFromRect(pr), privacy: .public) Ist \(ist.map(NSStringFromRect) ?? "–", privacy: .public)")
            }
            Task { @MainActor in self?.unplan(jobs) }
        }
    }

    func wasSnapped(_ w: AXWindow) -> CGRect? { original[w] }
    func forget(_ w: AXWindow) { original[w] = nil }
}
