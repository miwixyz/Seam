import AppKit
import SwiftUI

/// Gemeinsamer Zustand für Umschalter und Dock-Vorschau (E21).
@MainActor
@Observable
final class PreviewModel {
    var windows: [CatalogWindow] = []
    var images: [CGWindowID: NSImage] = [:]
    var selection = 0
    var size: PreviewSize = .normal
    var columns = 1
    /// Dock-Vorschau: eine Zeile, keine Markierung beim Öffnen.
    var showsSelection = true
    @ObservationIgnored var onHover: ((Int) -> Void)?
    @ObservationIgnored var onClick: ((Int) -> Void)?

    func reset(_ list: [CatalogWindow], size: PreviewSize, columns: Int, selection: Int) {
        windows = list
        self.size = size
        self.columns = max(1, columns)
        self.selection = selection
        images = list.reduce(into: [:]) { r, w in r[w.id] = WindowCatalog.cachedImage(w.id) }
    }
}

/// Randloses Schwebefenster. Nimmt Tastatur nur an, wenn es selbst Fokus hat (E21d) —
/// es gibt keine Beobachtung außerhalb dieses Fensters.
final class PreviewPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    var acceptsKey = false

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { onKey?(event) }

    /// E21h: randlos, Seam wird nicht aktiv, auf jedem Space, nicht im eigenen Umschalter.
    static func make(model: PreviewModel) -> PreviewPanel {
        let p = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.masksToBounds = true
        let host = FirstClickHostingView(rootView: WindowGridView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        p.contentView = glass
        return p
    }

    /// Größe, die der Inhalt braucht.
    var fittingSize: NSSize {
        (contentView?.subviews.first as? NSHostingView<WindowGridView>)?.fittingSize ?? .zero
    }
}

/// Erster Klick zählt, auch wenn das Fenster nicht vorn ist (Dock-Vorschau).
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct WindowGridView: View {
    let model: PreviewModel
    nonisolated static let spacing: CGFloat = 6
    nonisolated static let padding: CGFloat = 12

    var body: some View {
        let rows = stride(from: 0, to: model.windows.count, by: model.columns).map { start in
            Array(model.windows.indices[start..<min(start + model.columns, model.windows.count)])
        }
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(rows, id: \.first) { row in
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(row, id: \.self) { i in
                        let w = model.windows[i]
                        WindowTile(window: w, image: model.images[w.id], width: model.size.tileWidth,
                                   selected: model.showsSelection && i == model.selection)
                            .contentShape(Rectangle())
                            .onHover { inside in if inside { model.onHover?(i) } }
                            .onTapGesture { model.onClick?(i) }
                    }
                }
            }
        }
        .padding(Self.padding)
        .fixedSize()
    }
}

/// Eine Kachel: Vorschaubild (oder großes App-Symbol), darunter Symbol + Titel.
/// Titel ist fremder Text: nur `Text(verbatim:)` (E21c).
struct WindowTile: View {
    let window: CatalogWindow
    let image: NSImage?
    let width: CGFloat
    let selected: Bool

    var body: some View {
        let app = window.app
        let icon = app?.icon ?? NSWorkspace.shared.icon(for: .application)
        let name = WindowCatalog.sanitize(app?.localizedName)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: width * 0.3, height: width * 0.3)
                }
                if !window.onScreen {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                        .help("Minimiert oder auf einem anderen Schreibtisch")
                }
            }
            .frame(width: width, height: (width * 0.62).rounded())
            HStack(spacing: 6) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(verbatim: window.title.isEmpty ? name : window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: width, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.32) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
