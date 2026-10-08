import CoreGraphics

// Reine Rechenlogik, ohne Systemzugriffe, vollständig getestet (SeamTests).
// Koordinaten: Bedienungshilfen-System, Ursprung oben links auf dem
// Hauptbildschirm, y nach unten.

enum Geometry {

    // MARK: - Koordinaten

    /// AppKit (`NSScreen.frame`, Ursprung unten links) → Bedienungshilfen (oben links).
    /// `primaryHeight` = Höhe des Hauptbildschirms (der mit der Menüleiste).
    static func toAX(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Umkehrung, für Overlay-Fenster (AppKit).
    static func toAppKit(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - Raster

    /// Pixelrechteck einer Rasterfläche im sichtbaren Bereich `visible`.
    /// `gap` ist Magnets „Abstand um Fenster“: voller Abstand zum Bildschirmrand,
    /// zwischen zwei Fenstern insgesamt ebenfalls `gap` (je Seite die Hälfte).
    static func rect(for c: Cells, in visible: CGRect, _ o: Orientation, gap: CGFloat) -> CGRect {
        let cw = visible.width / CGFloat(o.columns), ch = visible.height / CGFloat(o.rows)
        var minX = visible.minX + CGFloat(c.x) * cw
        var maxX = visible.minX + CGFloat(c.x + c.w) * cw
        var minY = visible.minY + CGFloat(c.y) * ch
        var maxY = visible.minY + CGFloat(c.y + c.h) * ch
        minX += c.x == 0 ? gap : gap / 2
        maxX -= c.x + c.w == o.columns ? gap : gap / 2
        minY += c.y == 0 ? gap : gap / 2
        maxY -= c.y + c.h == o.rows ? gap : gap / 2
        // Kanten runden, nicht Lage und Breite einzeln: Sonst liegen zwei
        // benachbarte Flächen um 1 px auseinander oder übereinander.
        minX.round(); maxX.round(); minY.round(); maxY.round()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Andocken per Ziehen

    /// Wie nah der Mauszeiger am Bildschirmrand sein muss, damit Andocken greift.
    static let edgeTouch: CGFloat = 4

    /// Rasterzelle unter dem Mauszeiger, bezogen auf den GANZEN Bildschirm
    /// (`screen` inkl. Menüleiste): Man zieht mit der Maus an den echten Rand.
    static func cell(at p: CGPoint, screen: CGRect, _ o: Orientation) -> (col: Int, row: Int) {
        let col = Int(((p.x - screen.minX) / screen.width * CGFloat(o.columns)).rounded(.down))
        let row = Int(((p.y - screen.minY) / screen.height * CGFloat(o.rows)).rounded(.down))
        return (min(max(col, 0), o.columns - 1), min(max(row, 0), o.rows - 1))
    }

    static func touchesEdge(_ p: CGPoint, screen: CGRect) -> Bool {
        p.x - screen.minX <= edgeTouch || screen.maxX - p.x <= edgeTouch + 1
            || p.y - screen.minY <= edgeTouch || screen.maxY - p.y <= edgeTouch + 1
    }

    /// Welches Kommando gilt für diese Mausposition beim Ziehen?
    ///
    /// Ausgelöst wird erst, wenn der Zeiger den Bildschirmrand berührt (wie Magnet).
    /// Danach bleibt die Zone „eingerastet“, solange der Zeiger in einer
    /// Auslösefläche bleibt. So erreicht man auch Flächen eine Zeile vom Rand
    /// entfernt (Magnets „mittlere zwei Drittel“ liegt in Zeile 10 von 12).
    static func activeCommand(at p: CGPoint, screen: CGRect, _ o: Orientation,
                              engaged: Bool) -> Command? {
        guard screen.contains(p) || touchesEdge(p, screen: screen) else { return nil }
        guard engaged || touchesEdge(p, screen: screen) else { return nil }
        let (col, row) = cell(at: p, screen: screen, o)
        return Layout.specs(o).first { spec in
            spec.activation.contains { $0.contains(col: col, row: row) }
        }?.command
    }

    // MARK: - Mitziehen an gemeinsamen Kanten

    enum Edge: CaseIterable, Sendable { case left, right, top, bottom }

    /// Wie weit zwei Kanten auseinanderliegen dürfen, um als „gemeinsam“ zu gelten,
    /// über den eigentlichen Abstand hinaus.
    /// 16 statt anfangs 6 (08.10.): Edge landete nach dem Nachstellen 9 px neben dem
    /// Soll, danach galten die Fenster nicht mehr als Nachbarn.
    static let linkTolerance: CGFloat = 16

    struct Neighbor: Equatable, Sendable {
        let id: Int          // frei wählbare Kennung des Aufrufers
        let frame: CGRect
    }

    /// Welche Kanten hat der Nutzer gepackt? Die Kanten des Startrahmens, die
    /// höchstens `radius` vom Klickpunkt entfernt sind (Ecken: zwei Kanten).
    static func grabbedEdges(at p: CGPoint, frame f: CGRect, radius: CGFloat) -> [Edge] {
        var out: [Edge] = []
        let inY = p.y >= f.minY - radius && p.y <= f.maxY + radius
        let inX = p.x >= f.minX - radius && p.x <= f.maxX + radius
        if inY, abs(p.x - f.minX) <= radius { out.append(.left) }
        if inY, abs(p.x - f.maxX) <= radius { out.append(.right) }
        if inX, abs(p.y - f.minY) <= radius { out.append(.top) }
        if inX, abs(p.y - f.maxY) <= radius { out.append(.bottom) }
        return out
    }

    /// Setzt Kanten, die der Nutzer NICHT gepackt hat, auf den Startwert zurück,
    /// sofern sie sich höchstens um `slack` bewegt haben.
    ///
    /// Gemessen 2026-10-08 auf macOS 27.0.1: Zieht man die linke Kante eines
    /// Fensters, dessen rechte Kante 5 px vor dem Bildschirmrand steht, zieht
    /// macOS die rechte Kante an den Rand (3435 → 3440), auch ganz ohne Seam.
    /// Der Abstand am Rand ginge sonst bei jedem Ziehen verloren.
    static func keepUngrabbedEdges(now n: CGRect, start s: CGRect, grabbed: [Edge], slack: CGFloat) -> CGRect {
        guard !grabbed.isEmpty else { return n }
        var minX = n.minX, maxX = n.maxX, minY = n.minY, maxY = n.maxY
        if !grabbed.contains(.left), abs(minX - s.minX) <= slack { minX = s.minX }
        if !grabbed.contains(.right), abs(maxX - s.maxX) <= slack { maxX = s.maxX }
        if !grabbed.contains(.top), abs(minY - s.minY) <= slack { minY = s.minY }
        if !grabbed.contains(.bottom), abs(maxY - s.maxY) <= slack { maxY = s.maxY }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Welche Kanten hat der Nutzer bewegt? Vergleich Start ↔ jetzt.
    static func movedEdges(from s: CGRect, to n: CGRect) -> [Edge] {
        let e: CGFloat = 0.5
        var out: [Edge] = []
        if abs(n.minX - s.minX) > e { out.append(.left) }
        if abs(n.maxX - s.maxX) > e { out.append(.right) }
        if abs(n.minY - s.minY) > e { out.append(.top) }
        if abs(n.maxY - s.maxY) > e { out.append(.bottom) }
        // Reines Verschieben bewegt alle Kanten gleich: kein Größenziehen.
        if abs(n.width - s.width) <= e && abs(n.height - s.height) <= e { return [] }
        return out
    }

    /// Neue Rahmen der Nachbarfenster, wenn das führende Fenster von `start` auf
    /// `now` geändert wurde. Nur Fenster, deren Kante beim Gestenbeginn an der
    /// bewegten Kante lag. Der ursprüngliche Abstand je Fenster bleibt erhalten.
    ///
    /// - Gegenüberliegende Fenster (die rechts von einer bewegten rechten Kante
    ///   liegen) verschieben ihre zugewandte Kante und behalten die abgewandte.
    /// - Gleichseitige Fenster (z. B. ein zweites Fenster links, untereinander
    ///   gestapelt, mit derselben rechten Kante) ziehen ihre Kante mit, damit die
    ///   Naht durchgehend bleibt.
    static func linkedFrames(start s: CGRect, now n: CGRect,
                             neighbors: [Neighbor], gap: CGFloat) -> [Int: CGRect] {
        let tol = gap + linkTolerance
        var result: [Int: CGRect] = [:]

        for edge in movedEdges(from: s, to: n) {
            for nb in neighbors where nb.frame != s {
                var f = result[nb.id] ?? nb.frame
                let w = nb.frame
                switch edge {
                case .right:
                    if overlapsVertically(w, s), w.minX >= s.maxX - 1, w.minX - s.maxX <= tol {
                        let g = w.minX - s.maxX
                        f = CGRect(x: n.maxX + g, y: f.minY, width: w.maxX - (n.maxX + g), height: f.height)
                    } else if abs(w.maxX - s.maxX) <= 1, w.minX < s.maxX, stacksVertically(w, s, tol: tol) {
                        f = CGRect(x: f.minX, y: f.minY, width: n.maxX - f.minX, height: f.height)
                    } else { continue }
                case .left:
                    if overlapsVertically(w, s), w.maxX <= s.minX + 1, s.minX - w.maxX <= tol {
                        let g = s.minX - w.maxX
                        f = CGRect(x: f.minX, y: f.minY, width: (n.minX - g) - w.minX, height: f.height)
                    } else if abs(w.minX - s.minX) <= 1, w.maxX > s.minX, stacksVertically(w, s, tol: tol) {
                        f = CGRect(x: n.minX, y: f.minY, width: f.maxX - n.minX, height: f.height)
                    } else { continue }
                case .bottom:
                    if overlapsHorizontally(w, s), w.minY >= s.maxY - 1, w.minY - s.maxY <= tol {
                        let g = w.minY - s.maxY
                        f = CGRect(x: f.minX, y: n.maxY + g, width: f.width, height: w.maxY - (n.maxY + g))
                    } else if abs(w.maxY - s.maxY) <= 1, w.minY < s.maxY, stacksHorizontally(w, s, tol: tol) {
                        f = CGRect(x: f.minX, y: f.minY, width: f.width, height: n.maxY - f.minY)
                    } else { continue }
                case .top:
                    if overlapsHorizontally(w, s), w.maxY <= s.minY + 1, s.minY - w.maxY <= tol {
                        let g = s.minY - w.maxY
                        f = CGRect(x: f.minX, y: f.minY, width: f.width, height: (n.minY - g) - w.minY)
                    } else if abs(w.minY - s.minY) <= 1, w.maxY > s.minY, stacksHorizontally(w, s, tol: tol) {
                        f = CGRect(x: f.minX, y: n.minY, width: f.width, height: f.maxY - n.minY)
                    } else { continue }
                }
                result[nb.id] = f
            }
        }
        return result
    }

    /// Teilen sich a und b einen senkrechten Abschnitt (für links/rechts-Nachbarn)?
    static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > 20
    }

    static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > 20
    }

    /// Liegen a und b direkt übereinander (gleiche Spalte, gemeinsame waagrechte Naht)?
    static func stacksVertically(_ a: CGRect, _ b: CGRect, tol: CGFloat) -> Bool {
        overlapsHorizontally(a, b) && (abs(a.minY - b.maxY) <= tol || abs(b.minY - a.maxY) <= tol)
    }

    static func stacksHorizontally(_ a: CGRect, _ b: CGRect, tol: CGFloat) -> Bool {
        overlapsVertically(a, b) && (abs(a.minX - b.maxX) <= tol || abs(b.minX - a.maxX) <= tol)
    }

    /// Kandidaten für das Mitziehen: Fenster, die beim Gestenbeginn an einer
    /// Kante des führenden Fensters liegen (gegenüber oder gleichseitig gestapelt).
    static func isLinkCandidate(_ w: CGRect, to s: CGRect, gap: CGFloat) -> Bool {
        let tol = gap + linkTolerance
        let opposite = (overlapsVertically(w, s) && (abs(w.minX - s.maxX) <= tol || abs(s.minX - w.maxX) <= tol))
            || (overlapsHorizontally(w, s) && (abs(w.minY - s.maxY) <= tol || abs(s.minY - w.maxY) <= tol))
        let stacked = stacksVertically(w, s, tol: tol) || stacksHorizontally(w, s, tol: tol)
        return opposite || stacked
    }

    /// Ein Nachbar hat eine Mindestgröße und wurde nicht so klein wie verlangt.
    ///
    /// Gemessen 2026-10-08: Outlook blieb bei 1415 statt 1175 px Breite stehen, danach
    /// lagen die Fenster 240 px übereinander und das Mitziehen fand keine Nachbarn mehr.
    /// Lösung: Die gemeinsame Kante bleibt an der Mindestgröße des Nachbarn stehen.
    /// Der Nachbar behält seine abgewandte Kante, das führende Fenster wird so
    /// gesetzt, dass der ursprüngliche Abstand erhalten bleibt.
    ///
    /// - Returns: korrigierter Rahmen des führenden Fensters und des Nachbarn,
    ///   oder nil, wenn nichts zu korrigieren ist.
    static func resolveMinimum(leading l: CGRect, wanted w: CGRect, actual a: CGRect) -> (leading: CGRect, neighbor: CGRect)? {
        let e: CGFloat = 1
        if a.width > w.width + e {
            if w.minX >= l.maxX - e {                         // Nachbar rechts: rechte Kante bleibt
                let n = CGRect(x: w.maxX - a.width, y: w.minY, width: a.width, height: w.height)
                let gap = w.minX - l.maxX
                return (CGRect(x: l.minX, y: l.minY, width: n.minX - gap - l.minX, height: l.height), n)
            }
            if w.maxX <= l.minX + e {                         // Nachbar links: linke Kante bleibt
                let n = CGRect(x: w.minX, y: w.minY, width: a.width, height: w.height)
                let gap = l.minX - w.maxX
                return (CGRect(x: n.maxX + gap, y: l.minY, width: l.maxX - (n.maxX + gap), height: l.height), n)
            }
        }
        if a.height > w.height + e {
            if w.minY >= l.maxY - e {                         // Nachbar unten: untere Kante bleibt
                let n = CGRect(x: w.minX, y: w.maxY - a.height, width: w.width, height: a.height)
                let gap = w.minY - l.maxY
                return (CGRect(x: l.minX, y: l.minY, width: l.width, height: n.minY - gap - l.minY), n)
            }
            if w.maxY <= l.minY + e {                         // Nachbar oben: obere Kante bleibt
                let n = CGRect(x: w.minX, y: w.minY, width: w.width, height: a.height)
                let gap = l.minY - w.maxY
                return (CGRect(x: l.minX, y: n.maxY + gap, width: l.width, height: l.maxY - (n.maxY + gap)), n)
            }
        }
        return nil
    }

    // MARK: - Bildschirmwechsel

    /// Überträgt ein Fenster proportional vom sichtbaren Bereich `from` nach `to`.
    static func transfer(_ r: CGRect, from: CGRect, to: CGRect) -> CGRect {
        let sx = to.width / from.width, sy = to.height / from.height
        let w = min(r.width * sx, to.width), h = min(r.height * sy, to.height)
        let x = to.minX + (r.minX - from.minX) * sx, y = to.minY + (r.minY - from.minY) * sy
        return clamp(CGRect(x: x, y: y, width: w, height: h), to: to)
    }

    /// Schiebt ein Rechteck vollständig in `bounds` (E5: nie außerhalb des Bildschirms).
    static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect {
        let w = min(r.width, bounds.width), h = min(r.height, bounds.height)
        let x = min(max(r.minX, bounds.minX), bounds.maxX - w)
        let y = min(max(r.minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func centered(_ r: CGRect, in bounds: CGRect) -> CGRect {
        let w = min(r.width, bounds.width), h = min(r.height, bounds.height)
        return CGRect(x: (bounds.midX - w / 2).rounded(), y: (bounds.midY - h / 2).rounded(), width: w, height: h)
    }
}
