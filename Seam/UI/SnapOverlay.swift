import AppKit

/// Zeigt beim Ziehen die Zielfläche an (Magnet: highlightActivationAreas).
///
/// Ein randloses Fenster, das keine Mausereignisse annimmt und nie aktiv wird.
/// Farbe: Seams Akzent Iris aus `FamilyTheme` (Code-Audit 09.10., Q9: vorher dieselben Werte
/// hier ein zweites Mal von Hand). Dynamisch hell/dunkel, belegt in `ThemeTests`.
@MainActor
final class SnapOverlay {

    private var panel: NSPanel?
    private var shown: CGRect?

    private static var accent: NSColor { NSColor(FamilyTheme.accent) }

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
