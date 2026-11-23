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
    /// Alles, was Seam dem Deck-Weg zur Verfügung stellt (E20): Fensterbefehle und die zwei Layout-Befehle.
    struct Hooks {
        /// Führt den Befehl aus und liefert Ausgang und Ergebnis des letzten Naht-Befehls.
        var run: (Command) -> (Engine.PerformResult, WindowActions.SeamOutcome?)
        /// Layout der aktuellen Bildschirm-Kombination speichern (ersetzt das vorige).
        var save: () -> Bool
        /// Layout wiederherstellen (`automatic: false`). nil = Lauf gestartet, sonst der Grund.
        var tidy: () -> DeskBlock?
        var deskRunning: () -> Bool
        /// Bild weiter/zurück (±1) oder nur Zustand (nil), siehe `Engine.deckWallpaper`.
        var wallpaper: (Int?) -> DeckWire.Wallpaper
        /// Pfad des gerade geltenden Hintergrund-Bildes (nur für die Vorschau, E20m).
        var imagePath: () -> String?
    }
    @ObservationIgnored private let hooks: Hooks
    @ObservationIgnored private var server: DeckServer?
    @ObservationIgnored private var connected = false
    /// Socket ließ sich nicht öffnen, obwohl der Schalter an ist: Die Einstellungen zeigen es (nie stumm scheitern).
    private(set) var failed = false
    /// Zuletzt gesendeter Zustand: nur Änderungen gehen raus (höchstens so oft, wie Befehle kommen).
    @ObservationIgnored private var lastState: DeckWire.State?

    /// Mindestabstand der Layout-Befehle (E20k): ein Fehlgriff darf Layout und Eingabestrom nicht mehrfach auslösen.
    nonisolated static let deskInterval: TimeInterval = 3
    @ObservationIgnored private var lastDeskCommand = Date.distantPast
    /// Mindestabstand der Bildwechsel (E20l): Aufbau des Hintergrunds dauert, der Rest wird verworfen, nicht aufgestaut.
    nonisolated static let wallpaperInterval: TimeInterval = 1.5
    @ObservationIgnored private var lastWallpaperStep = Date.distantPast
    /// Zuletzt gelesener Hintergrund-Zustand: Platz- und Naht-Befehle lesen den Bildordner nicht jedes Mal neu (Code-Audit 23.11.).
    @ObservationIgnored private var cachedWallpaper: DeckWire.Wallpaper?
    /// Vorschau (E20m): nur für Plugins, die sie im `hello` melden, und nur mit dem Schalter. Gesendet wird nur bei Änderung.
    @ObservationIgnored private var pluginTakesPreview = false
    @ObservationIgnored private var lastPreviewPath: String??
    /// Ergebnis des letzten Layout-Befehls bzw. -Laufs, bis der nächste kommt.
    @ObservationIgnored private var lastDesk: (DeckWire.Desk.Last, DeckWire.Desk.Reason?)?

    init(prefs: Preferences, hooks: Hooks) {
        self.prefs = prefs
        self.hooks = hooks
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
            pluginTakesPreview = false
            lastPreviewPath = nil
            return
        }
        connected = true
        switch c {
        case .hello(_, let preview):
            pluginTakesPreview = preview
            lastPreviewPath = nil
            cachedWallpaper = nil
            send(Self.state(.done, nil, after: c), force: true)
        case .seam, .place:
            guard let cmd = Self.command(for: c) else { return }
            let (result, outcome) = hooks.run(cmd)
            send(Self.state(result, outcome, after: c), force: false)
        case .deskSave, .deskTidy:
            deskCommand(c)
        case .wallpaper(let dir):
            let now = Date()
            guard now.timeIntervalSince(lastWallpaperStep) >= Self.wallpaperInterval else {
                var w = hooks.wallpaper(nil)
                if w.phase == .ok { w.phase = .busy }
                return send(Self.state(.done, nil, after: c), force: false, wallpaper: w)
            }
            lastWallpaperStep = now
            send(Self.state(.done, nil, after: c), force: false, wallpaper: hooks.wallpaper(dir))
        }
    }

    // MARK: Layout (Stufe 2)

    @ObservationIgnored private var lastDeskCmd: DeckWire.Desk.Cmd?

    private func deskCommand(_ c: DeckWire.Command) {
        lastDeskCmd = c == .deskSave ? .save : .tidy
        let now = Date()
        if now.timeIntervalSince(lastDeskCommand) < Self.deskInterval {
            lastDesk = (.blocked, .cooldown)
            return send(Self.state(.done, nil, after: c), force: false)
        }
        lastDeskCommand = now
        lastDesk = nil
        if c == .deskSave {
            if hooks.deskRunning() { lastDesk = (.blocked, .running) } else { lastDesk = (hooks.save() ? .ok : .blocked, nil) }
        } else if let block = hooks.tidy() {
            lastDesk = (.blocked, Self.reason(for: block))
        }   // gestartet: Phase „running“, das Ergebnis kommt in `deskFinished`
        send(Self.state(.done, nil, after: c), force: false)
    }

    /// Lauf zu Ende (von `Engine.deskFinished`): Ergebnis aufs Gerät.
    func deskFinished(_ r: DeskRunResult) {
        lastDeskCmd = .tidy
        lastDesk = r.aborted.map { (.aborted, Self.reason(for: $0)) } ?? (.ok, nil)
        send(Self.state(.done, nil, after: .deskTidy), force: false)
    }

    private func currentDesk() -> DeckWire.Desk {
        var d = DeckWire.Desk(phase: .none, apps: nil, last: lastDesk?.0, reason: lastDesk?.1, cmd: lastDesk == nil ? nil : lastDeskCmd)
        if hooks.deskRunning() {
            d.phase = .running
        } else if let layout = prefs.deskLayouts[DeskLayouts.liveScreens().combinationKey] {
            d.phase = .saved
            d.apps = Set(layout.entries.map(\.bundleID) + layout.everywhere.map(\.bundleID)).count
        }
        return d
    }

    nonisolated static func reason(for b: DeskBlock) -> DeckWire.Desk.Reason {
        switch b {
        case .noLayout: .noLayout
        case .noAccessibility: .noAccessibility
        case .switchKeysOff: .switchKeys
        case .screenLocked: .locked
        case .fullScreenActive: .fullScreen
        case .cooldown: .cooldown
        case .alreadyRunning: .running
        case .spacesUnavailable: .spaces
        }
    }

    nonisolated static func reason(for a: DeskRunResult.Abort) -> DeckWire.Desk.Reason {
        switch a {
        case .userInput: .userInput
        case .modifiersStuck: .modifiersStuck
        case .timeLimit: .timeLimit
        }
    }

    private func send(_ state: DeckWire.State, force: Bool, wallpaper: DeckWire.Wallpaper? = nil) {
        var s = state
        s.desk = currentDesk()
        if let wallpaper { cachedWallpaper = wallpaper } else if cachedWallpaper == nil { cachedWallpaper = hooks.wallpaper(nil) }
        s.wallpaper = cachedWallpaper
        guard connected, let server else { return }
        if force || s != lastState {
            lastState = s
            server.send(DeckWire.encode(s))
        }
        pushPreview(server)
    }

    /// Vorschau des geltenden Bildes (E20m): 200 × 100, ≤ 5000 Byte, im Hintergrund erzeugt, nie auf Platte, nie der ganze Ring.
    /// Schalter aus oder Video → „keine Vorschau“ (einmal gemeldet, wenn vorher eine gesendet wurde).
    private func pushPreview(_ server: DeckServer) {
        guard pluginTakesPreview else { return }
        let path = prefs.deckPreview ? hooks.imagePath() : nil
        guard lastPreviewPath != .some(path) else { return }
        let first = lastPreviewPath == nil
        lastPreviewPath = .some(path)
        guard let path else {
            if !first { server.send(DeckWire.encodePreview(nil) ?? [:], max: DeckWire.maxPreviewFrame) }
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let jpeg = ImageRing.previewJPEG(of: URL(fileURLWithPath: path))
            await MainActor.run {
                guard let self, self.connected, self.lastPreviewPath == .some(path) else { return }
                server.send(DeckWire.encodePreview(jpeg) ?? DeckWire.encodePreview(nil) ?? [:], max: DeckWire.maxPreviewFrame)
            }
        }
    }

    // MARK: Rein, getestet

    /// Positivliste: nur diese Befehle erreicht das Deck, nie ein rohes `Command`.
    nonisolated static func command(for c: DeckWire.Command) -> Command? {
        switch c {
        case .hello, .deskSave, .deskTidy, .wallpaper: nil
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
        guard case .seam = c else { return .init(seam: .ok, stop: nil) }   // Plätze und Layout-Befehle: Stufe unbekannt
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
