import AppKit

/// Zeigt beim Ziehen die Zielfläche an (Magnet: highlightActivationAreas).
///
/// Ein randloses Fenster, das keine Mausereignisse annimmt und nie aktiv wird.
/// Farbe: Familien-Akzent „Iris“ (App-Familie Design-System), bis Seam einen
/// eigenen Akzent bekommt.
@MainActor
final class SnapOverlay {

    private var panel: NSPanel?
    private var shown: CGRect?

    private static let accent = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua]) == .darkAqua
            ? NSColor(red: 0x98 / 255, green: 0xA9 / 255, blue: 0xE1 / 255, alpha: 1)
            : NSColor(red: 0x3E / 255, green: 0x53 / 255, blue: 0x98 / 255, alpha: 1)
    }

    /// `rect` in Bedienungshilfen-Koordinaten.
    func show(_ rect: CGRect) {
        guard rect != shown else { return }
        shown = rect
        let p = panel ?? makePanel()
        panel = p
        p.setFrame(Geometry.toAppKit(rect, primaryHeight: Screens.primaryHeight), display: true)
        // Farben je Anzeige auflösen: `cgColor` friert die dynamische Farbe sonst
        // im Erscheinungsbild ein, das beim Anlegen galt (Hell/Dunkel-Wechsel).
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            p.contentView?.layer?.backgroundColor = Self.accent.withAlphaComponent(0.18).cgColor
            p.contentView?.layer?.borderColor = Self.accent.withAlphaComponent(0.65).cgColor
        }
        p.orderFrontRegardless()
    }

    func hide() {
        shown = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
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
        v.layer?.cornerRadius = 14
        v.layer?.borderWidth = 2
        p.contentView = v
        return p
    }
}
