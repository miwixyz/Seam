import AppKit
import Observation
import OSLog
import Security

/// Stream Deck (0.12.0, docs/SECURE-DESIGN.md E20): Socket `deck.sock` für das eigene Plugin „SeamDeck“, solange „Stream Deck“ an ist.
///
/// - Vor dem ersten Byte geprüft: Peer = Developer ID + `dev.mwlr.seam.deck`, **und** sein Elternprozess = Elgatos Stream Deck.
/// - Befehle nur aus der festen Liste (`DeckWire.parse`), höchstens 20/s, eine Verbindung.
/// - Befehle laufen über `Engine.perform` (dieselbe Zielwahl wie das Popover, E15), nie über Hotkeys. Jeder Befehl ist eine Geste
///   des Nutzers (E5); das Plugin sendet nie von selbst.
/// - Rückkanal: nur Aufzählungswerte und Zahlen. Nie App-, Fenster-, Datei- oder Bildschirmnamen. Nie Inhalte ins Protokoll.
@MainActor
@Observable
final class DeckLink {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "streamdeck")

    @ObservationIgnored private let prefs: Preferences
    /// Führt den Befehl aus und liefert Ausgang und Ergebnis des letzten Naht-Befehls.
    @ObservationIgnored private let run: (Command) -> (Engine.PerformResult, WindowActions.SeamOutcome?)
    @ObservationIgnored private var server: DeckServer?
    @ObservationIgnored private var connected = false
    /// Socket ließ sich nicht öffnen, obwohl der Schalter an ist: Die Einstellungen zeigen es (nie stumm scheitern).
    private(set) var failed = false
    /// Zuletzt gesendeter Zustand: nur Änderungen gehen raus (höchstens so oft, wie Befehle kommen).
    @ObservationIgnored private var lastState: DeckWire.State?

    init(prefs: Preferences, run: @escaping (Command) -> (Engine.PerformResult, WindowActions.SeamOutcome?)) {
        self.prefs = prefs
        self.run = run
    }

    /// Schalter angewendet: an → Socket öffnen, aus → schließen und Datei löschen (E20/6).
    func apply() {
        if prefs.deckEnabled { failed = !start() } else { stop(); failed = false }
    }

    /// false = sollte laufen, tut es aber nicht.
    private func start() -> Bool {
        guard !Engine.isRunningTests, !Engine.isPreview else { return true }
        guard server == nil else { return true }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        var peer: SecRequirement?
        var parent: SecRequirement?
        guard SecRequirementCreateWithString(DeckWire.pluginRequirement as CFString, [], &peer) == errSecSuccess, let peer,
              SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &parent) == errSecSuccess, let parent else {
            Self.log.error("Stream Deck: Anforderung ungültig")
            return false
        }
        // „Seam“ legt sonst erst die Hintergrund-Ablage an; ohne den Ordner scheiterte der Start (Code-Audit 23.11.).
        let appFolder = base.appendingPathComponent("Seam", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        let dir = appFolder.appendingPathComponent(DeckWire.socketFolder, isDirectory: true)
        let s = DeckServer(directory: dir, requirement: peer, parentRequirement: parent) { [weak self] c in
            Task { @MainActor in self?.receive(c) }
        }
        do {
            try s.start()
        } catch {
            Self.log.error("Stream Deck aus: \(String(describing: error), privacy: .public)")
            return false
        }
        server = s
        return true
    }

    private func stop() {
        server?.stop()
        server = nil
        connected = false
        lastState = nil
    }

    private func receive(_ c: DeckWire.Command?) {
        guard let c else {
            connected = false
            lastState = nil
            return
        }
        connected = true
        switch c {
        case .hello:
            send(Self.state(.done, nil, after: c), force: true)
        case .seam, .place:
            guard let cmd = Self.command(for: c) else { return }
            let (result, outcome) = run(cmd)
            send(Self.state(result, outcome, after: c), force: false)
        }
    }

    private func send(_ s: DeckWire.State, force: Bool) {
        guard connected, let server, force || s != lastState else { return }
        lastState = s
        server.send(DeckWire.encode(s))
    }

    // MARK: Rein, getestet

    /// Positivliste: nur diese Befehle erreicht das Deck, nie ein rohes `Command`.
    nonisolated static func command(for c: DeckWire.Command) -> Command? {
        switch c {
        case .hello: nil
        case .seam(let dir): dir > 0 ? .seamRight : .seamLeft
        case .place(let p):
            switch p {
            case .split: .split
            case .left: .left
            case .right: .right
            case .up: .up
            case .down: .down
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            case .firstThird: .firstThird
            case .centerThird: .centerThird
            case .lastThird: .lastThird
            case .firstTwoThirds: .firstTwoThirds
            case .centerTwoThirds: .centerTwoThirds
            case .lastTwoThirds: .lastTwoThirds
            case .maximize: .maximize
            case .center: .center
            case .restore: .restore
            case .nextDisplay: .nextDisplay
            case .previousDisplay: .previousDisplay
            }
        }
    }

    /// Zustand für das Gerät. Stufe nur nach einem Naht-Befehl; nach einem Platz-Befehl ist sie unbekannt (Fenster haben sich bewegt).
    nonisolated static func state(_ result: Engine.PerformResult, _ outcome: WindowActions.SeamOutcome?,
                                  after c: DeckWire.Command) -> DeckWire.State {
        switch result {
        case .notRunning: return .init(seam: .needsPermission, stop: nil)
        case .noWindow: return .init(seam: .noWindow, stop: nil)
        case .done: break
        }
        guard case .seam = c else { return .init(seam: .ok, stop: nil) }
        switch outcome {
        case .moved(let stop): return .init(seam: .ok, stop: stop)
        case .atEnd(let stop): return .init(seam: .atEnd, stop: stop)
        case .noPair: return .init(seam: .noPair, stop: nil)
        case nil: return .init(seam: .noWindow, stop: nil)   // Naht-Befehl ohne Wirkung (Fenster nicht lesbar)
        }
    }

    // MARK: Plugin installieren

    nonisolated static var pluginSource: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(DeckWire.pluginFolder, isDirectory: true)
    }

    enum InstallError: Error, Equatable { case missing, unsigned, pack }

    /// Paket für Stream Deck im Prozess packen und an Stream Deck übergeben. Stream Deck fragt selbst nach; Seam schreibt nie
    /// in Elgatos Ordner. Nur ein Plugin mit gültiger eigener Signatur wird übergeben.
    static func installPlugin() -> Result<Void, InstallError> {
        guard let src = pluginSource, FileManager.default.fileExists(atPath: src.path) else { return .failure(.missing) }
        guard isGenuinePlugin(src.appendingPathComponent(DeckWire.executable)) else { return .failure(.unsigned) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SeamDeck-\(UUID().uuidString)", isDirectory: true)
        var packed: URL?
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var error: NSError?
            // Das System packt den Ordner als Zip (oberste Ebene = Ordnername), wie Stream Deck es erwartet.
            NSFileCoordinator().coordinate(readingItemAt: src, options: .forUploading, error: &error) { zipped in
                let target = dir.appendingPathComponent("Seam.streamDeckPlugin")
                packed = (try? FileManager.default.copyItem(at: zipped, to: target)) != nil ? target : nil
            }
            guard error == nil, let packed else { return .failure(.pack) }
            NSWorkspace.shared.open(packed)
            Self.log.notice("Stream Deck: Plugin-Paket übergeben")
            return .success(())
        } catch {
            Self.log.error("Stream Deck: Paket nicht gepackt")
            return .failure(.pack)
        }
    }

    nonisolated static func isGenuinePlugin(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(DeckWire.pluginRequirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
