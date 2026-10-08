import Foundation
import Observation

/// Einstellungen. Nur Schalter und Zahlen, keine Daten fremder Apps
/// (docs/SECURE-DESIGN.md E10). Ab Werk wie Michaels Magnet.
@MainActor
@Observable
final class Preferences {

    private enum Key {
        static let linkEdges = "linkEdges"
        static let dragSnap = "dragSnap"
        static let shortcuts = "shortcuts"
        static let gap = "gap"
        static let restoreOnDragOut = "restoreOnDragOut"
    }

    private let defaults: UserDefaults

    /// Fenster an gemeinsamen Kanten mitziehen — Seams Besonderheit.
    var linkEdges: Bool { didSet { defaults.set(linkEdges, forKey: Key.linkEdges) } }
    /// Andocken per Ziehen an den Bildschirmrand (Magnet: snapWindows).
    var dragSnap: Bool { didSet { defaults.set(dragSnap, forKey: Key.dragSnap) } }
    var shortcuts: Bool { didSet { defaults.set(shortcuts, forKey: Key.shortcuts) } }
    /// Abstand um Fenster in Punkt (Magnet: paddingAroundWindows = 5).
    var gap: Int { didSet { defaults.set(gap, forKey: Key.gap) } }
    /// Angedocktes Fenster beim Herausziehen auf seine alte Größe (Magnet: restoreToOriginalSize).
    var restoreOnDragOut: Bool { didSet { defaults.set(restoreOnDragOut, forKey: Key.restoreOnDragOut) } }

    static let gapChoices = [0, 5, 10, 20]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        linkEdges = defaults.object(forKey: Key.linkEdges) as? Bool ?? true
        dragSnap = defaults.object(forKey: Key.dragSnap) as? Bool ?? true
        shortcuts = defaults.object(forKey: Key.shortcuts) as? Bool ?? true
        // Ungültige Werte (von außen verändert) fallen auf den Standard zurück (STRIDE T).
        let g = defaults.object(forKey: Key.gap) as? Int ?? 5
        gap = Self.gapChoices.contains(g) ? g : 5
        restoreOnDragOut = defaults.object(forKey: Key.restoreOnDragOut) as? Bool ?? true
    }
}
