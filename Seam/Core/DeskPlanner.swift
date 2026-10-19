import CoreGraphics

// Layouts pro Space, Schritt 3 (specs/2026-10-19-layouts-plan.md): Soll gegen Ist, rein rechnend.
// Führt nichts aus. Die Zahl der ⌃←/⌃→-Schritte rechnet erst der Lauf aus dem dann aktuellen
// Zustand — ein vorab geplanter Wert wäre beim Ausführen womöglich schon veraltet.

/// Ein Schreibtisch aus dem Layout steht nicht da, wo er hingehört. Der Nutzer muss ihn in
/// Mission Control zurückziehen; Seam kann Spaces nicht verschieben (gemessen 19.10., E17a).
struct DeskIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Kein Space trägt den Namen bzw. den Platz gibt es nicht.
        case missing
        /// Der Space lebt, aber auf einem anderen Bildschirm (macOS hat ihn beim Neustart verschoben).
        case onOtherDisplay(String)
    }
    let desk: DeskRef
    let kind: Kind
}

/// Ein Fenster soll an seinen Platz.
struct DeskMove: Equatable, Sendable {
    let windowID: Int
    let bundleID: String
    /// Ziel-Space (wie er gerade heißt und liegt).
    let target: SpaceInfo
    /// Zielrahmen in Bedienungshilfen-Koordinaten; nil = Größe behalten (mehr Fenster als im Layout).
    let frame: CGRect?
    /// Liegt auf einem anderen Space → Greifen + ⌃←/⌃→ (E17a). Sonst nur Rahmen setzen.
    let changesSpace: Bool
}

struct DeskSkip: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case notRunning, deskUnavailable
        // Erst beim Ausführen (Schritt 5):
        /// Fenster für die Bedienungshilfen nicht erreichbar oder nicht eindeutig zuzuordnen.
        case notReachable
        /// Keine sichere Stelle zum Greifen bzw. das Fenster kam beim Ziehen nicht mit.
        case notGrabbable
        /// Nach der Fahrt lag das Fenster nicht auf dem Ziel-Space.
        case notVerified
        /// Am Platz, aber die App nahm die gespeicherte Größe nicht an.
        case sizeRefused
    }
    let bundleID: String
    let reason: Reason
}

struct DeskPlan: Equatable, Sendable {
    var issues: [DeskIssue] = []
    var moves: [DeskMove] = []
    var skipped: [DeskSkip] = []

    /// Weicht die Anordnung vom Layout ab? (Menü-Hinweis „speichern?“.) Nicht laufende Apps zählen nicht.
    var deviates: Bool { !issues.isEmpty || !moves.isEmpty }
}

enum DeskPlanner {

    /// Abweichung, unter der ein Rahmen als „sitzt“ gilt (Erfolgskriterium ±2 pt).
    static let tolerance: CGFloat = 2

    static func plan(layout: DeskLayout, spaces: [SpaceInfo], names: [String: String],
                     windows: [LiveWindow], screens: DeskScreens) -> DeskPlan {
        var plan = DeskPlan()
        let desks = spaces.filter { !$0.isFullScreen }
        var resolved: [DeskRef: SpaceInfo] = [:]
        // Nur Fenster auf einem bekannten, normalen Schreibtisch: Vollbild-Fenster oder Fenster auf
        // unbekannten Spaces kann Seam nie einsortieren (code-audit 19.10.: sonst dauerhaft
        // „nicht geschafft“ und „weicht ab“).
        let movable = Set(desks.map(\.managedID))
        var reported = Set<DeskRef>()

        for entry in layout.entries {
            let ref = entry.desk
            if resolved[ref] == nil && !reported.contains(ref) {
                switch resolve(ref, desks: desks, names: names) {
                case .success(let space): resolved[ref] = space
                case .failure(let issue): plan.issues.append(issue); reported.insert(ref)
                }
            }
            let mine = windows.filter { $0.bundleID == entry.bundleID && $0.spaceIDs.count == 1 && movable.contains($0.spaceIDs[0]) }
            guard !mine.isEmpty else {
                plan.skipped.append(DeskSkip(bundleID: entry.bundleID, reason: .notRunning)); continue
            }
            guard let target = resolved[ref], let screen = screens.frame(of: target.display) else {
                plan.skipped.append(DeskSkip(bundleID: entry.bundleID, reason: .deskUnavailable)); continue
            }
            // E5 (rafter-code-review 19.10., Fund 1): nie außerhalb des Bildschirms — auch nicht bei
            // veränderten Daten oder geänderter Auflösung.
            let wantedFrames = entry.frames.map { f -> CGRect in
                let r = f.rect.offsetBy(dx: screen.minX, dy: screen.minY)
                return Geometry.clamp(r, to: screens.bounds(for: r, display: target.display) ?? screen)
            }
            let assigned = assign(wantedFrames, to: mine.map(\.frame))
            for (i, w) in mine.enumerated() {
                let wanted = assigned[i]
                let onTarget = w.spaceIDs == [target.managedID]
                let frameFits = wanted.map { fits(w.frame, $0) } ?? true
                guard !(onTarget && frameFits) else { continue }
                plan.moves.append(DeskMove(windowID: w.windowID, bundleID: entry.bundleID, target: target,
                                           frame: wanted, changesSpace: !onTarget))
            }
        }
        return plan
    }

    /// Welcher lebende Space ist mit diesem Layout-Schreibtisch gemeint?
    /// Mit Namen: der Space mit dem Namen auf dem richtigen Bildschirm (bei Doppelten der passende
    /// Platz). Ohne Namen: der Platz auf dem Bildschirm.
    static func resolve(_ ref: DeskRef, desks: [SpaceInfo], names: [String: String]) -> Result<SpaceInfo, DeskIssue> {
        guard let name = ref.name else {
            if let s = desks.first(where: { $0.display == ref.display && $0.number == ref.number }) { return .success(s) }
            return .failure(DeskIssue(desk: ref, kind: .missing))
        }
        let named = desks.filter { names[$0.key] == name }
        let here = named.filter { $0.display == ref.display }
        if let s = here.first(where: { $0.number == ref.number }) ?? here.first { return .success(s) }
        if let elsewhere = named.first { return .failure(DeskIssue(desk: ref, kind: .onOtherDisplay(elsewhere.display))) }
        return .failure(DeskIssue(desk: ref, kind: .missing))
    }

    /// Jede gespeicherte Größe an das ähnlichste Fenster (gierig, nach Abstand von Mitte + Größe).
    /// Nicht nach Stapel-Reihenfolge: Die ändert sich mit jedem Klick, die Fenster würden sonst
    /// bei jedem Aufräumen die Plätze tauschen. Ergebnis je Fenster: Zielrahmen oder nil.
    static func assign(_ wanted: [CGRect], to current: [CGRect]) -> [CGRect?] {
        struct Pair { let cost: CGFloat, wanted: Int, current: Int }
        var pairs: [Pair] = []
        for (wi, w) in wanted.enumerated() {
            for (ci, c) in current.enumerated() {
                let cost = hypot(w.midX - c.midX, w.midY - c.midY) + abs(w.width - c.width) + abs(w.height - c.height)
                pairs.append(Pair(cost: cost, wanted: wi, current: ci))
            }
        }
        var out = [CGRect?](repeating: nil, count: current.count)
        var usedW = Set<Int>(), usedC = Set<Int>()
        let sorted = pairs.sorted {
            $0.cost != $1.cost ? $0.cost < $1.cost : ($0.wanted != $1.wanted ? $0.wanted < $1.wanted : $0.current < $1.current)
        }
        for p in sorted where !usedW.contains(p.wanted) && !usedC.contains(p.current) {
            out[p.current] = wanted[p.wanted]
            usedW.insert(p.wanted); usedC.insert(p.current)
        }
        return out
    }

    /// Abweichung der Größe, die als „sitzt“ gilt. Apps wie Terminal rasten auf Zeichenbreiten
    /// und -höhen ein und nehmen eine Größe nie aufs Punkt genau an (code-audit 19.10.).
    static let sizeTolerance: CGFloat = 24

    /// Sitzt ein Fenster? Lage auf ±2 pt, Größe auf ±24 pt.
    static func fits(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= sizeTolerance && abs(a.height - b.height) <= sizeTolerance
    }

    /// Gleiches Fenster? (Zuordnung Fensterliste ↔ Bedienungshilfen: streng, ±2 pt überall.)
    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

extension DeskIssue: Error {}
