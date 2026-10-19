import AppKit
import OSLog

// Layouts pro Space, Schritt 5: der Lauf (docs/SECURE-DESIGN.md E17b).
// Liest Layout + Ist-Zustand auf dem Hauptthread, lässt DeskExecutor die Züge auf einer eigenen
// Warteschlange ausführen und meldet ein Ergebnis zurück. Regeln + Ausführung: DeskExecutor.swift.

/// Führt einen Plan aus. Eine Instanz je App (Engine).
@MainActor
final class DeskRunner {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "layouts")
    private let prefs: Preferences
    private let queue = DispatchQueue(label: "dev.mwlr.seam.layouts", qos: .userInitiated)
    private(set) var isRunning = false
    private var lastAutomatic: Date?

    init(prefs: Preferences) { self.prefs = prefs }

    /// Lauf starten. Rückgabe: Grund, warum nicht (dann kommt kein `done`). Sonst kommt das
    /// Ergebnis später über `done` auf dem Hauptthread.
    @discardableResult
    func run(automatic: Bool, done: @escaping @MainActor (DeskRunResult) -> Void) -> DeskBlock? {
        let read = SpaceReader.read()
        let spaces = read ?? []
        let screens = DeskLayouts.liveScreens()
        let layout = prefs.deskLayouts[screens.combinationKey]
        let conditions = DeskRun.Conditions(hasLayout: layout != nil, trusted: AXAccess.isTrusted,
                                            switchKeys: InputSynth.spaceSwitchKeysEnabled(),
                                            locked: DeskRun.isScreenLocked(),
                                            fullScreen: spaces.contains { $0.isCurrent && $0.isFullScreen },
                                            running: isRunning, spacesReadable: read != nil)
        if let block = DeskRun.blocker(conditions, automatic: automatic, lastAutomatic: lastAutomatic, now: Date()) {
            Self.log.notice("Aufräumen nicht gestartet: \(String(describing: block), privacy: .public)")
            return block
        }
        guard let layout else { return .noLayout }
        if automatic { lastAutomatic = Date() }
        isRunning = true
        let windows = DeskLayouts.liveWindows()
        let plan = DeskPlanner.plan(layout: layout, spaces: spaces, names: prefs.spaceNames, windows: windows, screens: screens)
        Self.log.notice("Aufräumen: \(automatic ? "automatisch" : "von Hand", privacy: .public), \(plan.moves.count) Züge, \(plan.issues.count) Space-Probleme")
        queue.async {
            let result = DeskExecutor.execute(plan, windows: windows, screens: screens)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isRunning = false
                    Self.log.notice("Aufräumen fertig: \(result.moved) verschoben, \(result.framed) Rahmen, \(result.skipped.count) ausgelassen [\(result.skipped.map { String(describing: $0.reason) }.joined(separator: ","), privacy: .public)], Abbruch \(result.aborted.map { String(describing: $0) } ?? "nein", privacy: .public)")
                    done(result)
                }
            }
        }
        return nil
    }

    /// Plan für den jetzigen Zustand, ohne etwas auszuführen (Popover: weicht ab? Space-Probleme?).
    func currentPlan() -> DeskPlan? {
        let screens = DeskLayouts.liveScreens()
        guard let layout = prefs.deskLayouts[screens.combinationKey],
              let spaces = SpaceReader.read() else { return nil }
        return DeskPlanner.plan(layout: layout, spaces: spaces, names: prefs.spaceNames,
                                windows: DeskLayouts.liveWindows(), screens: screens)
    }
}
