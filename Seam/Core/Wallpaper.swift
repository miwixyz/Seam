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
    static let maxImageEdge = 8192

    private(set) var status: WallpaperStatus = .off

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var screenChange: Task<Void, Never>?
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
        job = Task { [weak self] in
            switch kind {
            case .video: await self?.startVideo(url, screens: screens, gen: gen)
            case .image: self?.startImage(url, screens: screens, gen: gen)
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
            return (s, WallpaperScreen(id: id, frame: s.frame, millimeters: mm))
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

        // Erstes Bild auch als macOS-Hintergrund. Scheitert das, läuft das Video trotzdem.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.maxImageEdge, height: Self.maxImageEdge)
        if let (frame, _) = try? await generator.image(at: .zero), gen == generation {
            _ = setDesktopImages(frame, screens: screens, rects: rects)
        }
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

    // MARK: - Standbild

    private func startImage(_ url: URL, screens: [(NSScreen, WallpaperScreen)], gen: Int) {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxImageEdge
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            fail("Bild lässt sich nicht lesen.", gen: gen)
            return
        }
        guard gen == generation else { return }
        let media = CGSize(width: image.width, height: image.height)
        let rects = WallpaperPlan.mediaRects(media: media, screens: screens.map(\.1), layout: prefs.wallpaperLayout)
        guard rects.count == screens.count else { fail("Bild hat keine Größe.", gen: gen); return }
        if let problem = setDesktopImages(image, screens: screens, rects: rects) {
            fail(problem, gen: gen)
            return
        }
        status = .image(screens: screens.count)
        Self.log.notice("Hintergrund: Bild auf \(screens.count) Bildschirmen")
    }

    /// Schneidet das Bild je Bildschirm zu, schreibt es in den eigenen Ordner (E18c) und setzt es als
    /// macOS-Hintergrund. Rückgabe: Fehlermeldung oder nil.
    private func setDesktopImages(_ image: CGImage, screens: [(NSScreen, WallpaperScreen)], rects: [CGRect]) -> String? {
        guard let dir = Self.folder() else { return "Ordner für die Bildstücke fehlt." }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        for ((screen, ws), rect) in zip(screens, rects) {
            let scale = screen.backingScaleFactor
            let pw = Int((ws.frame.width * scale).rounded()), ph = Int((ws.frame.height * scale).rounded())
            let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
            guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                return "Bildstück für einen Bildschirm ließ sich nicht anlegen."
            }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                       width: rect.width * scale, height: rect.height * scale))
            guard let piece = ctx.makeImage() else { return "Bildstück ließ sich nicht zeichnen." }
            let prefix = "seam-\(Self.safe(ws.id))-"
            let file = dir.appendingPathComponent("\(prefix)\(stamp).png")
            guard let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return "Bildstück ließ sich nicht speichern."
            }
            CGImageDestinationAddImage(dest, piece, nil)
            guard CGImageDestinationFinalize(dest) else { return "Bildstück ließ sich nicht speichern." }
            do {
                try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true
                ])
            } catch {
                Self.log.error("Hintergrund setzen fehlgeschlagen: \((error as NSError).code)")
                return "macOS hat den Hintergrund nicht übernommen."
            }
            Self.removeOld(in: dir, prefix: prefix, keep: file)
        }
        return nil
    }

    /// `~/Library/Application Support/Seam/Hintergrund/`, angelegt bei Bedarf.
    private static func folder() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Seam/Hintergrund", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// E18c: nur alte Stücke DIESES Bildschirms mit Seam-Präfix im eigenen Ordner. Stücke anderer
    /// Bildschirme bleiben — macOS zeigt sie womöglich noch an.
    private static func removeOld(in dir: URL, prefix: String, keep: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where n.hasPrefix(prefix) && n.hasSuffix(".png") && n != keep.lastPathComponent {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    /// Bildschirm-Kennung für Dateinamen: nur Buchstaben, Ziffern, Bindestrich.
    static func safe(_ id: String) -> String {
        String(id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(64))
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
