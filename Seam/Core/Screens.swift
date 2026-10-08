import AppKit

/// Bildschirme in Bedienungshilfen-Koordinaten (Ursprung oben links).
@MainActor
enum Screens {

    struct Info: Equatable {
        /// Ganzer Bildschirm inkl. Menüleiste (für Andocken: man zieht an den echten Rand).
        let frame: CGRect
        /// Ohne Menüleiste und Dock (Zielflächen der Fenster).
        let visible: CGRect
        var orientation: Orientation { .of(visible) }
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func all() -> [Info] {
        let h = primaryHeight
        return NSScreen.screens.map {
            Info(frame: Geometry.toAX($0.frame, primaryHeight: h),
                 visible: Geometry.toAX($0.visibleFrame, primaryHeight: h))
        }
    }

    static func containing(_ p: CGPoint) -> Info? {
        // Rand inklusive: Der Zeiger steht beim Andocken genau auf der letzten Zeile/Spalte.
        all().first { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }
    }

    /// Bildschirm mit der größten Überschneidung (für Tastenkürzel).
    static func best(for r: CGRect) -> Info? {
        all().max { area($0.frame.intersection(r)) < area($1.frame.intersection(r)) }
    }

    /// Reihenfolge für „nächster/vorheriger Bildschirm“: von links nach rechts, dann oben nach unten.
    static func ordered() -> [Info] {
        all().sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// Mauszeiger in Bedienungshilfen-Koordinaten.
    static var mouse: CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x, y: primaryHeight - m.y)
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
