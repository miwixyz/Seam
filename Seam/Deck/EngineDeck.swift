import Foundation

/// Stream Deck, Stufe 3 (E20l): Bildwechsel aus dem gewählten Bildordner. Der Pfad ändert sich nur über
/// `Preferences.setWallpaperPath`, die bestehende einzige Stelle (E18a).
extension Engine {

    /// `dir` = +1/−1: eine Datei weiter, nil: nur Zustand lesen. Wirkt nur auf den gerade geltenden Pfad (hell oder dunkel);
    /// den anderen und das System-Aussehen lässt Seam unberührt.
    func deckWallpaper(step dir: Int?) -> DeckWire.Wallpaper {
        guard prefs.wallpaperEnabled else { return .init(phase: .off) }
        let dark = Wallpaper.isDark
        let folder = prefs.deckImageFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? OnlineGallery.folder()
        let ring = folder.map(ImageRing.files(in:)) ?? []
        guard !ring.isEmpty else { return .init(phase: .noImages) }
        var current = Preferences.wallpaperPath(light: prefs.wallpaperPath, dark: prefs.wallpaperPathDark, isDark: dark)
        if let dir, let next = ImageRing.step(from: current, in: ring, dir: dir) {
            prefs.setWallpaperPath(next.path, dark: dark)   // lehnt ungültige Pfade (> 1024 Zeichen) ab, dann bleibt alles wie es war
            wallpaper.apply()
            current = Preferences.wallpaperPath(light: prefs.wallpaperPath, dark: prefs.wallpaperPathDark, isDark: dark)
        }
        let busy = wallpaper.status == .loading
        let file = current.map(URL.init(fileURLWithPath:))
        return .init(phase: busy ? .busy : .ok, index: ImageRing.position(of: current, in: ring), count: ring.count, dark: dark,
                     kind: file.map { ImageRing.isVideo($0) ? .video : .image })
    }

    /// Pfad des Bildes, das gerade als Hintergrund gilt (hell oder dunkel). Nur für die Vorschau; nil bei ausgeschaltetem Hintergrund.
    func deckImagePath() -> String? {
        guard prefs.wallpaperEnabled else { return nil }
        return Preferences.wallpaperPath(light: prefs.wallpaperPath, dark: prefs.wallpaperPathDark, isDark: Wallpaper.isDark)
    }
}
