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

    // MARK: - Kürzel setzen den Nachbarn mit (Michael, 08.10.)

    /// Wie weit ein Nachbar von der Naht entfernt sein darf (Lücke oder Überlappung),
    /// damit ein Kürzel ihn mitsetzt. Gemessen 08.10.: 156 px Lücke bzw. 263 px
    /// Überlappung zwischen Outlook und Edge nach einzelnen Kürzeln.
    static let complementReach: CGFloat = 400

    /// Innere Kanten einer Zielfläche: die nicht am Rand des sichtbaren Bereichs liegen.
    static func innerEdges(of t: CGRect, in visible: CGRect, gap: CGFloat) -> [Edge] {
        let e = gap + 2
        var out: [Edge] = []
        if t.minX - visible.minX > e { out.append(.left) }
        if visible.maxX - t.maxX > e { out.append(.right) }
        if t.minY - visible.minY > e { out.append(.top) }
        if visible.maxY - t.maxY > e { out.append(.bottom) }
        return out
    }

    /// Neuer Rahmen für ein Fenster `w` auf der anderen Seite der Kante `edge` der
    /// Zielfläche `t`: zugewandte Kante an die Naht (mit Abstand), abgewandte bleibt.
    /// nil, wenn `w` dieser Kante nicht gegenübersteht.
    static func complement(of w: CGRect, target t: CGRect, edge: Edge, gap: CGFloat, visible: CGRect? = nil) -> CGRect? {
        let r: CGRect
        switch edge {
        case .right:
            guard w.midX > t.maxX, overlapRatioY(w, t) >= 0.5, abs(w.minX - (t.maxX + gap)) <= complementReach else { return nil }
            r = CGRect(x: t.maxX + gap, y: w.minY, width: w.maxX - (t.maxX + gap), height: w.height)
        case .left:
            guard w.midX < t.minX, overlapRatioY(w, t) >= 0.5, abs(w.maxX - (t.minX - gap)) <= complementReach else { return nil }
            r = CGRect(x: w.minX, y: w.minY, width: (t.minX - gap) - w.minX, height: w.height)
        case .bottom:
            guard w.midY > t.maxY, overlapRatioX(w, t) >= 0.5, abs(w.minY - (t.maxY + gap)) <= complementReach else { return nil }
            r = CGRect(x: w.minX, y: t.maxY + gap, width: w.width, height: w.maxY - (t.maxY + gap))
        case .top:
            guard w.midY < t.minY, overlapRatioX(w, t) >= 0.5, abs(w.maxY - (t.minY - gap)) <= complementReach else { return nil }
            r = CGRect(x: w.minX, y: w.minY, width: w.width, height: (t.minY - gap) - w.minY)
        }
        // Spannt die Zielfläche die volle Höhe (bzw. Breite), bekommt der Partner sie auch.
        // Gemessen 08.10.: Edge behielt beim Mitsetzen y 290 / Höhe 991 statt der vollen Höhe.
        var out = r
        if let v = visible {
            let e = gap + 2
            let fullHeight = t.minY - v.minY <= e && v.maxY - t.maxY <= e
            let fullWidth = t.minX - v.minX <= e && v.maxX - t.maxX <= e
            if fullHeight, edge == .left || edge == .right { out = CGRect(x: r.minX, y: t.minY, width: r.width, height: t.height) }
            if fullWidth, edge == .top || edge == .bottom { out = CGRect(x: t.minX, y: r.minY, width: t.width, height: r.height) }
        }
        return out.width >= 80 && out.height >= 60 ? out : nil
    }

    /// Anteil der Zielfläche, den `w` senkrecht bzw. waagrecht abdeckt.
    static func overlapRatioY(_ w: CGRect, _ t: CGRect) -> CGFloat {
        max(0, min(w.maxY, t.maxY) - max(w.minY, t.minY)) / max(t.height, 1)
    }

    static func overlapRatioX(_ w: CGRect, _ t: CGRect) -> CGFloat {
        max(0, min(w.maxX, t.maxX) - max(w.minX, t.minX)) / max(t.width, 1)
    }

    /// Liegt `w` an der Kante `edge` von `s` bündig gegenüber?
    static func isFacing(_ w: CGRect, to s: CGRect, gap: CGFloat, edge: Edge) -> Bool {
        let tol = gap + linkTolerance
        switch edge {
        case .right: return overlapsVertically(w, s) && abs(w.minX - s.maxX) <= tol
        case .left: return overlapsVertically(w, s) && abs(s.minX - w.maxX) <= tol
        case .bottom: return overlapsHorizontally(w, s) && abs(w.minY - s.maxY) <= tol
        case .top: return overlapsHorizontally(w, s) && abs(s.minY - w.maxY) <= tol
        }
    }

    // MARK: - Geteilter Bildschirm: Naht in festen Stufen (Michael, 08.10.)

    /// Stellen der Naht in Rasterspalten (quer, von 24) bzw. -zeilen (hochkant, von 24):
    /// ⅓ · ⅜ · ½ · ⅝ · ⅔.
    static let seamStops = [8, 9, 12, 15, 16]

    /// Nächste Stufe links (-1) bzw. rechts (+1) der aktuellen Naht. `current` in Zellen,
    /// darf krumm sein (von Hand gezogen). nil am Ende der Stufen.
    static func nextSeamStop(current: CGFloat, direction: Int) -> Int? {
        let eps: CGFloat = 0.25
        return direction > 0
            ? seamStops.first { CGFloat($0) > current + eps }
            : seamStops.last { CGFloat($0) < current - eps }
    }

    /// Beide Hälften eines geteilten Bildschirms bei Naht `cells` (Zellen von 24).
    /// Quer: links/rechts, hochkant: oben/unten.
    static func splitFrames(at cells: Int, in visible: CGRect, _ o: Orientation, gap: CGFloat) -> (first: CGRect, second: CGRect) {
        let n = 24
        if o == .landscape {
            return (rect(for: Cells(0, 0, cells, 12), in: visible, .landscape, gap: gap),
                    rect(for: Cells(cells, 0, n - cells, 12), in: visible, .landscape, gap: gap))
        }
        return (rect(for: Cells(0, 0, 12, cells), in: visible, .portrait, gap: gap),
                rect(for: Cells(0, cells, 12, n - cells), in: visible, .portrait, gap: gap))
    }

    // MARK: - Nur sichtbare Nachbarn (Michael, 08.10.)

    /// Der Streifen eines Nachbarn an der Kante zum führenden Fenster: Dort sieht man,
    /// ob er wirklich an die Naht grenzt. Gleichseitig gestapelte Fenster: ganzer Rahmen.
    static func contactStrip(of w: CGRect, to s: CGRect, gap: CGFloat) -> CGRect {
        let tol = gap + linkTolerance, depth: CGFloat = 20
        let yLo = max(w.minY, s.minY), yHi = min(w.maxY, s.maxY)
        let xLo = max(w.minX, s.minX), xHi = min(w.maxX, s.maxX)
        if overlapsVertically(w, s), abs(w.minX - s.maxX) <= tol {        // rechts daneben
            return CGRect(x: w.minX, y: yLo, width: min(depth, w.width), height: yHi - yLo)
        }
        if overlapsVertically(w, s), abs(s.minX - w.maxX) <= tol {        // links daneben
            return CGRect(x: w.maxX - min(depth, w.width), y: yLo, width: min(depth, w.width), height: yHi - yLo)
        }
        if overlapsHorizontally(w, s), abs(w.minY - s.maxY) <= tol {      // darunter
            return CGRect(x: xLo, y: w.minY, width: xHi - xLo, height: min(depth, w.height))
        }
        if overlapsHorizontally(w, s), abs(s.minY - w.maxY) <= tol {      // darüber
            return CGRect(x: xLo, y: w.maxY - min(depth, w.height), width: xHi - xLo, height: min(depth, w.height))
        }
        return w
    }

    /// Verdeckt, wenn ein einzelnes Fenster davor den Kontaktstreifen ganz enthält.
    /// (Bewusst einfach: Teilabdeckungen durch mehrere Fenster zählen als sichtbar.)
    static func isHidden(_ strip: CGRect, by inFront: [CGRect]) -> Bool {
        inFront.contains { $0.insetBy(dx: -1, dy: -1).contains(strip) }
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
