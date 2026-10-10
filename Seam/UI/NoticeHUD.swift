import AppKit

/// Kurzes Hinweisschild an der Naht (MinimumNotice). Wie `SnapOverlay`: randlos, nimmt keine
/// Mausereignisse an, wird nie aktiv, liegt auf allen Spaces. Glas wie das Systemmaterial
/// (`.hudWindow`), hell/dunkel folgt dem System. Verschwindet nach `duration` von selbst.
@MainActor
final class NoticeHUD {

    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideTask: Task<Void, Never>?
    private static let duration: Duration = .seconds(5)
    private static let maxTextWidth: CGFloat = 340
    private static let padding = NSSize(width: 16, height: 12)

    /// `anchor` in Bedienungshilfen-Koordinaten, Schild mittig darauf, im sichtbaren Bereich gehalten.
    func show(_ text: String, at anchor: CGPoint, within visible: CGRect) {
        let p = panel ?? makePanel()
        panel = p
        guard let label else { return }
        label.stringValue = text
        label.preferredMaxLayoutWidth = Self.maxTextWidth
        let fit = label.sizeThatFits(NSSize(width: Self.maxTextWidth, height: .greatestFiniteMagnitude))
        let size = NSSize(width: ceil(fit.width) + 2 * Self.padding.width, height: ceil(fit.height) + 2 * Self.padding.height)
        let rect = Geometry.clamp(CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                                         width: size.width, height: size.height), to: visible)
        p.setFrame(Geometry.toAppKit(rect, primaryHeight: Screens.primaryHeight), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Inzwischen neu gezeigt? Dann stehen lassen.
                if self?.panel?.alphaValue == 0 { self?.panel?.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.hidesOnDeactivate = false

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.masksToBounds = true

        let l = NSTextField(wrappingLabelWithString: "")
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: Self.padding.width),
            l.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -Self.padding.width),
            l.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
        ])
        label = l
        p.contentView = glass
        return p
    }
}
