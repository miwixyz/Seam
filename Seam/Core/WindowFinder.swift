import AppKit

/// Findet die Fenster, die beim Gestenbeginn an einer Kante des führenden
/// Fensters liegen und dort **sichtbar** sind.
///
/// Zweistufig, damit ein Klick nicht jede laufende App abfragt: Erst die
/// Fensterliste des Systems (schnell, von vorn nach hinten sortiert, liefert Lage und
/// Prozess, **keine Titel ohne Bildschirmaufnahme-Freigabe**, die Seam bewusst nicht
/// anfordert), dann nur für die wenigen Kandidaten die Bedienungshilfen.
///
/// **Nur sichtbare Nachbarn** (Michael, 08.10.): Beim Messen zog ein Gmail-Fenster mit,
/// das komplett verdeckt hinter dem eigentlichen Nachbarn an derselben Kante lag.
@MainActor
enum WindowFinder {

    static func neighbors(of leading: AXWindow, frame: CGRect, gap: CGFloat) -> [(AXWindow, CGRect)] {
        // Von vorn nach hinten. Überlagerungen wie HazeOver (keine normale App) decken nichts ab.
        let entries = WindowList.onScreen().map { ($0, WindowList.isRegularApp($0.pid)) }
        var out: [(AXWindow, CGRect)] = []
        for (z, (e, regular)) in entries.enumerated() where regular && Geometry.isLinkCandidate(e.bounds, to: frame, gap: gap) {
            let inFront = entries.prefix(z)
                // Das gezogene Fenster selbst nie als Abdeckung zählen. Nicht über exakte
                // Gleichheit: Beim Loslassen hat es sich gegenüber dem Startrahmen schon bewegt.
                .filter { $0.1 && !Self.mostlyOverlaps($0.0.bounds, frame) }
                .map(\.0.bounds)
            let strip = Geometry.contactStrip(of: e.bounds, to: frame, gap: gap)
            guard !Geometry.isHidden(strip, by: inFront),
                  let w = AXAccess.window(of: e.pid, matching: e.bounds),
                  w != leading, !out.contains(where: { $0.0 == w }) else { continue }
            out.append((w, e.bounds))
        }
        return out
    }

    /// Für Kürzel (Michael, 08.10.: „Kürzel setzen den Nachbarn mit“): je innerer Kante
    /// der Zielfläche das VORDERSTE sichtbare Fenster auf der anderen Seite, das ihr
    /// zugewandt ist, auch mit Lücke oder Überlappung, und sein neuer Rahmen.
    static func complements(target t: CGRect, visible: CGRect, moving: AXWindow, movingFrame: CGRect,
                            gap: CGFloat) -> [(AXWindow, CGRect)] {
        let entries = WindowList.onScreen().filter {
            WindowList.isRegularApp($0.pid)
                && !Geometry.close($0.bounds, movingFrame)          // das gesetzte Fenster selbst
                && $0.bounds.intersects(visible)
        }
        var out: [(AXWindow, CGRect)] = []
        for edge in Geometry.innerEdges(of: t, in: visible, gap: gap) {
            // Von vorn nach hinten: das erste passende Fenster gewinnt.
            for e in entries {
                guard let r = Geometry.complement(of: e.bounds, target: t, edge: edge, gap: gap, visible: visible),
                      let w = AXAccess.window(of: e.pid, matching: e.bounds),
                      w != moving, !out.contains(where: { $0.0 == w }) else { continue }
                // E5: auf den sichtbaren Bereich begrenzen. Ein Nachbar, dessen äußerer Rand
                // außerhalb lag, wird dabei mit eingeholt (rafter-code-review, 08.10.).
                let clamped = r.intersection(visible)
                guard !clamped.isNull, clamped.width >= 80, clamped.height >= 60 else { continue }
                out.append((w, clamped))
                break
            }
        }
        return out
    }

    /// ⌃⌥S: das vorderste andere Fenster auf demselben Bildschirm (also meist das
    /// zuletzt benutzte), als Partner zum Teilen.
    static func nextWindow(after moving: AXWindow, frame: CGRect, on screen: CGRect) -> (AXWindow, CGRect)? {
        for e in WindowList.onScreen() {
            let b = e.bounds
            guard b.width >= 200, b.height >= 150,
                  screen.contains(CGPoint(x: b.midX, y: b.midY)),
                  !Geometry.close(b, frame),
                  WindowList.isRegularApp(e.pid),
                  let w = AXAccess.window(of: e.pid, matching: b),
                  w != moving else { continue }
            return (w, b)
        }
        return nil
    }

    private static func mostlyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        guard !i.isNull, b.width > 0, b.height > 0 else { return false }
        return i.width * i.height >= 0.8 * b.width * b.height
    }
}
