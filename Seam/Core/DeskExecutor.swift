import AppKit

// Layouts pro Space, Schritt 5: die Ausführung eines Plans (docs/SECURE-DESIGN.md E17b).
// Blockiert (InputSynth bis ~1 s je Schritt) — nur von einer eigenen Warteschlange aufrufen.
// Getrennt von DeskRunner, damit sie ohne Einstellungen prüfbar ist.
/// Warum ein Lauf nicht startet.
enum DeskBlock: Equatable, Sendable {
    case noLayout, noAccessibility, switchKeysOff, screenLocked, fullScreenActive, cooldown, alreadyRunning
    /// macOS liefert gerade keine Liste der Spaces (code-audit 19.10.: vorher sah das aus wie
    /// „alle Schreibtische fehlen“ und führte zur falschen Anweisung).
    case spacesUnavailable
}

struct DeskRunResult: Equatable, Sendable {
    enum Abort: Equatable, Sendable { case userInput, modifiersStuck, timeLimit }
    var moved = 0
    var framed = 0
    var skipped: [DeskSkip] = []
    var issues: [DeskIssue] = []
    var aborted: Abort?
}

enum DeskRun {

    /// Höchstens ein automatischer Lauf je 2 Minuten (E17b): ein flatternder Bildschirm darf Maus
    /// und Tastatur nicht in Dauerschleife übernehmen.
    static let cooldown: TimeInterval = 120
    static let timeLimit: TimeInterval = 60

    struct Conditions: Equatable, Sendable {
        var hasLayout = true
        var trusted = true
        var switchKeys = true
        var locked = false
        var fullScreen = false
        var running = false
        var spacesReadable = true
    }

    /// Darf ein Lauf starten? nil = ja. Reihenfolge = was der Nutzer zuerst beheben muss.
    static func blocker(_ c: Conditions, automatic: Bool, lastAutomatic: Date?, now: Date) -> DeskBlock? {
        if c.running { return .alreadyRunning }
        if !c.hasLayout { return .noLayout }
        if !c.trusted { return .noAccessibility }
        if !c.spacesReadable { return .spacesUnavailable }
        if c.locked { return .screenLocked }
        if !c.switchKeys { return .switchKeysOff }
        if c.fullScreen { return .fullScreenActive }
        if automatic, let last = lastAutomatic, now.timeIntervalSince(last) < cooldown { return .cooldown }
        return nil
    }

    /// Schritte von einem Space zu einem anderen auf demselben Bildschirm (+ = nach rechts).
    /// nil = anderer Bildschirm oder Vollbild.
    static func steps(from current: SpaceInfo, to target: SpaceInfo) -> Int? {
        guard current.display == target.display, !current.isFullScreen, !target.isFullScreen else { return nil }
        return target.number - current.number
    }

    /// Welches Bedienungshilfen-Fenster gehört zu diesem Rahmen? Nur bei genau einem Treffer
    /// (±2 pt) — keine private Schnittstelle, im Zweifel auslassen (E17a).
    static func uniqueMatch(_ frames: [CGRect?], for target: CGRect) -> Int? {
        let hits = frames.indices.filter { frames[$0].map { DeskPlanner.close($0, target) } ?? false }
        return hits.count == 1 ? hits[0] : nil
    }

    static func isScreenLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        if (d["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        return (d["kCGSSessionOnConsoleKey"] as? Bool) == false
    }
}

enum DeskExecutor {

    /// Ergebnis eines einzelnen Fensters. `sizeRefused`: am Platz, aber die App nahm die Größe nicht an.
    private enum Step {
        case done(moved: Bool, framed: Bool, sizeRefused: Bool)
        case skip(DeskSkip.Reason)
        case abort(DeskRunResult.Abort)
    }

    static func execute(_ plan: DeskPlan, windows: [LiveWindow], screens: DeskScreens) -> DeskRunResult {
        var result = DeskRunResult(skipped: plan.skipped, issues: plan.issues)
        let deadline = Date().addingTimeInterval(DeskRun.timeLimit)
        let byID = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        // Sichtbarer Space je Bildschirm vor dem Lauf — am Ende dorthin zurück (`reach` schaltet
        // ggf. auf andere Spaces, um Fenster zu erreichen).
        let startViews = (SpaceReader.read() ?? []).filter(\.isCurrent)
        for move in plan.moves {
            if Date() > deadline { result.aborted = .timeLimit; break }
            switch perform(move, live: byID[move.windowID], screens: screens, deadline: deadline) {
            case .done(let moved, let framed, let refused):
                if moved { result.moved += 1 }
                if framed { result.framed += 1 }
                if refused { result.skipped.append(DeskSkip(bundleID: move.bundleID, reason: .sizeRefused)) }
            case .skip(let reason): result.skipped.append(DeskSkip(bundleID: move.bundleID, reason: reason))
            case .abort(let why): result.aborted = why
            }
            if result.aborted != nil { break }
        }
        // Greift der Nutzer gerade ein, nicht mehr umschalten — sonst Ansicht wiederherstellen.
        if result.aborted != .userInput {
            for view in startViews where view.display != "Main" || startViews.count == 1 {
                if case .abort(.userInput)? = viewBack(on: view.display, to: view, screens: screens, deadline: deadline) {
                    result.aborted = .userInput
                    break
                }
            }
        }
        return result
    }

    private static func perform(_ move: DeskMove, live: LiveWindow?, screens: DeskScreens, deadline: Date) -> Step {
        guard let live else { return .skip(.notReachable) }
        let ax: AXWindow
        switch reach(live, screens: screens, deadline: deadline) {
        case .success(let found): ax = found
        case .failure(let stop): return stop.step
        }
        var moved = false
        if move.changesSpace {
            if let stop = carry(ax, live: live, move: move, screens: screens, deadline: deadline) { return stop }
            moved = true
        }
        // Größe zählt nur, wenn sie wirklich sitzt (code-audit 19.10.: vorher still als Erfolg gezählt).
        guard let f = move.frame else { return .done(moved: moved, framed: false, sizeRefused: false) }
        let fits = ax.setFrame(f).map { DeskPlanner.fits($0, f) } ?? false
        return .done(moved: moved, framed: fits, sizeRefused: !fits)
    }

    private struct Halt: Error { let step: Step }

    /// Bedienungshilfen-Fenster holen. Liegt das Fenster auf einem Space, der gerade nicht sichtbar
    /// ist, erst die Ansicht seines Bildschirms dorthin schalten — Bedienungshilfen sehen nur
    /// sichtbare Spaces. Abnahme 19.10., 15:10: Nach dem Zurückziehen in Mission Control lagen 6
    /// Fenster auf einem verdeckten Space und wurden alle als „nicht erreichbar“ ausgelassen.
    private static func reach(_ live: LiveWindow, screens: DeskScreens, deadline: Date) -> Result<AXWindow, Halt> {
        if let ax = axWindow(for: live) { return .success(ax) }
        guard let source = space(of: live.windowID), !source.isCurrent,
              let now = visibleSpace(on: source.display), let steps = DeskRun.steps(from: now, to: source), steps != 0,
              let screen = screens.frame(of: source.display) else { return .failure(Halt(step: .skip(.notReachable))) }
        switch InputSynth.switchView(on: screen, by: steps, deadline: deadline) {
        case .moved: break
        case .interrupted: return .failure(Halt(step: .abort(.userInput)))
        case .modifiersStuck: return .failure(Halt(step: .abort(.modifiersStuck)))
        case .timeUp: return .failure(Halt(step: .abort(.timeLimit)))
        case .noGripPoint, .notGrabbed, .invalidSteps: return .failure(Halt(step: .skip(.notReachable)))
        }
        usleep(300_000)
        return axWindow(for: live).map { .success($0) } ?? .failure(Halt(step: .skip(.notReachable)))
    }

    /// Fenster auf den Ziel-Space tragen. nil = angekommen.
    private static func carry(_ ax: AXWindow, live: LiveWindow, move: DeskMove, screens: DeskScreens, deadline: Date) -> Step? {
        if let current = space(of: live.windowID), current.display != move.target.display {
            return carryAcross(ax, live: live, move: move, screens: screens, deadline: deadline)
        }
        guard let current = space(of: live.windowID), let steps = DeskRun.steps(from: current, to: move.target),
              let screen = screens.frame(of: move.target.display) else { return .skip(.notReachable) }
        guard steps != 0 else { return nil }
        // Gibt es einen zweiten Bildschirm mit eigenen Spaces, geht es ganz ohne Greifen (19.10.,
        // WhatsApp: Web-Oberfläche oben, Ziehen bewegte das Fenster nicht).
        if move.target.display != "Main", screens.frames.keys.contains(where: { $0 != move.target.display }) {
            return carryBounce(ax, live: live, move: move, screens: screens, deadline: deadline)
        }
        // Sichtbarer Space dieses Bildschirms vor der Fahrt — dorthin geht die Ansicht danach zurück.
        let viewBefore = visibleSpace(on: move.target.display)
        switch InputSynth.shift(ax, by: steps, deadline: deadline) {
        case .moved: break
        case .interrupted: return .abort(.userInput)
        case .modifiersStuck: return .abort(.modifiersStuck)
        case .timeUp: return .abort(.timeLimit)
        case .noGripPoint, .notGrabbed, .invalidSteps: return .skip(.notGrabbable)
        }
        let arrived = space(of: live.windowID)?.managedID == move.target.managedID
        // Ansicht zurück, damit der Ausgangs-Space sichtbar bleibt (weitere Fenster dort) und der
        // Nutzer am Ende dort steht, wo er war. Aus dem tatsächlich sichtbaren Space gerechnet,
        // nicht blind -steps (code-audit 19.10.: ein verschlucktes ⌃→ schösse sonst übers Ziel).
        if let stop = viewBack(on: move.target.display, to: viewBefore, screens: screens, deadline: deadline) { return stop }
        return arrived ? nil : .skip(.notVerified)
    }

    /// Gleicher Bildschirm, ohne Greifen: Fenster kurz auf den anderen Bildschirm parken (landet dort
    /// auf dem sichtbaren Space), eigene Ansicht auf den Ziel-Space schalten, Fenster zurücksetzen —
    /// es landet auf dem jetzt sichtbaren Space = Ziel —, Ansicht zurück. Kein Klick, funktioniert
    /// auch bei Apps, deren Kopfzeile Web-Inhalt ist (WhatsApp, 19.10.). Wird der Nutzer aktiv, bevor
    /// das Fenster zurück ist, kommt es an seinen alten Platz zurück.
    private static func carryBounce(_ ax: AXWindow, live: LiveWindow, move: DeskMove, screens: DeskScreens,
                                    deadline: Date) -> Step? {
        guard let screen = screens.frame(of: move.target.display),
              let other = screens.frames.first(where: { $0.key != move.target.display })?.value,
              let current = space(of: live.windowID), let steps = DeskRun.steps(from: current, to: move.target)
        else { return .skip(.notReachable) }
        let before = visibleSpace(on: move.target.display)
        let size = move.frame?.size ?? live.frame.size
        ax.setFrame(Geometry.clamp(CGRect(origin: CGPoint(x: other.minX + 40, y: other.minY + 40), size: size), to: other))
        usleep(300_000)
        let viewTo = InputSynth.switchView(on: screen, by: steps, deadline: deadline)
        guard viewTo == .moved else {
            ax.setFrame(live.frame)                  // zurück an den alten Platz
            switch viewTo {
            case .interrupted: return .abort(.userInput)
            case .modifiersStuck: return .abort(.modifiersStuck)
            case .timeUp: return .abort(.timeLimit)
            default: return .skip(.notReachable)
            }
        }
        ax.setFrame(move.frame ?? Geometry.clamp(CGRect(origin: live.frame.origin, size: size), to: screen))
        usleep(300_000)
        let arrived = space(of: live.windowID)?.managedID == move.target.managedID
        if let stop = viewBack(on: move.target.display, to: before, screens: screens, deadline: deadline) { return stop }
        return arrived ? nil : .skip(.notVerified)
    }

    /// Auf einen anderen Bildschirm: erst dessen Ansicht auf den Ziel-Space schalten, dann das
    /// Fenster hinübersetzen — es landet auf dem sichtbaren Space dieses Bildschirms (gemessen
    /// 19.10.), also direkt am Ziel. Kein Greifen, kein Klick. Sichttest 19.10., 14:35: vorher
    /// setzte Seam das Fenster oben links ab und wollte es dann greifen — dort lag Teams darüber.
    private static func carryAcross(_ ax: AXWindow, live: LiveWindow, move: DeskMove, screens: DeskScreens,
                                    deadline: Date) -> Step? {
        guard let screen = screens.frame(of: move.target.display), let before = visibleSpace(on: move.target.display),
              let steps = DeskRun.steps(from: before, to: move.target) else { return .skip(.notReachable) }
        if steps != 0 {
            switch InputSynth.switchView(on: screen, by: steps, deadline: deadline) {
            case .moved: break
            case .interrupted: return .abort(.userInput)
            case .modifiersStuck: return .abort(.modifiersStuck)
            case .timeUp: return .abort(.timeLimit)
            case .noGripPoint, .notGrabbed, .invalidSteps: return .skip(.notReachable)
            }
        }
        let size = move.frame?.size ?? live.frame.size
        ax.setFrame(move.frame ?? Geometry.clamp(CGRect(origin: CGPoint(x: screen.minX + 40, y: screen.minY + 40), size: size), to: screen))
        usleep(300_000)
        let arrived = space(of: live.windowID)?.managedID == move.target.managedID
        if let stop = viewBack(on: move.target.display, to: before, screens: screens, deadline: deadline) { return stop }
        return arrived ? nil : .skip(.notVerified)
    }

    /// Ansicht eines Bildschirms zurück auf `before`, aus dem tatsächlich sichtbaren Space gerechnet.
    /// 20 s Nachlauf über die Frist, damit der Nutzer nicht auf einem fremden Schreibtisch stehen bleibt.
    private static func viewBack(on display: String, to before: SpaceInfo?, screens: DeskScreens, deadline: Date) -> Step? {
        guard let before, let screen = screens.frame(of: display), let now = visibleSpace(on: display),
              let back = DeskRun.steps(from: now, to: before), back != 0 else { return nil }
        switch InputSynth.switchView(on: screen, by: back, deadline: deadline.addingTimeInterval(20)) {
        case .interrupted: return .abort(.userInput)
        case .modifiersStuck: return .abort(.modifiersStuck)
        default: return nil
        }
    }

    /// Der gerade sichtbare Space eines Bildschirms.
    private static func visibleSpace(on display: String) -> SpaceInfo? {
        SpaceReader.read()?.first { $0.isCurrent && $0.display == display }
    }

    /// Bedienungshilfen-Fenster zu einem Fenster aus der Fensterliste: gleiche App, gleicher Rahmen,
    /// genau ein Treffer. Sieht nur Fenster auf sichtbaren Spaces.
    private static func axWindow(for live: LiveWindow) -> AXWindow? {
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: live.bundleID).flatMap { app in
            AXAccess.elements(AXUIElementCreateApplication(app.processIdentifier), .windows).map(AXWindow.init)
        }.filter(\.isManageable)
        return DeskRun.uniqueMatch(candidates.map(\.frame), for: live.frame).map { candidates[$0] }
    }

    private static func space(of window: Int) -> SpaceInfo? {
        let ids = SpaceReader.spaceIDs(ofWindow: CGWindowID(window))
        guard ids.count == 1 else { return nil }
        return SpaceReader.read()?.first { $0.managedID == ids[0] }
    }
}
