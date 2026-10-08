import AppKit
import OSLog

/// Führt Kommandos auf einem Fenster aus und merkt sich dessen ursprüngliche Größe.
@MainActor
final class WindowActions {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "aktion")
    private let prefs: Preferences
    private let writer = NeighborWriter()

    /// Rahmen vor dem ersten Andocken. Nur im Speicher, an die AX-Referenz
    /// gebunden, nach einem Neustart weg (docs/SECURE-DESIGN.md E10).
    private var original: [AXWindow: CGRect] = [:]

    init(prefs: Preferences) { self.prefs = prefs }

    /// Tastenkürzel: wirkt auf das fokussierte Fenster.
    func perform(_ key: KeyCombo) {
        guard let w = AXAccess.focusedWindow(), let f = w.frame, let screen = Screens.best(for: f) else {
            Self.log.notice("Kürzel \(key.label, privacy: .public): kein verwaltbares Fenster im Fokus")
            return
        }
        guard let cmd = Layout.command(for: key, screen.orientation) else { return }
        apply(cmd, to: w, current: f, screen: screen, before: f)
    }

    /// `before` = Rahmen vor der Geste (beim Andocken per Ziehen der Rahmen vor dem Ziehen).
    func apply(_ cmd: Command, to w: AXWindow, current f: CGRect, screen: Screens.Info, before: CGRect) {
        let gap = CGFloat(prefs.gap)
        let target: CGRect?
        switch cmd {
        case .restore:
            target = original.removeValue(forKey: w).map { Geometry.clamp($0, to: screen.visible) }
        case .center:
            target = Geometry.centered(f, in: screen.visible)
        case .nextDisplay, .previousDisplay:
            let all = Screens.ordered()
            guard all.count > 1, let i = all.firstIndex(of: screen) else { return }
            let j = (i + (cmd == .nextDisplay ? 1 : all.count - 1)) % all.count
            target = Geometry.transfer(f, from: screen.visible, to: all[j].visible)
        default:
            guard let cells = Layout.spec(cmd, screen.orientation)?.target else { return }
            if original[w] == nil { original[w] = before }
            target = Geometry.rect(for: cells, in: screen.visible, screen.orientation, gap: gap)
        }
        guard let target else { return }
        let goal = Geometry.clamp(target, to: screen.visible)
        let log = Self.log, name = cmd.rawValue
        // Mit Nachprüfung auf der Warteschlange: Edge landete beim ersten ⌃⌥→ auf
        // x 2449 / Breite 991 statt x 1723 / 1712 (gemessen 08.10.).
        writer.run {
            let result = NeighborWriter.setVerified(w, goal)
            // Messpunkt: Soll und Ist. Weicht die App ab (Mindestgröße), steht es hier.
            log.notice("\(name, privacy: .public): Soll \(NSStringFromRect(goal), privacy: .public) Ist \(result.map(NSStringFromRect) ?? "–", privacy: .public)")
        }
    }

    func wasSnapped(_ w: AXWindow) -> CGRect? { original[w] }
    func forget(_ w: AXWindow) { original[w] = nil }
}
