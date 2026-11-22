import AppKit
import Observation
import SwiftUI

/// Kürzel-Blatt (docs/SECURE-DESIGN.md E24c): Panel nur zum Ansehen. Nimmt weder Fokus noch Mausereignisse,
/// hat keine Schaltflächen und lädt nichts nach. Alle Texte aus fremden Menüs gehen als `Text(verbatim:)`
/// hinein, nie als Markdown oder Link. Der Inhalt lebt nur im Speicher, bis das Blatt wieder verschwindet.
@MainActor
final class ShortcutSheet {

    static let columnWidth: CGFloat = 300
    static let rowHeight: CGFloat = 20
    static let padding: CGFloat = 18
    static let headerHeight: CGFloat = 30

    private let model = ShortcutSheetModel()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }

    /// Zeigt das Blatt mittig auf `screen`. `app` ist der Name aus dem System (nicht aus dem Menü).
    func show(app: String, sections: [MenuSection], truncated: Bool, on screen: Screens.Info) {
        let visible = screen.visible
        let maxWidth = visible.width * 0.95
        let maxHeight = visible.height * 0.85
        let maxColumns = max(Int((maxWidth - 2 * Self.padding) / Self.columnWidth), 1)
        let rows = Int((maxHeight - 2 * Self.padding - Self.headerHeight) / Self.rowHeight)
        let layout = ShortcutSheetLayout.columns(sections, rowsPerColumn: rows, maxColumns: maxColumns)
        guard !layout.columns.isEmpty else { return }
        model.app = app
        model.columns = layout.columns
        model.truncated = truncated || layout.truncated

        let tallest = layout.columns.map(\.count).max() ?? 0
        let size = CGSize(
            width: CGFloat(layout.columns.count) * Self.columnWidth + 2 * Self.padding,
            height: Self.headerHeight + CGFloat(tallest + (model.truncated ? 1 : 0)) * Self.rowHeight + 2 * Self.padding)
        let rect = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        let p = panel ?? makePanel()
        panel = p
        p.setFrame(Geometry.toAppKit(rect, primaryHeight: Screens.primaryHeight), display: true)
        p.orderFrontRegardless()
    }

    /// Sofort weg und den Inhalt vergessen (E24b: nichts bleibt im Speicher, wenn das Blatt zu ist).
    func hide() {
        panel?.orderOut(nil)
        model.columns = []
        model.app = ""
        model.truncated = false
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: ShortcutSheetView(model: model))
        return p
    }
}

@MainActor
@Observable
final class ShortcutSheetModel {
    var app = ""
    var columns: [[SheetRow]] = []
    var truncated = false
}

private struct ShortcutSheetView: View {
    let model: ShortcutSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.app)
                .font(.system(size: 14, weight: .semibold))
                .frame(height: ShortcutSheet.headerHeight, alignment: .topLeading)
            HStack(alignment: .top, spacing: 0) {
                // Über Kopien laufen, nie per Index zurück ins Modell: `hide()` leert es, während die Ansicht
                // noch einmal gerechnet wird (Absturz „Index out of range“ am 22.11., Testversion).
                ForEach(Array(model.columns.enumerated()), id: \.offset) { _, rows in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                    .padding(.trailing, 16)
                    .frame(width: ShortcutSheet.columnWidth, alignment: .topLeading)
                }
            }
            if model.truncated {
                Text(verbatim: "…")
                    .foregroundStyle(.secondary)
                    .frame(height: ShortcutSheet.rowHeight, alignment: .leading)
            }
        }
        .padding(ShortcutSheet.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func rowView(_ row: SheetRow) -> some View {
        switch row {
        case .header(let name):
            Text(verbatim: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: ShortcutSheet.rowHeight, alignment: .bottomLeading)
        case .item(let shortcut):
            HStack(spacing: 8) {
                Text(verbatim: shortcut.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(verbatim: shortcut.keys)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 12))
            .frame(height: ShortcutSheet.rowHeight)
        }
    }
}
