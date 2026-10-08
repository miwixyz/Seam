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
        static let keepPairs = "keepPairs"
        static let dimEnabled = "dimEnabled"
        static let dimStrength = "dimStrength"
        static let showSpaceName = "showSpaceName"
        static let spaceNames = "spaceNames"
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
    /// Mit ⌃⌥S geteilte Fenster kommen gemeinsam nach vorn und werden gemeinsam minimiert (E12).
    var keepPairs: Bool { didSet { defaults.set(keepPairs, forKey: Key.keepPairs) } }
    /// Hintergrund abdunkeln wie HazeOver (E13). Ab Werk aus (Michael, 09.10.).
    var dimEnabled: Bool { didSet { defaults.set(dimEnabled, forKey: Key.dimEnabled) } }
    /// Deckkraft der Abdunklung in Prozent.
    var dimStrength: Int { didSet { defaults.set(dimStrength, forKey: Key.dimStrength) } }
    /// Namen des aktuellen Space neben dem Symbol in der Menüleiste zeigen (E14).
    var showSpaceName: Bool { didSet { defaults.set(showSpaceName, forKey: Key.showSpaceName) } }
    /// Namen der Spaces: Space-Schlüssel (UUID) → Name. Nur Eingaben des Nutzers (E14).
    var spaceNames: [String: String] { didSet { defaults.set(spaceNames, forKey: Key.spaceNames) } }

    static let gapChoices = [0, 5, 10, 20]
    static let dimChoices = [20, 35, 50]

    /// Namen setzen (leer = Standardname „Schreibtisch N“).
    func setSpaceName(_ name: String, for key: String) {
        let n = SpaceNames.sanitize(name)
        if n.isEmpty { spaceNames[key] = nil } else { spaceNames[key] = n }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        linkEdges = defaults.object(forKey: Key.linkEdges) as? Bool ?? true
        dragSnap = defaults.object(forKey: Key.dragSnap) as? Bool ?? true
        shortcuts = defaults.object(forKey: Key.shortcuts) as? Bool ?? true
        // Ungültige Werte (von außen verändert) fallen auf den Standard zurück (STRIDE T).
        let g = defaults.object(forKey: Key.gap) as? Int ?? 5
        gap = Self.gapChoices.contains(g) ? g : 5
        restoreOnDragOut = defaults.object(forKey: Key.restoreOnDragOut) as? Bool ?? true
        keepPairs = defaults.object(forKey: Key.keepPairs) as? Bool ?? true
        dimEnabled = defaults.object(forKey: Key.dimEnabled) as? Bool ?? false
        let s = defaults.object(forKey: Key.dimStrength) as? Int ?? 35
        dimStrength = Self.dimChoices.contains(s) ? s : 35
        showSpaceName = defaults.object(forKey: Key.showSpaceName) as? Bool ?? true
        // Von außen veränderte Werte bereinigen (STRIDE T): nur Text, gekürzt, ohne Steuerzeichen.
        let raw = defaults.dictionary(forKey: Key.spaceNames) as? [String: String] ?? [:]
        spaceNames = raw.reduce(into: [:]) { r, e in
            let n = SpaceNames.sanitize(e.value)
            if !n.isEmpty, e.key.count <= 80 { r[e.key] = n }
        }
    }
}
