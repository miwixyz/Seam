import AppKit
import AVFoundation
import Observation
import OSLog
import UniformTypeIdentifiers

/// Was der Hintergrund gerade tut, fürs Fenster „Hintergrund“ (eigene Apps scheitern nie stumm).
enum WallpaperStatus: Equatable {
    case off
    case loading
    case video(screens: Int)
    case image(screens: Int)
    case problem(String)
}

/// Hintergrund wie Motion Desktop (E18, docs/SECURE-DESIGN.md): Video hinter den Schreibtisch-Symbolen
/// oder Standbild, als Gesamtbild über alle Bildschirme oder je Bildschirm ganz.
///
/// Video: ein randloses Fenster je Bildschirm auf Ebene `desktopWindow` (gemessen 10.11.: über dem
/// macOS-Hintergrund, unter den Finder-Symbolen), alle an EINEM Player — dadurch laufen die Stücke
/// des Gesamtbilds im Gleichtakt. Zusätzlich wird das erste Bild als macOS-Hintergrund gesetzt
/// (Mission Control, Sperrbildschirm, Seam beendet).
/// Standbild: Seam schneidet das Bild je Bildschirm zu und setzt es als macOS-Hintergrund — keine
/// Grafikleistung, bleibt auch ohne Seam.
/// Braucht keine Bedienungshilfen.
@MainActor
@Observable
final class Wallpaper {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "hintergrund")
    /// Größte Bildkante beim Laden (E18b, Speicher). rafter-code-review 10.11.: 16384 erlaubte
    /// ~1 GB je Bild (16384² × 4 Byte); 8192 (8K) deckt Michaels Bildschirme (zusammen ≤ 4520 pt
    /// breit) und begrenzt auf ~256 MB.
    nonisolated static let maxImageEdge = WallpaperPlan.maxImageEdge

    private(set) var status: WallpaperStatus = .off

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var screenChange: Task<Void, Never>?
    /// Art der aktuellen Datei, solange der Hintergrund läuft (für Space-Wechsel).
    @ObservationIgnored private var currentKind: Kind?
    @ObservationIgnored private var spaceJob: Task<Void, Never>?
    /// Zählt jeden Neuaufbau; ein älterer Ladevorgang, der spät fertig wird, verwirft sein Ergebnis.
    @ObservationIgnored private var generation = 0
    /// Hell/Dunkel (Michael, 10.11.): macOS-Darstellung beim letzten Aufbau, und ihr Beobachter.
    @ObservationIgnored private var lastDark: Bool?
    @ObservationIgnored private var appearanceWatch: NSKeyValueObservation?

    init(prefs: Preferences) { self.prefs = prefs }

    /// Ist macOS gerade dunkel? Eine Menüleisten-App folgt der Systemdarstellung.
    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Darstellung gewechselt: nur neu aufbauen, wenn hell und dunkel verschiedene Dateien haben.
    private func appearanceChanged() {
        let dark = Self.isDark
        guard dark != lastDark else { return }
        lastDark = dark
        guard prefs.wallpaperPathDark != nil, prefs.wallpaperPathDark != prefs.wallpaperPath else { return }
        apply()
    }

    // MARK: - Ein/Aus

    /// Nach jeder Änderung im Fenster und nach Bildschirmwechseln: alles neu aufbauen.
    func apply() {
        generation += 1
        let gen = generation
        job?.cancel()
        spaceJob?.cancel()
        currentKind = nil
        tearDownVideo()
        guard prefs.wallpaperEnabled else {
            removeObservers()
            status = .off
            return
        }
        addObservers()
        let dark = Self.isDark
        lastDark = dark
        guard let path = Preferences.wallpaperPath(light: prefs.wallpaperPath, dark: prefs.wallpaperPathDark, isDark: dark) else {
            status = .problem("Noch keine Datei gewählt.")
            return
        }
        let url = URL(fileURLWithPath: path)
        let kind: Kind
        switch Self.kind(of: url) {
        case .success(let k): kind = k
        case .failure(let msg):
            status = .problem(msg)
            return
        }
        let screens = targetScreens()
        guard !screens.isEmpty else {
            status = .problem("Kein Bildschirm ausgewählt.")
            return
        }
        status = .loading
        currentKind = kind
        job = Task { [weak self] in
            switch kind {
            case .video: await self?.startVideo(url, screens: screens, gen: gen)
            case .image: await self?.showStills(kind: .image, gen: gen)
            }
        }
    }

    // MARK: - Datei prüfen (E18a)

    enum Kind: Equatable { case video, image }

    enum Check: Equatable {
        case success(Kind)
        case failure(String)
    }

    static func kind(of url: URL) -> Check {
        let name = url.lastPathComponent
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure("„\(name)“ ist nicht mehr da oder nicht lesbar. Bitte neu wählen.")
        }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .failure("Art von „\(name)“ nicht erkennbar.")
        }
        if type.conforms(to: .movie) { return .success(.video) }
        if type.conforms(to: .image) { return .success(.image) }
        return .failure("„\(name)“ ist weder Video noch Bild.")
    }

    // MARK: - Bildschirme

    private func targetScreens() -> [(NSScreen, WallpaperScreen)] {
        let off = Set(prefs.wallpaperOffScreens)
        return NSScreen.screens.compactMap { s in
            guard let id = SpaceReader.displayIdentifier(of: s), !off.contains(id),
                  let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let mm = CGDisplayScreenSize(n.uint32Value)
            let offset = CGFloat(prefs.wallpaperOffsets[id] ?? 0)
            return (s, WallpaperScreen(id: id, frame: s.frame, millimeters: mm, offsetY: offset))
        }
    }

    // MARK: - Video

    private func startVideo(_ url: URL, screens: [(NSScreen, WallpaperScreen)], gen: Int) async {
        let asset = AVURLAsset(url: url)
        let media: CGSize
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                fail("Im Video ist keine Bildspur.", gen: gen)
                return
            }
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let r = CGRect(origin: .zero, size: size).applying(transform)
            media = CGSize(width: abs(r.width), height: abs(r.height))
        } catch {
            fail("Video lässt sich nicht lesen.", gen: gen, error: error)
            return
        }
        guard gen == generation else { return }
        let rects = WallpaperPlan.mediaRects(media: media, screens: screens.map(\.1), layout: prefs.wallpaperLayout)
        guard rects.count == screens.count else { fail("Video hat keine Größe.", gen: gen); return }

        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(asset: asset))
        player = p
        windows = zip(screens, rects).map { Self.makeWindow(on: $0.0.0, media: $0.1, player: p) }
        p.play()
        status = .video(screens: windows.count)
        Self.log.notice("Hintergrund: Video auf \(self.windows.count) Bildschirmen")

        // Erstes Bild auch als macOS-Hintergrund (Mission Control, Sperrbildschirm), auf jedem Space.
        await showStills(kind: .video, gen: gen)
    }

    private static func makeWindow(on screen: NSScreen, media: CGRect, player: AVPlayer) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        // E18e: über dem macOS-Hintergrund, unter den Finder-Symbolen (gemessen 10.11.).
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        let layer = AVPlayerLayer(player: player)
        // Das Rechteck hat schon das richtige Seitenverhältnis (WallpaperPlan.fill).
        layer.videoGravity = .resize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = media
        view.layer?.addSublayer(layer)
        CATransaction.commit()
        w.contentView = view
        w.setFrame(screen.frame, display: false)
        w.orderFront(nil)
        return w
    }

    private func tearDownVideo() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    // MARK: - Standbild, auf jedem Space (Michael 18.11.)

    /// macOS-Hintergrund für den GERADE aktiven Space jedes Bildschirms setzen. `setDesktopImageURL` wirkt
    /// nur auf den aktiven Space (gemessen: das Bild stand nur auf einem Space); darum ruft Seam das bei
    /// jedem Space-Wechsel erneut auf. Das Rechnen (Laden bis 8192 px, Zuschneiden, PNG) läuft außerhalb
    /// des Hauptthreads, fertige Stücke werden wiederverwendet (Audit 18.11.: vorher 1–5 s Stillstand).
    private func showStills(kind: Kind, gen: Int) async {
        // Beim Video ist das Standbild Beiwerk: Scheitert es, läuft das Video trotzdem (Code-Audit 18.11.).
        func problem(_ message: String, _ error: Error? = nil) {
            if kind == .video {
                Self.log.error("Hintergrund: Standbild zum Video nicht gesetzt: \(message, privacy: .public) \((error as NSError?)?.code ?? 0)")
            } else {
                fail(message, gen: gen, error: error)
            }
        }
        let screens = targetScreens()
        guard !screens.isEmpty else { problem("Kein Bildschirm ausgewählt."); return }
        guard let dir = Self.folder() else { problem("Ordner für die Bildstücke fehlt."); return }
        let main = Preferences.wallpaperPath(light: prefs.wallpaperPath, dark: prefs.wallpaperPathDark, isDark: Self.isDark)
        let wanted = wantedPaths(screens.map(\.1), main: main)
        let all = screens.map(\.1), scales = screens.map { $0.0.backingScaleFactor }, layout = prefs.wallpaperLayout
        var files: [String: URL] = [:]
        for (path, indices) in Dictionary(grouping: screens.indices, by: { wanted[$0] }) {
            guard let path else { continue }
            let job = PieceJob(path: path, isVideo: kind == .video && path == main, screens: all, scales: scales,
                               needed: indices, layout: layout, dir: dir)
            switch await Task.detached(priority: .utility, operation: { await PieceMaker.make(job) }).value {
            case .success(let made): files.merge(made) { _, new in new }
            case .failure(let e): problem(e.message); return
            }
        }
        guard gen == generation, !Task.isCancelled else { return }
        for (screen, ws) in screens {
            guard let file = files[ws.id], NSWorkspace.shared.desktopImageURL(for: screen) != file else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true
                ])
            } catch {
                problem("macOS hat den Hintergrund nicht übernommen.", error)
                return
            }
        }
        if kind == .image { status = .image(screens: files.count) }
        Self.log.notice("Hintergrund: Bild auf \(files.count) Bildschirmen (aktiver Space)")
        // Aufräumen: nur Stücke der Ziel-Bildschirme, die zu keiner gewählten Datei mehr passen (E18c).
        let used = Set([prefs.wallpaperPath, prefs.wallpaperPathDark].compactMap { $0 }
                       + (prefs.wallpaperPerSpace ? Array(prefs.wallpaperSpacePaths.values) : []))
        let keep = await Task.detached(priority: .utility) {
            PieceMaker.names(paths: used, screens: all, scales: scales, layout: layout)
        }.value.union(files.values.map(\.lastPathComponent))
        // Zwischen Setzen und hier lag ein `await`: Ist inzwischen ein neuerer Aufbau dran, nichts löschen.
        guard gen == generation, !Task.isCancelled else { return }
        Self.removeOld(in: dir, screens: all.map(\.id), keep: keep)
    }

    /// Welche Datei je Bildschirm? „Je Schreibtisch“: die des aktiven Space, nur Bilder (ein Video läuft
    /// ohnehin auf allen Spaces), sonst das Hauptbild.
    private func wantedPaths(_ screens: [WallpaperScreen], main: String?) -> [String?] {
        guard prefs.wallpaperPerSpace else { return screens.map { _ in main } }
        let spaces = SpaceReader.read() ?? []
        return screens.map { ws in
            let slot = SpaceNames.current(spaces, display: ws.id)?.slot
            let p = WallpaperPlan.spacePath(slot: slot, perSpace: true, spacePaths: prefs.wallpaperSpacePaths, main: main)
            guard let p, p != main else { return main }
            return Self.kind(of: URL(fileURLWithPath: p)) == .success(.image) ? p : main
        }
    }

    private func spaceChanged() {
        guard prefs.wallpaperEnabled, let kind = currentKind else { return }
        let gen = generation
        // Nacheinander, nie zwei Aufbauten gleichzeitig (Code-Audit 18.11.): erst den laufenden abwarten.
        spaceJob?.cancel()                      // ein noch wartender Wechsel ist überholt
        let before = [job, spaceJob].compactMap { $0 }
        spaceJob = Task { [weak self] in
            for t in before { await t.value }
            guard !Task.isCancelled else { return }
            await self?.showStills(kind: kind, gen: gen)
        }
    }

    /// `~/Library/Application Support/Seam/Hintergrund/`, angelegt bei Bedarf.
    private static func folder() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Seam/Hintergrund", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// E18c: nur Stücke der Ziel-Bildschirme mit Seam-Präfix im eigenen Ordner, die zu keiner gewählten
    /// Datei gehören. Stücke anderer Bildschirme bleiben — macOS zeigt sie womöglich noch an.
    private static func removeOld(in dir: URL, screens: [String], keep: Set<String>) {
        let prefixes = screens.map { "seam-\(WallpaperPlan.safe($0))-" }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where n.hasSuffix(".png") && !keep.contains(n) && prefixes.contains(where: { n.hasPrefix($0) }) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    // MARK: - Beobachter

    private func addObservers() {
        guard tokens.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        // Schlafen die Bildschirme oder ist ein anderer Nutzer dran: Video anhalten.
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.player?.pause() }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.player?.play() }
            })
        }
        // Space-Wechsel: macOS-Hintergrund für den neuen Space setzen (setDesktopImageURL wirkt je Space).
        tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        })
        // Bildschirme ändern sich oft mehrfach hintereinander: erst neu aufbauen, wenn es ruhig ist.
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
        // Hell/Dunkel: macOS meldet den Wechsel über die Darstellung der App.
        appearanceWatch = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.appearanceChanged() }
        }
    }

    private func removeObservers() {
        tokens.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        appearanceWatch?.invalidate()
        appearanceWatch = nil
        screenChange?.cancel()
        spaceJob?.cancel()
    }

    private func scheduleRebuild() {
        screenChange?.cancel()
        screenChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    private func fail(_ message: String, gen: Int, error: Error? = nil) {
        guard gen == generation else { return }
        tearDownVideo()
        status = .problem(message)
        Self.log.error("Hintergrund: \(message, privacy: .public) \((error as NSError?)?.code ?? 0)")
    }
}

// MARK: - Bildstücke rechnen (außerhalb des Hauptthreads, Audit 18.11.)

/// Auftrag: eine Quelldatei für bestimmte Bildschirme zuschneiden. Beim Gesamtbild hängt jedes Stück an allen
/// Ziel-Bildschirmen (`screens`), gebraucht werden nur die in `needed`.
struct PieceJob: Sendable {
    let path: String
    let isVideo: Bool
    let screens: [WallpaperScreen]
    let scales: [CGFloat]
    let needed: [Int]
    let layout: WallpaperLayout
    let dir: URL
}

struct PieceError: Error { let message: String }

enum PieceMaker {

    static func stamp(_ path: String) -> WallpaperPlan.SourceStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let date = a[.modificationDate] as? Date, let size = a[.size] as? NSNumber else { return nil }
        return WallpaperPlan.SourceStamp(path: path, modified: date.timeIntervalSince1970, bytes: size.intValue)
    }

    static func name(_ stamp: WallpaperPlan.SourceStamp, screen i: Int, screens: [WallpaperScreen],
                     scales: [CGFloat], layout: WallpaperLayout) -> String {
        WallpaperPlan.pieceName(screen: screens[i].id, source: stamp, layout: layout, screens: screens,
                                scale: scales[i])
    }

    /// Dateinamen aller Stücke, die zu diesen Dateien gehören (fürs Aufräumen).
    static func names(paths: Set<String>, screens: [WallpaperScreen], scales: [CGFloat], layout: WallpaperLayout) -> Set<String> {
        var out = Set<String>()
        for p in paths {
            guard let st = stamp(p) else { continue }
            for i in screens.indices { out.insert(name(st, screen: i, screens: screens, scales: scales, layout: layout)) }
        }
        return out
    }

    /// Bildschirm-Kennung → fertiges Stück. Liegt ein Stück schon da, wird es nicht neu gerechnet.
    static func make(_ job: PieceJob) async -> Result<[String: URL], PieceError> {
        let fileName = (job.path as NSString).lastPathComponent
        guard let st = stamp(job.path) else { return .failure(PieceError(message: "„\(fileName)“ ist nicht mehr da. Bitte neu wählen.")) }
        let targets = job.needed.map { i in (i, job.dir.appendingPathComponent(name(st, screen: i, screens: job.screens,
                                                                                         scales: job.scales, layout: job.layout))) }
        var out: [String: URL] = [:]
        let missing = targets.filter { !FileManager.default.fileExists(atPath: $0.1.path) }
        for (i, url) in targets where !missing.contains(where: { $0.0 == i }) { out[job.screens[i].id] = url }
        guard !missing.isEmpty else { return .success(out) }
        guard let image = await load(job) else {
            return .failure(PieceError(message: job.isVideo ? "Video lässt sich nicht lesen." : "Bild lässt sich nicht lesen."))
        }
        let rects = WallpaperPlan.mediaRects(media: CGSize(width: image.width, height: image.height),
                                             screens: job.screens, layout: job.layout)
        guard rects.count == job.screens.count else { return .failure(PieceError(message: "Bild hat keine Größe.")) }
        for (i, url) in missing {
            if let problem = draw(image, rect: rects[i], screen: job.screens[i], scale: job.scales[i], to: url) {
                return .failure(PieceError(message: problem))
            }
            out[job.screens[i].id] = url
        }
        return .success(out)
    }

    private static func load(_ job: PieceJob) async -> CGImage? {
        let url = URL(fileURLWithPath: job.path)
        if job.isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: Wallpaper.maxImageEdge, height: Wallpaper.maxImageEdge)
            return try? await generator.image(at: .zero).image
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Wallpaper.maxImageEdge
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Stück zeichnen und schreiben (erst unter Zwischennamen, dann umbenennen: nie ein halbes PNG unter dem Namen).
    private static func draw(_ image: CGImage, rect: CGRect, screen ws: WallpaperScreen, scale: CGFloat, to url: URL) -> String? {
        let pw = Int((ws.frame.width * scale).rounded()), ph = Int((ws.frame.height * scale).rounded())
        let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return "Bildstück für einen Bildschirm ließ sich nicht anlegen."
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
        guard let piece = ctx.makeImage() else { return "Bildstück ließ sich nicht zeichnen." }
        // Eindeutiger Zwischenname: Ein abgebrochener Aufbau rechnet weiter und darf dem neuen nicht dazwischenschreiben.
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)-" + url.lastPathComponent)
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return "Bildstück ließ sich nicht speichern."
        }
        CGImageDestinationAddImage(dest, piece, nil)
        guard CGImageDestinationFinalize(dest) else { return "Bildstück ließ sich nicht speichern." }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return "Bildstück ließ sich nicht speichern."
        }
        return nil
    }
}
