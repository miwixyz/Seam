import CoreGraphics

/// Ein Bildschirm für die Hintergrund-Rechnung (E18): Kennung, Lage in AppKit-Punkten (y nach oben,
/// Ursprung unten links am Hauptbildschirm) und echte Größe in Millimetern (0 = unbekannt).
struct WallpaperScreen: Equatable {
    let id: String
    let frame: CGRect
    let millimeters: CGSize
    /// Höhenausgleich in mm (Michael, 10.11.: „der rechte Bildschirm ist noch ein Tick zu weit
    /// unten“; Z1-2 steht ~13 cm unter dem PA34, macOS kennt die Lücke nicht). Positiv = höher.
    var offsetY: CGFloat = 0
}

/// Wie das Bild auf die Bildschirme kommt.
enum WallpaperLayout: String, CaseIterable {
    /// Ein Gesamtbild über alle gewählten Bildschirme, verteilt nach echter Größe.
    case span
    /// Auf jedem Bildschirm das ganze Bild.
    case each
}

/// Wo liegt das Bild auf jedem Bildschirm? Reine Rechnung, getestet (SeamTests/WallpaperPlanTests).
///
/// Gesamtbild nach echter Größe (Michael, 10.11.): macOS ordnet Bildschirme in Punkten an, die
/// Monitore haben aber verschiedene Dichten (gemessen 10.11.: PA34 4,29 pt/mm, MB169 5,67 pt/mm).
/// Nach Punkten verteilt sprang das Bild an der Kante. Deshalb: jeder Bildschirm bekommt ein Rechteck
/// in Millimetern (Größe aus seiner eigenen Dichte), Lage aus der macOS-Anordnung; Bildschirme, die
/// sich in Punkten berühren, berühren sich auch in Millimetern. Darüber das Bild „füllend“, und für
/// jeden Bildschirm zurück in seine Punkte.
enum WallpaperPlan {

    /// Punkte je Millimeter; nil, wenn macOS keine Größe kennt (dann gilt die des Hauptbildschirms).
    static func density(_ s: WallpaperScreen) -> CGFloat? {
        guard s.millimeters.width > 1, s.millimeters.height > 1, s.frame.width > 0 else { return nil }
        return s.frame.width / s.millimeters.width
    }

    /// Rechteck jedes Bildschirms in Millimetern, gleiche Reihenfolge wie `screens`.
    static func physical(_ screens: [WallpaperScreen]) -> [CGRect] {
        guard !screens.isEmpty else { return [] }
        // Bezug: der Hauptbildschirm (Ursprung 0,0), sonst der erste.
        let ref = screens.firstIndex { $0.frame.origin == .zero } ?? 0
        let refDensity = density(screens[ref]) ?? 1
        func size(_ s: WallpaperScreen) -> CGSize {
            let d = density(s) ?? refDensity
            return CGSize(width: s.frame.width / d, height: s.frame.height / d)
        }
        var out = [CGRect?](repeating: nil, count: screens.count)
        // Reihenfolge: vom Bezug aus nach Abstand, damit jeder Bildschirm an einem schon gesetzten anlegt.
        let refCenter = CGPoint(x: screens[ref].frame.midX, y: screens[ref].frame.midY)
        let order = screens.indices.sorted {
            dist(screens[$0].frame, refCenter) < dist(screens[$1].frame, refCenter)
        }
        for i in order {
            let s = screens[i]
            let sz = size(s)
            // Erst an Oberkante und linker Kante (umgerechnet mit der Bezugsdichte) …
            // Bis 0.9.0 um die Mitte: Ein Monitor, der in mm viel kürzer ist als in Punkten (MB169:
            // 338 mm statt 447 mm), rutschte damit um die halbe Differenz nach unten. Michaels Foto
            // 10.11.: Oberkante MB169 laut Anordnung 133 mm unter der des PA34, auf dem Tisch 131 mm
            // (Mitte: 191 mm, Welle 6 cm versetzt). Z1-2 links: 265 mm laut Anordnung, Tisch 268 mm.
            var r = CGRect(x: s.frame.minX / refDensity,
                           y: s.frame.maxY / refDensity - sz.height,
                           width: sz.width, height: sz.height)
            // … dann an berührende, schon gesetzte Bildschirme anlegen (sonst Lücke oder Überlappung).
            var snappedX = false, snappedY = false
            for j in order where out[j] != nil {
                let p = screens[j].frame, pr = out[j]!
                let overlapY = s.frame.minY < p.maxY && s.frame.maxY > p.minY
                let overlapX = s.frame.minX < p.maxX && s.frame.maxX > p.minX
                if !snappedX, overlapY, near(s.frame.minX, p.maxX) { r.origin.x = pr.maxX; snappedX = true }
                if !snappedX, overlapY, near(s.frame.maxX, p.minX) { r.origin.x = pr.minX - r.width; snappedX = true }
                if !snappedY, overlapX, near(s.frame.minY, p.maxY) { r.origin.y = pr.maxY; snappedY = true }
                if !snappedY, overlapX, near(s.frame.maxY, p.minY) { r.origin.y = pr.minY - r.height; snappedY = true }
            }
            // Ausgleich des Nutzers zuletzt, auch nach dem Anlegen an einen Nachbarn.
            r.origin.y += s.offsetY
            out[i] = r
        }
        return out.map { $0! }
    }

    /// Lage des Bildes je Bildschirm in dessen eigenen Punkten (Ursprung unten links des Bildschirms).
    /// Das Rechteck ist meist größer als der Bildschirm; was übersteht, wird abgeschnitten.
    static func mediaRects(media: CGSize, screens: [WallpaperScreen], layout: WallpaperLayout) -> [CGRect] {
        guard media.width > 0, media.height > 0, !screens.isEmpty else { return [] }
        switch layout {
        case .each:
            return screens.map { fill(media, into: CGRect(origin: .zero, size: $0.frame.size)) }
        case .span:
            let phys = physical(screens)
            let canvas = phys.dropFirst().reduce(phys[0]) { $0.union($1) }
            let image = fill(media, into: canvas)
            let refDensity = density(screens[screens.firstIndex { $0.frame.origin == .zero } ?? 0]) ?? 1
            return screens.indices.map { i in
                let d = density(screens[i]) ?? refDensity
                let p = phys[i]
                return CGRect(x: (image.minX - p.minX) * d, y: (image.minY - p.minY) * d,
                              width: image.width * d, height: image.height * d)
            }
        }
    }

    /// Bild füllend (Seitenverhältnis bleibt, nichts leer), mittig.
    static func fill(_ media: CGSize, into r: CGRect) -> CGRect {
        let k = max(r.width / media.width, r.height / media.height)
        let w = media.width * k, h = media.height * k
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1.5 }

    private static func dist(_ r: CGRect, _ c: CGPoint) -> CGFloat {
        hypot(r.midX - c.x, r.midY - c.y)
    }
}
