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
        case hello(version: String)
        /// Naht eine Stufe weiter (+1) oder zurück (−1).
        case seam(dir: Int)
        case place(Place)
    }

    // MARK: Plugin → Seam

    /// `nil` = ungültig, Verbindung zu. Streng: `v` ist die Zahl 1 (kein Wahrheitswert), genau die erlaubten Schlüssel, nur feste Werte.
    nonisolated static func parse(_ payload: Data) -> Command? {
        guard payload.count < maxFrame,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              isOne(obj["v"]) else { return nil }
        let keys = Set(obj.keys)
        if keys == ["v", "hello"] {
            guard let v = obj["hello"] as? String, isVersion(v) else { return nil }
            return .hello(version: v)
        }
        guard keys.isSuperset(of: ["v", "cmd"]), let cmd = obj["cmd"] as? String else { return nil }
        switch cmd {
        case "seam":
            guard keys == ["v", "cmd", "dir"], let n = obj["dir"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == 1 || n.doubleValue == -1 else { return nil }
            return .seam(dir: n.intValue)
        case "place":
            guard keys == ["v", "cmd", "what"], let w = obj["what"] as? String, let p = Place(rawValue: w) else { return nil }
            return .place(p)
        default:
            return nil
        }
    }

    nonisolated static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .hello(let v): ["v": 1, "hello": v]
        case .seam(let dir): ["v": 1, "cmd": "seam", "dir": dir]
        case .place(let p): ["v": 1, "cmd": "place", "what": p.rawValue]
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

    struct State: Equatable, Sendable {
        var seam: SeamState
        /// 8, 9, 12, 15, 16 (⅓ ⅜ ½ ⅝ ⅔), nur bei `ok` und `atEnd`.
        var stop: Int?
    }

    nonisolated static let validStops = [8, 9, 12, 15, 16]

    nonisolated static func encode(_ s: State) -> [String: Any] {
        var seam: [String: Any] = ["state": s.seam.rawValue]
        if let stop = s.stop, validStops.contains(stop) { seam["stop"] = stop }
        return ["v": 1, "seam": seam]
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
        return State(seam: state, stop: stop)
    }

    // MARK: Rahmen

    enum Frame: Equatable {
        case message(Data), needMore, invalid
    }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer`. `invalid`: Länge 0 oder zu groß → Verbindung trennen.
    nonisolated static func nextFrame(_ buffer: inout Data) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= maxFrame else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    nonisolated static func frame(_ object: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object), json.count + 4 <= maxFrame else { return nil }
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
