import AppKit

// Layouts pro Space (docs/SECURE-DESIGN.md E17c, specs/2026-10-19-layouts-pro-space.md).
// Gespeichert wird je App: Bundle-ID, Ziel-Space, Fensterrahmen. Keine Titel, keine Inhalte,
// keine Zeitpunkte, keine Häufigkeit.

/// Ein Schreibtisch im Layout: Name (wenn vergeben) + Bildschirm + Position (E17d).
/// Nie die macOS-Kennung — die wechselt beim Neustart (gemessen 19.10.).
struct DeskRef: Codable, Equatable, Hashable, Sendable {
    let name: String?
    let display: String
    let number: Int
}

/// Rahmen relativ zur linken oberen Ecke des Bildschirms (Bedienungshilfen-Koordinaten).
struct DeskFrame: Codable, Equatable, Sendable {
    let x, y, width, height: Double

    init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct DeskLayoutEntry: Codable, Equatable, Sendable {
    let bundleID: String
    let desk: DeskRef
    /// Rahmen der Fenster dieser App, vorderstes zuerst.
    let frames: [DeskFrame]
}

/// Das Layout einer Bildschirm-Kombination (Michael 19.10.: „Erst eins.“).
struct DeskLayout: Codable, Equatable, Sendable {
    let entries: [DeskLayoutEntry]
}

/// Bildschirme für die Aufnahme: Kennung → Rahmen (Bedienungshilfen-Koordinaten) und der
/// Hauptbildschirm. Teilen sich alle Bildschirme die Spaces, meldet macOS „Main“; dann gilt er.
struct DeskScreens: Equatable, Sendable {
    let frames: [String: CGRect]
    let primary: String?

    func frame(of display: String) -> CGRect? {
        frames[display] ?? (display == "Main" ? primary.flatMap { frames[$0] } : nil)
    }

    /// Bereich, in dem ein Rahmen bleiben muss (E5). Teilen sich alle Bildschirme die Spaces
    /// („Main“), ist das der Bildschirm, auf dem die Fenstermitte liegt — sonst zöge Seam Fenster
    /// vom zweiten Bildschirm auf den Hauptbildschirm (code-audit 19.10.).
    func bounds(for rect: CGRect, display: String) -> CGRect? {
        guard display == "Main", frames[display] == nil else { return frame(of: display) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return frames.values.first { $0.contains(center) } ?? frame(of: display)
    }

    /// Schlüssel der Bildschirm-Kombination dieser Bildschirme.
    var combinationKey: String { DeskLayouts.combinationKey(Array(frames.keys)) }
}

/// Ein Fenster, wie es gerade ist (gelesen aus der Fensterliste, ohne Titel).
struct LiveWindow: Equatable, Sendable {
    let bundleID: String
    /// `ManagedSpaceID`s; genau einer = gehört zu einem Space. Leer = minimiert/versteckt,
    /// mehrere = „auf allen Schreibtischen“.
    let spaceIDs: [Int]
    /// Rahmen in Bedienungshilfen-Koordinaten (global).
    let frame: CGRect
    /// Fensternummer des WindowServers (für Schritte im selben Moment, nie gespeichert).
    var windowID = 0
}

enum DeskLayouts {

    static let maxCombinations = 20
    static let maxEntries = 200
    static let maxFramesPerApp = 10
    static let maxDeskNumber = 64
    /// Größter Betrag einer Koordinate (E17c). Größer ist kein echter Bildschirm.
    static let maxCoordinate = 32_000.0

    /// Schlüssel einer Bildschirm-Kombination: Bildschirm-Kennungen sortiert.
    static func combinationKey(_ displays: [String]) -> String {
        Set(displays).sorted().joined(separator: "+")
    }

    // MARK: Aufnehmen

    /// Aus der aktuellen Lage ein Layout machen (rein, testbar).
    /// - Ausgelassen: eigene App, Fenster auf keinem oder mehreren Spaces, Vollbild-Spaces,
    ///   Spaces ohne bekannten Bildschirm. Eine App gehört auf einen Space (Michael 19.10.):
    ///   maßgeblich ist ihr vorderstes Fenster, Fenster auf anderen Spaces zählen nicht.
    static func capture(windows: [LiveWindow], spaces: [SpaceInfo], names: [String: String],
                        screens: DeskScreens, ownBundleID: String?) -> DeskLayout {
        let byID = Dictionary(spaces.map { ($0.managedID, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        var desks: [String: DeskRef] = [:]
        var frames: [String: [DeskFrame]] = [:]
        for w in windows where w.bundleID != ownBundleID && w.spaceIDs.count == 1 {
            guard let space = byID[w.spaceIDs[0]], !space.isFullScreen,
                  let screen = screens.frame(of: space.display) else { continue }
            let name = names[space.key].flatMap { $0.isEmpty ? nil : $0 }
            let desk = DeskRef(name: name, display: space.display, number: space.number)
            if let known = desks[w.bundleID] {
                guard known == desk, frames[w.bundleID, default: []].count < maxFramesPerApp else { continue }
            } else {
                guard order.count < maxEntries else { continue }
                order.append(w.bundleID)
                desks[w.bundleID] = desk
            }
            let rel = w.frame.offsetBy(dx: -screen.minX, dy: -screen.minY)
            frames[w.bundleID, default: []].append(DeskFrame(rel))
        }
        return DeskLayout(entries: order.map {
            DeskLayoutEntry(bundleID: $0, desk: desks[$0]!, frames: frames[$0] ?? [])
        })
    }

    // MARK: Laden mit Grenzen (E17c)

    /// Gespeicherte Daten prüfen. Ungültiges wird verworfen, nicht repariert.
    static func decode(_ data: Data?) -> [String: DeskLayout] {
        guard let data, data.count <= 1_000_000,
              let raw = try? JSONDecoder().decode([String: DeskLayout].self, from: data) else { return [:] }
        var out: [String: DeskLayout] = [:]
        for (key, layout) in raw.sorted(by: { $0.key < $1.key }) where out.count < maxCombinations {
            guard isValidKey(key, maxLength: 400) else { continue }
            var seen = Set<String>()
            let entries = layout.entries.prefix(maxEntries).compactMap { e -> DeskLayoutEntry? in
                guard LinkRules.isBundleID(e.bundleID), seen.insert(e.bundleID).inserted,
                      let desk = validDesk(e.desk) else { return nil }
                let frames = e.frames.prefix(maxFramesPerApp).filter(isValidFrame)
                return frames.isEmpty ? nil : DeskLayoutEntry(bundleID: e.bundleID, desk: desk, frames: Array(frames))
            }
            if !entries.isEmpty { out[key] = DeskLayout(entries: entries) }
        }
        return out
    }

    static func encode(_ layouts: [String: DeskLayout]) -> Data? {
        try? JSONEncoder().encode(layouts)
    }

    private static func validDesk(_ d: DeskRef) -> DeskRef? {
        guard isValidKey(d.display, maxLength: 80), (1...maxDeskNumber).contains(d.number) else { return nil }
        let name = d.name.map(SpaceNames.sanitize).flatMap { $0.isEmpty ? nil : $0 }
        return DeskRef(name: name, display: d.display, number: d.number)
    }

    private static func isValidFrame(_ f: DeskFrame) -> Bool {
        let v = [f.x, f.y, f.width, f.height]
        return v.allSatisfy { $0.isFinite && abs($0) <= maxCoordinate } && f.width > 0 && f.height > 0
    }

    private static func isValidKey(_ k: String, maxLength: Int) -> Bool {
        !k.isEmpty && k.utf8.count <= maxLength
            && !k.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    // MARK: Live lesen

    /// Alle normalen App-Fenster auf allen Spaces (Fensterliste, ohne Titel — E3), vorn zuerst.
    /// Mindestgröße und Deckkraft filtern Hilfsfenster wie Linkanzeigen aus (Messung 16.10./19.10.).
    @MainActor
    static func liveWindows() -> [LiveWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var bundles: [pid_t: String?] = [:]
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b),
                  frame.width >= 120, frame.height >= 80 else { return nil }
            if bundles[pid] == nil {
                let app = NSRunningApplication(processIdentifier: pid)
                bundles[pid] = app?.activationPolicy == .regular ? app?.bundleIdentifier : nil
            }
            guard let bundle = bundles[pid] ?? nil else { return nil }
            return LiveWindow(bundleID: bundle, spaceIDs: SpaceReader.spaceIDs(ofWindow: CGWindowID(n)), frame: frame,
                              windowID: n)
        }
    }

    /// Name einer App zur Bundle-ID — nur für die Oberfläche, nie fürs Protokoll (E17c).
    @MainActor
    static func appName(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
            ?? bundleID
    }

    /// Bildschirme jetzt, in Bedienungshilfen-Koordinaten.
    @MainActor
    static func liveScreens() -> DeskScreens {
        let h = Screens.primaryHeight
        let frames: [String: CGRect] = NSScreen.screens.reduce(into: [:]) { r, s in
            if let id = SpaceReader.displayIdentifier(of: s) { r[id] = Geometry.toAX(s.frame, primaryHeight: h) }
        }
        return DeskScreens(frames: frames, primary: SpaceReader.displayIdentifier(of: NSScreen.screens.first))
    }
}
