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

    private struct Entry { let pid: pid_t; let bounds: CGRect; let regular: Bool }

    static func neighbors(of leading: AXWindow, frame: CGRect, gap: CGFloat) -> [(AXWindow, CGRect)] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        // Von vorn nach hinten. Überlagerungen wie HazeOver (keine normale App) decken nichts ab.
        var entries: [Entry] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { continue }
            let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            entries.append(Entry(pid: pid, bounds: bounds, regular: regular))
        }

        var out: [(AXWindow, CGRect)] = []
        for (z, e) in entries.enumerated() where e.regular && Geometry.isLinkCandidate(e.bounds, to: frame, gap: gap) {
            let inFront = entries.prefix(z)
                // Das gezogene Fenster selbst nie als Abdeckung zählen. Nicht über exakte
                // Gleichheit: Beim ersten Größeziehen hat es sich schon bewegt.
                .filter { $0.regular && !Self.mostlyOverlaps($0.bounds, frame) }
                .map(\.bounds)
            let strip = Geometry.contactStrip(of: e.bounds, to: frame, gap: gap)
            guard !Geometry.isHidden(strip, by: inFront) else { continue }
            if let w = AXAccess.windows(of: e.pid).first(where: { win in
                guard let f = win.frame else { return false }
                return Self.same(f, e.bounds)
            }), w != leading, !out.contains(where: { $0.0 == w }) {
                out.append((w, e.bounds))
            }
        }
        return out
    }

    /// Für Kürzel (Michael, 08.10.: „Kürzel setzen den Nachbarn mit“): je innerer Kante
    /// der Zielfläche das VORDERSTE sichtbare Fenster auf der anderen Seite, das ihr
    /// zugewandt ist, auch mit Lücke oder Überlappung, und sein neuer Rahmen.
    static func complements(target t: CGRect, visible: CGRect, moving: AXWindow, movingFrame: CGRect,
                            gap: CGFloat) -> [(AXWindow, CGRect)] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var entries: [Entry] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b),
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  !same(bounds, movingFrame),                    // das gesetzte Fenster selbst
                  bounds.intersects(visible) else { continue }
            entries.append(Entry(pid: pid, bounds: bounds, regular: true))
        }
        var out: [(AXWindow, CGRect)] = []
        for edge in Geometry.innerEdges(of: t, in: visible, gap: gap) {
            // Von vorn nach hinten: das erste passende Fenster gewinnt.
            for e in entries {
                guard let r = Geometry.complement(of: e.bounds, target: t, edge: edge, gap: gap),
                      let w = AXAccess.windows(of: e.pid).first(where: { $0.frame.map { same($0, e.bounds) } ?? false }),
                      w != moving, !out.contains(where: { $0.0 == w }) else { continue }
                out.append((w, r))
                break
            }
        }
        return out
    }

    private static func mostlyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        guard !i.isNull, b.width > 0, b.height > 0 else { return false }
        return i.width * i.height >= 0.8 * b.width * b.height
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
