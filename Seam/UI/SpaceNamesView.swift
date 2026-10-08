import SwiftUI

/// „Spaces benennen“: ein Textfeld je Schreibtisch, in Mission-Control-Reihenfolge (E14).
/// Gespeichert wird bei jeder Eingabe; leer = Standardname.
struct SpaceNamesView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let spaces = engine.spaces.spaces
        let displays = spaces.map(\.display).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        VStack(alignment: .leading, spacing: 12) {
            if spaces.isEmpty {
                Text("macOS gibt die Liste der Spaces gerade nicht heraus. Die Namen bleiben gespeichert.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Der Name des aktuellen Space steht neben dem Seam-Symbol in der Menüleiste. Leer lassen = Standardname.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(displays, id: \.self) { display in
                    if displays.count > 1 {
                        Text("Bildschirm \((displays.firstIndex(of: display) ?? 0) + 1)").font(.headline)
                    }
                    ForEach(spaces.filter { $0.display == display }) { space in
                        row(space)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ space: SpaceInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: space.isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(space.isCurrent ? Color.accentColor : Color.secondary)
                .accessibilityLabel(space.isCurrent ? "Aktueller Space" : "")
            if space.isFullScreen {
                Text("Vollbild-App").foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("\(space.number).").monospacedDigit().frame(width: 22, alignment: .trailing)
                TextField("Schreibtisch \(space.number)", text: Binding(
                    get: { prefs.spaceNames[space.key] ?? "" },
                    set: { prefs.setSpaceName($0, for: space.key) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
