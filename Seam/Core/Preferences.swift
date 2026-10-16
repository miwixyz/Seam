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
        static let dimScreenModes = "dimScreenModes"
        static let dimScreenStrengths = "dimScreenStrengths"
        static let dimActiveAppAll = "dimActiveAppAll"
        static let dimNeverApps = "dimNeverApps"
        static let dimOffSpaces = "dimOffSpaces"
        static let showSpaceName = "showSpaceName"
        static let spaceNames = "spaceNames"
        static let hideIconWithSpaceName = "hideIconWithSpaceName"
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
    /// Deckkraft der Abdunklung in Prozent. Ab 0.6 der Wert für Bildschirme ohne eigene Stärke.
    var dimStrength: Int { didSet { defaults.set(dimStrength, forKey: Key.dimStrength) } }
    /// Je Bildschirm (UUID, E13 0.6): Art der Abdunklung. Fehlt der Eintrag → `.dim`.
    var dimScreenModes: [String: String] { didSet { defaults.set(dimScreenModes, forKey: Key.dimScreenModes) } }
    /// Je Bildschirm (UUID): eigene Stärke. Fehlt der Eintrag → `dimStrength`.
    var dimScreenStrengths: [String: Int] { didSet { defaults.set(dimScreenStrengths, forKey: Key.dimScreenStrengths) } }
    /// Alle Fenster der aktiven App bleiben hell, nicht nur das oberste (Michael, 16.10.). Ab Werk aus.
    var dimActiveAppAll: Bool { didSet { defaults.set(dimActiveAppAll, forKey: Key.dimActiveAppAll) } }
    /// Bundle-IDs der Apps, deren Fenster nie abgedunkelt werden.
    var dimNeverApps: [String] { didSet { defaults.set(dimNeverApps, forKey: Key.dimNeverApps) } }
    /// Space-Schlüssel (wie bei den Namen, E14), in denen nicht abgedunkelt wird.
    var dimOffSpaces: [String] { didSet { defaults.set(dimOffSpaces, forKey: Key.dimOffSpaces) } }
    /// Namen des aktuellen Space neben dem Symbol in der Menüleiste zeigen (E14).
    var showSpaceName: Bool { didSet { defaults.set(showSpaceName, forKey: Key.showSpaceName) } }
    /// Namen der Spaces: Space-Schlüssel (UUID) → Name. Nur Eingaben des Nutzers (E14).
    var spaceNames: [String: String] { didSet { defaults.set(spaceNames, forKey: Key.spaceNames) } }
    /// Seam-Symbol weglassen, solange ein Space-Name in der Menüleiste steht (Michael, 09.10.).
    var hideIconWithSpaceName: Bool { didSet { defaults.set(hideIconWithSpaceName, forKey: Key.hideIconWithSpaceName) } }

    static let gapChoices = [0, 5, 10, 20]
    static let dimChoices = [20, 35, 50]
    static let maxDimApps = 50
    static let maxDimSpaces = 100
    static let maxDimScreens = 20

    // MARK: Abdunkeln je Bildschirm, App, Space (0.6)

    func dimMode(for screen: String?) -> DimScreenMode {
        screen.flatMap { dimScreenModes[$0] }.flatMap(DimScreenMode.init(rawValue:)) ?? .dim
    }

    func setDimMode(_ mode: DimScreenMode, for screen: String) {
        guard Self.validKey(screen) else { return }
        if mode == .dim { dimScreenModes[screen] = nil; return }
        guard dimScreenModes[screen] != nil || dimScreenModes.count < Self.maxDimScreens else { return }
        dimScreenModes[screen] = mode.rawValue
    }

    func dimStrength(for screen: String?) -> Int {
        screen.flatMap { dimScreenStrengths[$0] } ?? dimStrength
    }

    func setDimStrength(_ value: Int, for screen: String) {
        guard Self.validKey(screen), Self.dimChoices.contains(value),
              dimScreenStrengths[screen] != nil || dimScreenStrengths.count < Self.maxDimScreens else { return }
        dimScreenStrengths[screen] = value
    }

    func addDimNeverApp(_ id: String) {
        guard LinkRules.isBundleID(id), !dimNeverApps.contains(id), dimNeverApps.count < Self.maxDimApps else { return }
        dimNeverApps.append(id)
    }

    func setSpaceDimmed(_ dimmed: Bool, key: String) {
        if dimmed {
            dimOffSpaces.removeAll { $0 == key }
        } else if Self.validKey(key), !dimOffSpaces.contains(key), dimOffSpaces.count < Self.maxDimSpaces {
            dimOffSpaces.append(key)
        }
    }

    /// Schlüssel (Bildschirm-UUID, Space): nicht leer, höchstens 80 Byte, keine Steuerzeichen.
    /// Bytes statt Zeichen (Rafter-Review 16.10.): ein „Zeichen“ kann beliebig viele Kombinationszeichen haben.
    private static func validKey(_ k: String) -> Bool {
        !k.isEmpty && k.utf8.count <= 80 && !k.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Gültige Einträge ohne Doppelte, Reihenfolge bleibt, Schluss bei `max`.
    private static func uniqueCapped(_ list: [String], max: Int, valid: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in list where out.count < max && valid(s) && seen.insert(s).inserted { out.append(s) }
        return out
    }

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
        // Abdunkeln je Bildschirm/App/Space (0.6): nur gültige Werte, gedeckelt (STRIDE T, E13).
        // Rafter-Review 16.10.: kein `uniqueKeysWithValues` (bricht bei doppelten Schlüsseln ab),
        // Obergrenze während des Durchlaufs (nicht erst danach), Duplikate über ein Set.
        let modes = defaults.dictionary(forKey: Key.dimScreenModes) as? [String: String] ?? [:]
        dimScreenModes = modes.reduce(into: [:]) { r, e in
            if r.count < Self.maxDimScreens, Self.validKey(e.key), DimScreenMode(rawValue: e.value) != nil { r[e.key] = e.value }
        }
        let strengths = defaults.dictionary(forKey: Key.dimScreenStrengths) as? [String: Int] ?? [:]
        dimScreenStrengths = strengths.reduce(into: [:]) { r, e in
            if r.count < Self.maxDimScreens, Self.validKey(e.key), Self.dimChoices.contains(e.value) { r[e.key] = e.value }
        }
        dimActiveAppAll = defaults.object(forKey: Key.dimActiveAppAll) as? Bool ?? false
        dimNeverApps = Self.uniqueCapped(defaults.stringArray(forKey: Key.dimNeverApps) ?? [], max: Self.maxDimApps,
                                         valid: LinkRules.isBundleID)
        dimOffSpaces = Self.uniqueCapped(defaults.stringArray(forKey: Key.dimOffSpaces) ?? [], max: Self.maxDimSpaces,
                                         valid: Self.validKey)
        showSpaceName = defaults.object(forKey: Key.showSpaceName) as? Bool ?? true
        hideIconWithSpaceName = defaults.object(forKey: Key.hideIconWithSpaceName) as? Bool ?? false
        // Von außen veränderte Werte bereinigen (STRIDE T): nur Text, gekürzt, ohne Steuerzeichen.
        let raw = defaults.dictionary(forKey: Key.spaceNames) as? [String: String] ?? [:]
        spaceNames = raw.reduce(into: [:]) { r, e in
            let n = SpaceNames.sanitize(e.value)
            if !n.isEmpty, e.key.count <= 80 { r[e.key] = n }
        }
    }
}
