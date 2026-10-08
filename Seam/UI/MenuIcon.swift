import AppKit

/// Piktogramme fürs Menü (Michael, 08.10.: „Icons neben den Kürzeln“).
/// Befehle mit Zielfläche: kleiner Bildschirm, die Fläche gefüllt — aus denselben
/// Rasterzellen gezeichnet, die Seam setzt, also nie im Widerspruch zum Verhalten.
/// Übrige Befehle: Systemsymbole. Vorlagenbilder, passen sich hell/dunkel an.
@MainActor
enum MenuIcon {

    private static var cache: [String: NSImage] = [:]

    static func image(_ spec: CommandSpec, _ o: Orientation) -> NSImage? {
        if let cells = spec.target { return screen(cells, o) }
        let name: String
        switch spec.command {
        case .nextDisplay: name = "arrow.right.to.line"
        case .previousDisplay: name = "arrow.left.to.line"
        case .center: name = "inset.filled.center.rectangle"
        case .restore: name = "arrow.uturn.backward"
        case .split: name = o == .landscape ? "rectangle.split.2x1" : "rectangle.split.1x2"
        case .seamLeft: name = o == .landscape ? "arrow.left" : "arrow.up"
        case .seamRight: name = o == .landscape ? "arrow.right" : "arrow.down"
        default: return nil
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private static func screen(_ c: Cells, _ o: Orientation) -> NSImage {
        let key = "\(o)-\(c.x)-\(c.y)-\(c.w)-\(c.h)"
        if let img = cache[key] { return img }
        let canvas = NSSize(width: 20, height: 14)
        let img = NSImage(size: canvas, flipped: true) { _ in
            let outer = o == .landscape
                ? NSRect(x: 1, y: 1.5, width: 18, height: 11)
                : NSRect(x: 5.5, y: 0.5, width: 9, height: 13)
            let frame = NSBezierPath(roundedRect: outer.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            frame.lineWidth = 1
            NSColor.black.setStroke()
            frame.stroke()
            let inner = outer.insetBy(dx: 1.75, dy: 1.75)
            let cw = inner.width / CGFloat(o.columns), ch = inner.height / CGFloat(o.rows)
            let fill = NSRect(x: inner.minX + CGFloat(c.x) * cw, y: inner.minY + CGFloat(c.y) * ch,
                              width: CGFloat(c.w) * cw, height: CGFloat(c.h) * ch)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        img.isTemplate = true
        cache[key] = img
        return img
    }
}
