import AppKit
import Darwin
import Foundation
import OSLog
import Security

// SeamDeck – Stream-Deck-Plugin für Seam (0.12.0, SECURE-DESIGN E20).
// Übersetzt Regler und Tasten in feste Seam-Befehle und zeigt Seams Rückmeldung an. Keine Freigaben, keine eigene Fensterlogik.
// Schreibt nie auf stdout/stderr (Stream Deck protokolliert das je Plugin), nur os_log mit festen Texten.

let log = Logger(subsystem: DeckWire.pluginID, category: "plugin")

/// Gestartet von Elgatos Stream Deck? Sonst still beenden (Seam prüft dasselbe noch einmal, M2).
func parentIsStreamDeck() -> Bool {
    var req: SecRequirement?
    guard SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &req) == errSecSuccess, let req else { return false }
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: NSNumber(value: getppid())] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return false }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

/// Argumente von Stream Deck: `-port N -pluginUUID … -registerEvent … -info …`.
func streamDeckArguments(_ argv: [String]) -> (port: Int, uuid: String, register: String)? {
    var a: [String: String] = [:]
    var i = 1
    while i + 1 < argv.count { a[argv[i]] = argv[i + 1]; i += 2 }
    guard let p = a["-port"].flatMap(Int.init), (1...65_535).contains(p), let u = a["-pluginUUID"], let r = a["-registerEvent"] else {
        return nil
    }
    return (p, u, r)
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum Display {
    /// Stufe → Beschriftung: ⅓ ⅜ ½ ⅝ ⅔ (24stel-Raster).
    static func stopLabel(_ stop: Int) -> String {
        switch stop {
        case 8: "⅓"
        case 9: "⅜"
        case 12: "½"
        case 15: "⅝"
        case 16: "⅔"
        default: "–"
        }
    }

    /// 8 → 0 %, 16 → 100 %.
    static func percent(_ stop: Int) -> Int { max(0, min(100, (stop - 8) * 100 / 8)) }

    static func text(_ s: DeckWire.State) -> String {
        switch s.seam {
        case .ok, .atEnd: s.stop.map(stopLabel) ?? "–"
        case .noPair: "erst Teilen"
        case .noWindow: "kein Fenster"
        case .needsPermission: "Freigabe fehlt"
        }
    }

    /// Beschriftung je Fläche (steht oben auf der Taste, das Symbol kommt aus `imgs/key-place-<Fläche>@2x.png`).
    static let labels: [DeckWire.Place: String] = [
        .split: "Teilen", .left: "Links", .right: "Rechts", .up: "Oben", .down: "Unten",
        .topLeft: "Oben links", .topRight: "Oben rechts", .bottomLeft: "Unten links", .bottomRight: "Unten rechts",
        .firstThird: "1. Drittel", .centerThird: "Mitte", .lastThird: "3. Drittel",
        .firstTwoThirds: "2/3 links", .centerTwoThirds: "2/3 Mitte", .lastTwoThirds: "2/3 rechts",
        .maximize: "Maximal", .center: "Zentriert", .restore: "Original",
        .nextDisplay: "Nächster", .previousDisplay: "Voriger",
    ]

    /// Ringe für „Platz“ am Drehregler: drehen wählt, Drücken wendet an.
    static let rings: [String: (name: String, items: [DeckWire.Place])] = [
        "halves": ("Hälften", [.left, .right, .up, .down, .maximize, .center, .restore, .split]),
        "thirds": ("Drittel", [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
        "quarters": ("Viertel", [.topLeft, .topRight, .bottomRight, .bottomLeft]),
    ]

    /// Bild aus dem Plugin-Ordner als `data:`-URL (nur feste Namen aus dieser Datei, nie aus einer Nachricht), gemerkt im Speicher.
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    static func image(_ name: String) -> String? {
        if let hit = cache[name] { return hit }
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent(),
              let data = try? Data(contentsOf: dir.appendingPathComponent("imgs/\(name)@2x.png")) else { return nil }
        let url = "data:image/png;base64," + data.base64EncodedString()
        cache[name] = url
        return url
    }
}

/// Eine Aktion auf dem Gerät.
struct DeckAction {
    enum Kind { case seam, place }
    let kind: Kind
    var onDial: Bool
    var place: DeckWire.Place = .left
    var dir = 1
    /// Regler „Platz“: Ring und vorgewählte Stelle (nur lokal, bis Drücken).
    var ring = "halves"
    var index = 0
}

@MainActor
final class Plugin {

    static let seamAction = "dev.mwlr.seam.deck.seam"
    static let placeAction = "dev.mwlr.seam.deck.place"

    private let task: URLSessionWebSocketTask
    private let seam = SeamSocket()
    private var actions: [String: DeckAction] = [:]
    private var state: DeckWire.State?
    private var reconnect: Timer?

    init(port: Int, uuid: String, register: String) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        sendDeck(["event": register, "uuid": uuid])
        seam.onState = { [weak self] s in self?.received(s) }
        seam.onConnectionChange = { [weak self] up in self?.connectionChanged(up) }
        receiveLoop()
        tryConnect()
        reconnect = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tryConnect() }
        }
        reconnect?.tolerance = 0.5
    }

    // MARK: Stream Deck

    private func sendDeck(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { error in if error != nil { log.error("Senden an Stream Deck fehlgeschlagen") } }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .failure:
                    log.notice("Stream Deck getrennt – Ende")
                    exit(0)
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self?.handle(obj)
                    }
                    self?.receiveLoop()
                }
            }
        }
    }

    private func handle(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String else { return }
        let ctx = obj["context"] as? String
        let payload = obj["payload"] as? [String: Any] ?? [:]
        switch event {
        case "willAppear", "didReceiveSettings":
            guard let ctx, let action = obj["action"] as? String else { return }
            let settings = payload["settings"] as? [String: Any] ?? [:]
            // Nur die feste Auswahl; alles andere → Voreinstellung.
            let place = (settings["what"] as? String).flatMap(DeckWire.Place.init(rawValue:)) ?? .left
            let dirText = (settings["dir"] as? String) ?? (settings["dir"] as? Int).map(String.init)
            let dir = dirText == "-1" ? -1 : 1
            let onDial = (payload["controller"] as? String) == "Encoder"
            var a = actions[ctx] ?? DeckAction(kind: action == Self.placeAction ? .place : .seam, onDial: onDial)
            if event == "willAppear" { a.onDial = onDial }
            a.place = place
            a.dir = dir
            let ring = (settings["ring"] as? String).flatMap { Display.rings[$0] != nil ? $0 : nil } ?? "halves"
            if ring != a.ring { a.index = 0 }
            a.ring = ring
            actions[ctx] = a
            render(ctx)
            tryConnect()
        case "willDisappear":
            if let ctx { actions[ctx] = nil }
        case "dialRotate":
            guard let ctx, let ticks = payload["ticks"] as? Int, ticks != 0 else { return }
            if var a = actions[ctx], a.kind == .place {
                // Nur wählen, nichts bewegen: jede Raste ein Schritt im Ring, angewendet wird erst beim Drücken.
                let count = Display.rings[a.ring]?.items.count ?? 1
                a.index = ((a.index + (ticks > 0 ? 1 : -1)) % count + count) % count
                actions[ctx] = a
                render(ctx)
                return
            }
            guard actions[ctx]?.kind == .seam else { return }
            guard check(ctx) else { return }
            // Eine Stufe je Raste, höchstens 4 je Ereignis; Seam rechnet die Stufe, nie das Plugin.
            for _ in 0..<min(abs(ticks), 4) { seam.send(.seam(dir: ticks > 0 ? 1 : -1)) }
        case "dialUp", "touchTap":
            // Naht-Regler: Drücken = Teilen. Platz-Regler: Drücken oder Tippen = vorgewählte Fläche anwenden.
            guard let ctx, let a = actions[ctx], check(ctx) else { return }
            if a.kind == .place {
                if let p = Display.rings[a.ring]?.items[safe: a.index] { seam.send(.place(p)) }
            } else if event == "dialUp" {
                seam.send(.place(.split))
            }
        case "keyDown":
            guard let ctx, let a = actions[ctx], check(ctx) else { return }
            switch a.kind {
            case .seam: seam.send(.seam(dir: a.dir))
            case .place: seam.send(.place(a.place))
            }
        default:
            break
        }
    }

    /// Nicht verbunden → Warnzeichen (nie stumm scheitern).
    private func check(_ ctx: String) -> Bool {
        if seam.isConnected { return true }
        sendDeck(["event": "showAlert", "context": ctx])
        tryConnect()
        return false
    }

    // MARK: Seam

    private func tryConnect() {
        guard !seam.isConnected, !actions.isEmpty else { return }
        seam.connect()
    }

    private func connectionChanged(_ up: Bool) {
        if up {
            seam.send(.hello(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"))
        } else {
            state = nil
        }
        for ctx in actions.keys { render(ctx) }
    }

    private func received(_ s: DeckWire.State) {
        state = s
        for ctx in actions.keys { render(ctx) }
        let problem = s.seam == .noPair || s.seam == .noWindow || s.seam == .needsPermission
        if problem, let ctx = actions.first(where: { $0.value.kind == .seam })?.key { sendDeck(["event": "showAlert", "context": ctx]) }
    }

    // MARK: Anzeige

    private func render(_ ctx: String) {
        guard let a = actions[ctx] else { return }
        switch a.kind {
        case .seam:
            let value = !seam.isConnected ? "Seam fehlt" : state.map(Display.text) ?? "–"
            if a.onDial {
                let pct = (state?.seam == .ok || state?.seam == .atEnd) ? state?.stop.map(Display.percent) ?? 50 : 50
                sendDeck(["event": "setFeedback", "context": ctx,
                          "payload": ["title": "Naht", "value": value, "indicator": ["value": pct]]])
            } else {
                setImage(ctx, Display.image(a.dir > 0 ? "key-seam-plus" : "key-seam-minus"))
                let name = a.dir > 0 ? "Naht +" : "Naht −"
                // Oben: Name, darunter (nach einem Befehl) die Stufe oder der Grund, warum nichts geschah.
                let title = value == "–" ? name : "\(name)\n\(value)"
                sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": title, "target": 0]])
            }
        case .place where a.onDial:
            let ring = Display.rings[a.ring]
            let p = ring?.items[safe: a.index] ?? .left
            var fb: [String: Any] = ["title": ring?.name ?? "Platz", "value": Display.labels[p] ?? "",
                                     "indicator": ["value": ((a.index + 1) * 100) / max(1, ring?.items.count ?? 1)]]
            if let icon = Display.image("key-place-\(p.rawValue)") { fb["icon"] = icon }
            sendDeck(["event": "setFeedback", "context": ctx, "payload": fb])
        case .place:
            setImage(ctx, Display.image("key-place-\(a.place.rawValue)"))
            sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": Display.labels[a.place] ?? "", "target": 0]])
        }
    }

    private func setImage(_ ctx: String, _ image: String?) {
        guard let image else { return }
        sendDeck(["event": "setImage", "context": ctx, "payload": ["image": image, "target": 0]])
    }
}

// MARK: Start

guard parentIsStreamDeck() else {
    log.error("Nicht von Stream Deck gestartet – Ende")
    exit(0)
}
guard let args = streamDeckArguments(CommandLine.arguments) else {
    log.error("Argumente von Stream Deck fehlen – Ende")
    exit(1)
}
let plugin = Plugin(port: args.port, uuid: args.uuid, register: args.register)
withExtendedLifetime(plugin) { RunLoop.main.run() }
