import Foundation

/// Stream Deck (0.12.0, docs/SECURE-DESIGN.md E20): Nachrichtenformat zwischen Seam und dem Plugin „SeamDeck“.
/// Dieselbe Datei in beiden Zielen, damit Senden und Prüfen nie auseinanderlaufen. Rahmen: 4 Byte Länge (Big Endian) + JSON.
///
/// Es gibt **keine** Felder für Fensterkennung, App, Pfad, Koordinaten, Prozentwert oder Text. Befehle sind feste Aufzählungswerte;
/// die Stufe der Naht ist immer „eine weiter/zurück“, nie eine Zielstufe. Seam rechnet.
enum DeckWire {

    nonisolated static let socketName = "deck.sock"
    nonisolated static let socketFolder = "Deck"
    nonisolated static let pluginID = "dev.mwlr.seam.deck"
    /// Ordner des Plugins in Seams Resources und Name des Pakets für Stream Deck.
    nonisolated static let pluginFolder = "dev.mwlr.seam.deck.sdPlugin"
    /// Programmdatei im Plugin-Ordner (Manifest `CodePath`).
    nonisolated static let executable = "seamdeck"
    /// Größter Rahmen (Länge + JSON) in beide Richtungen. Befehle und Zustand sind klein; mehr ist kein Befehl.
    nonisolated static let maxFrame = 512
    /// Höchstens so viele Befehle je Sekunde (Regler liefern normal bis ≈ 9 Ereignisse/s, gemessen bei Gnotchi M4).
    nonisolated static let maxPerSecond = 20
    nonisolated static let maxVersionChars = 20

    /// Elgatos Stream-Deck-App (gemessen 17.11.: `Developer ID Application: Corsair Memory, Inc. (Y93VXCB8Q5)`).
    nonisolated static let streamDeckRequirement =
        #"anchor apple generic and identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5""#

    /// Developer ID von Michaels Team mit fester Kennung – **nicht** nur `anchor apple generic`: Apple-Development-Builds
    /// tragen `get-task-allow` und ließen sich vom selben Nutzer anhängen.
    nonisolated static func requirement(identifier: String) -> String {
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
            + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier ""#
            + identifier + #"" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    }

    nonisolated static let pluginRequirement = requirement(identifier: pluginID)
    nonisolated static let seamRequirement = requirement(identifier: "dev.mwlr.seam")

    /// Feste Liste der Plätze am Deck (E20/3). Rohwerte = Namen von Seams `Command`; neue Seam-Kommandos erscheinen hier nie von selbst.
    enum Place: String, CaseIterable, Sendable {
        case split
        case left, right, up, down
        case topLeft, topRight, bottomLeft, bottomRight
        case firstThird, centerThird, lastThird
        case firstTwoThirds, centerTwoThirds, lastTwoThirds
        case maximize, center, restore
        case nextDisplay, previousDisplay
    }

    enum Command: Equatable, Sendable {
        /// `preview`: Das Plugin kann Vorschaubilder lesen (größerer Rahmen nur in Richtung Plugin). Fehlt das Feld → nein.
        case hello(version: String, preview: Bool = false)
        /// Naht eine Stufe weiter (+1) oder zurück (−1).
        case seam(dir: Int)
        case place(Place)
        /// Layout der aktuellen Bildschirm-Kombination speichern bzw. wiederherstellen (Stufe 2, E20k).
        case deskSave, deskTidy
        /// Nächstes (+1) oder voriges (−1) Bild aus dem gewählten Bildordner (Stufe 3, E20l). Nie ein Pfad, nie ein Name.
        case wallpaper(dir: Int)
    }

    // MARK: Plugin → Seam

    /// `nil` = ungültig, Verbindung zu. Streng: `v` ist die Zahl 1 (kein Wahrheitswert), genau die erlaubten Schlüssel, nur feste Werte.
    nonisolated static func parse(_ payload: Data) -> Command? {
        guard payload.count < maxFrame,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              isOne(obj["v"]) else { return nil }
        let keys = Set(obj.keys)
        if keys == ["v", "hello"] || keys == ["v", "hello", "preview"] {
            guard let v = obj["hello"] as? String, isVersion(v) else { return nil }
            guard keys.count == 3 else { return .hello(version: v) }
            guard let b = obj["preview"] as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() else { return nil }
            return .hello(version: v, preview: b.boolValue)
        }
        guard keys.isSuperset(of: ["v", "cmd"]), let cmd = obj["cmd"] as? String else { return nil }
        switch cmd {
        case "seam":
            guard keys == ["v", "cmd", "dir"], let n = obj["dir"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == 1 || n.doubleValue == -1 else { return nil }
            return .seam(dir: n.intValue)
        case "wallpaper":
            guard keys == ["v", "cmd", "dir"], let n = obj["dir"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == 1 || n.doubleValue == -1 else { return nil }
            return .wallpaper(dir: n.intValue)
        case "deskSave", "deskTidy":
            guard keys == ["v", "cmd"] else { return nil }
            return cmd == "deskSave" ? .deskSave : .deskTidy
        case "place":
            guard keys == ["v", "cmd", "what"], let w = obj["what"] as? String, let p = Place(rawValue: w) else { return nil }
            return .place(p)
        default:
            return nil
        }
    }

    nonisolated static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .hello(let v, let preview): preview ? ["v": 1, "hello": v, "preview": true] : ["v": 1, "hello": v]
        case .seam(let dir): ["v": 1, "cmd": "seam", "dir": dir]
        case .place(let p): ["v": 1, "cmd": "place", "what": p.rawValue]
        case .wallpaper(let dir): ["v": 1, "cmd": "wallpaper", "dir": dir]
        case .deskSave: ["v": 1, "cmd": "deskSave"]
        case .deskTidy: ["v": 1, "cmd": "deskTidy"]
        }
    }

    nonisolated private static func isOne(_ any: Any?) -> Bool {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
        return n.doubleValue == 1
    }

    /// Ziffern und Punkte, höchstens 20 Zeichen („0.12.0“, „0.12.0.0“).
    nonisolated static func isVersion(_ s: String) -> Bool {
        !s.isEmpty && s.count <= maxVersionChars && s.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }

    // MARK: Seam → Plugin

    /// Ergebnis des letzten Naht-Befehls bzw. Zustand der Verbindung. Nur Aufzählungswerte und Zahlen (E20/10).
    enum SeamState: String, Sendable {
        case ok, noPair, noWindow, needsPermission, atEnd
    }

    /// Layout-Zustand (Stufe 2): nur Aufzählungen und eine Zahl, nie App- oder Bildschirmnamen (Fehlertexte bleiben in Seam).
    struct Desk: Equatable, Sendable {
        enum Phase: String, Sendable { case none, saved, running, blocked }
        enum Last: String, Sendable { case ok, aborted, blocked }
        enum Reason: String, Sendable {
            case userInput, modifiersStuck, timeLimit
            case noLayout, noAccessibility, switchKeys, locked, fullScreen, cooldown, running, spaces
        }
        /// Welcher Befehl das Ergebnis `last` erzeugt hat; jede Taste zeigt nur ihr eigenes Ergebnis.
        enum Cmd: String, Sendable { case save, tidy }
        var phase: Phase
        /// Anzahl Apps im gespeicherten Layout (nur bei `saved`).
        var apps: Int?
        var last: Last?
        var reason: Reason?
        var cmd: Cmd?
    }

    /// Hintergrund-Zustand (Stufe 3): Zähler und Aufzählungen, nie Datei- oder Ordnernamen.
    struct Wallpaper: Equatable, Sendable {
        enum Phase: String, Sendable { case ok, noImages, off, busy }
        enum Kind: String, Sendable { case image, video }
        var phase: Phase
        /// Stelle im Ring (1…count) und Länge; nur bei `ok`.
        var index: Int?
        var count: Int?
        var dark: Bool?
        var kind: Kind?
    }

    struct State: Equatable, Sendable {
        var seam: SeamState
        /// 8, 9, 12, 15, 16 (⅓ ⅜ ½ ⅝ ⅔), nur bei `ok` und `atEnd`.
        var stop: Int?
        var desk: Desk?
        var wallpaper: Wallpaper?
    }

    nonisolated static let validStops = [8, 9, 12, 15, 16]
    nonisolated static let maxApps = 999
    nonisolated static let maxRing = 200

    nonisolated static func encode(_ s: State) -> [String: Any] {
        var seam: [String: Any] = ["state": s.seam.rawValue]
        if let stop = s.stop, validStops.contains(stop) { seam["stop"] = stop }
        var out: [String: Any] = ["v": 1, "seam": seam]
        if let d = s.desk {
            var desk: [String: Any] = ["state": d.phase.rawValue]
            if let n = d.apps, (0...maxApps).contains(n) { desk["apps"] = n }
            if let l = d.last { desk["last"] = l.rawValue }
            if let r = d.reason { desk["reason"] = r.rawValue }
            if let c = d.cmd { desk["cmd"] = c.rawValue }
            out["desk"] = desk
        }
        if let w = s.wallpaper {
            var o: [String: Any] = ["state": w.phase.rawValue]
            if let i = w.index, let n = w.count, (1...maxRing).contains(n), (1...n).contains(i) { o["index"] = i; o["count"] = n }
            if let d = w.dark { o["dark"] = d }
            if let k = w.kind { o["kind"] = k.rawValue }
            out["wallpaper"] = o
        }
        return out
    }

    /// Plugin-Seite. Tolerant gegenüber zusätzlichen Feldern späterer Seam-Versionen, streng bei Typ und Wertebereich.
    nonisolated static func parseState(_ payload: Data) -> State? {
        guard payload.count < maxFrame,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], isOne(obj["v"]),
              let seam = obj["seam"] as? [String: Any], let raw = seam["state"] as? String, let state = SeamState(rawValue: raw) else {
            return nil
        }
        var stop: Int?
        if let n = seam["stop"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), validStops.contains(n.intValue) { stop = n.intValue }
        var desk: Desk?
        if let d = obj["desk"] as? [String: Any], let raw = d["state"] as? String, let phase = Desk.Phase(rawValue: raw) {
            var apps: Int?
            if let n = d["apps"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), (0...maxApps).contains(n.intValue) { apps = n.intValue }
            desk = Desk(phase: phase, apps: apps, last: (d["last"] as? String).flatMap(Desk.Last.init(rawValue:)),
                        reason: (d["reason"] as? String).flatMap(Desk.Reason.init(rawValue:)),
                        cmd: (d["cmd"] as? String).flatMap(Desk.Cmd.init(rawValue:)))
        }
        var wallpaper: Wallpaper?
        if let w = obj["wallpaper"] as? [String: Any], let raw = w["state"] as? String, let phase = Wallpaper.Phase(rawValue: raw) {
            var index: Int?, count: Int?
            if let i = w["index"] as? NSNumber, let n = w["count"] as? NSNumber, CFGetTypeID(i) != CFBooleanGetTypeID(),
               CFGetTypeID(n) != CFBooleanGetTypeID(), (1...maxRing).contains(n.intValue), (1...n.intValue).contains(i.intValue) {
                index = i.intValue
                count = n.intValue
            }
            let dark = (w["dark"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
            wallpaper = Wallpaper(phase: phase, index: index, count: count, dark: dark,
                                  kind: (w["kind"] as? String).flatMap(Wallpaper.Kind.init(rawValue:)))
        }
        return State(seam: state, stop: stop, desk: desk, wallpaper: wallpaper)
    }

    // MARK: Vorschau (Stufe 3, E20m)

    /// Fertig skaliertes JPEG (200 × 100) ≤ 5000 Byte. Eigene Nachricht mit eigenem, größeren Rahmen nur in Richtung Plugin.
    nonisolated static let maxPreviewBytes = 5000
    nonisolated static let maxPreviewFrame = 8192
    nonisolated static let previewSize = (width: 200, height: 100)

    /// `{"v":1,"preview":"<Base64>"}`; leerer Text = keine Vorschau. Gesendet nur an Plugins, die im `hello` `preview` melden.
    nonisolated static func encodePreview(_ jpeg: Data?) -> [String: Any]? {
        guard let jpeg else { return ["v": 1, "preview": ""] }
        guard jpeg.count <= maxPreviewBytes, jpeg.starts(with: [0xFF, 0xD8]) else { return nil }
        return ["v": 1, "preview": jpeg.base64EncodedString()]
    }

    /// Plugin-Seite: `.some(nil)` = keine Vorschau, `.some(daten)` = Bild, `nil` = keine Vorschau-Nachricht oder ungültig.
    nonisolated static func parsePreview(_ payload: Data) -> Data?? {
        guard payload.count < maxPreviewFrame,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], isOne(obj["v"]), Set(obj.keys) == ["v", "preview"],
              let text = obj["preview"] as? String else { return nil }
        if text.isEmpty { return .some(nil) }
        guard text.count <= maxPreviewBytes * 2, let data = Data(base64Encoded: text), data.count <= maxPreviewBytes,
              data.starts(with: [0xFF, 0xD8]) else { return nil }
        return .some(data)
    }

    // MARK: Rahmen

    enum Frame: Equatable {
        case message(Data), needMore, invalid
    }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer`. `invalid`: Länge 0 oder zu groß → Verbindung trennen.
    nonisolated static func nextFrame(_ buffer: inout Data, max limit: Int = maxFrame) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= limit else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    nonisolated static func frame(_ object: [String: Any], max limit: Int = maxFrame) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object), json.count + 4 <= limit else { return nil }
        let n = UInt32(json.count).bigEndian
        return withUnsafeBytes(of: n) { Data($0) } + json
    }

    /// Bestätigung nach geprüfter Verbindung (`{"v":1,"ok":true}`), vom Plugin erwartet, bevor es sendet.
    nonisolated static func isAck(_ payload: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], isOne(obj["v"]),
              Set(obj.keys) == ["v", "ok"], let ok = obj["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID() else { return false }
        return ok.boolValue
    }
}
