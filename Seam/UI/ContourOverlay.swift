import AppKit

/// Konturen für langsame Nachbarn: Während des Ziehens zeigt Seam, wo ein Fenster
/// landen wird, statt es live umzubauen (SlowApps). Wie SnapOverlay: randlos, nimmt
/// keine Maus an, wird nie aktiv. Familien-Akzent „Iris“.
@MainActor
final class ContourOverlay {

    private var panels: [Int: NSPanel] = [:]

    private static let accent = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua]) == .darkAqua
            ? NSColor(red: 0x98 / 255, green: 0xA9 / 255, blue: 0xE1 / 255, alpha: 1)
            : NSColor(red: 0x3E / 255, green: 0x53 / 255, blue: 0x98 / 255, alpha: 1)
    }

    /// `rects` in Bedienungshilfen-Koordinaten, je Nachbar-Kennung.
    func update(_ rects: [Int: CGRect]) {
        for (id, panel) in panels where rects[id] == nil {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for (id, r) in rects {
            let p = panels[id] ?? make()
            panels[id] = p
            p.setFrame(Geometry.toAppKit(r, primaryHeight: Screens.primaryHeight), display: true)
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                p.contentView?.layer?.backgroundColor = Self.accent.withAlphaComponent(0.10).cgColor
                p.contentView?.layer?.borderColor = Self.accent.withAlphaComponent(0.85).cgColor
            }
            p.orderFrontRegardless()
        }
    }

    func hideAll() { update([:]) }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.hidesOnDeactivate = false
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.borderWidth = 3
        p.contentView = v
        return p
    }
}
