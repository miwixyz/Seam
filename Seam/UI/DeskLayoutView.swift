import SwiftUI

/// Fenster „Layout bearbeiten“ (E17, Michael 19.10.: „Was ist, wenn ich das Layout ändern möchte?“).
/// Je App eine Zeile: Schreibtisch wählen oder App herausnehmen. Größen ändert man durch
/// Anordnen + „Speichern“ im Seam-Menü.
struct DeskLayoutView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs

    @State private var combination = ""
    @State private var desks: [SpaceInfo] = []
    /// Namen und Symbole einmal beim Öffnen (code-audit 19.10.: vorher je Zeile bei jedem Neuzeichnen
    /// eine LaunchServices-Abfrage).
    @State private var names: [String: String] = [:]
    @State private var icons: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            if let layout = prefs.deskLayouts[combination], !layout.entries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(layout.entries, id: \.bundleID) { entry in
                        row(entry)
                        if entry.bundleID != layout.entries.last?.bundleID {
                            Rectangle().fill(FamilyTheme.cardStroke).frame(height: 0.8)
                        }
                    }
                }
                .padding(.horizontal, FamilyTheme.Space.m)
                .familyCard(radius: FamilyTheme.Radius.tile)
                Text("Größen änderst du, indem du die Fenster anordnest und im Seam-Menü „Speichern“ wählst.")
                    .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary)
                HStack {
                    Button("Jetzige Anordnung übernehmen") { engine.saveDeskLayout() }
                        .buttonStyle(CardButtonStyle())
                    Spacer()
                    Button("Layout löschen", role: .destructive) {
                        prefs.saveDeskLayout(DeskLayout(entries: []), for: combination)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            } else {
                Label("Für diese Bildschirme ist noch kein Layout gespeichert. Ordne deine Fenster an und wähle im Seam-Menü „Speichern“.",
                      systemImage: "info.circle")
                    .font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            engine.spaces.refresh()
            combination = DeskLayouts.liveScreens().combinationKey
            desks = engine.spaces.spaces.filter { !$0.isFullScreen }
            for entry in prefs.deskLayouts[combination]?.entries ?? [] {
                names[entry.bundleID] = DeskLayouts.appName(entry.bundleID)
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) {
                    icons[entry.bundleID] = NSWorkspace.shared.icon(forFile: url.path)
                }
            }
        }
    }

    private func row(_ entry: DeskLayoutEntry) -> some View {
        HStack(spacing: FamilyTheme.Space.s) {
            appIcon(entry.bundleID).frame(width: 20, height: 20)
            Text(appName(entry.bundleID)).lineLimit(1)
            Spacer(minLength: FamilyTheme.Space.m)
            Picker("Schreibtisch", selection: Binding(
                get: { entry.desk },
                set: { prefs.setDesk($0, for: entry.bundleID, in: combination) }
            )) {
                ForEach(choices(including: entry.desk), id: \.self) { ref in
                    Text(choiceTitle(ref)).tag(ref)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button {
                prefs.removeFromLayout(entry.bundleID, in: combination)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(FamilyTheme.textSecondary)
                .help("Aus dem Layout nehmen – Seam lässt diese App dann in Ruhe")
                .accessibilityLabel("\(appName(entry.bundleID)) aus dem Layout nehmen")
        }
        .frame(minHeight: 36)
    }

    /// Alle jetzigen Schreibtische als Ziel, plus der gespeicherte, falls es ihn gerade nicht gibt.
    private func choices(including current: DeskRef) -> [DeskRef] {
        var refs = desks.map { DeskRef(name: prefs.spaceNames[$0.key], display: $0.display, number: $0.number) }
        if !refs.contains(current) { refs.append(current) }
        return refs
    }

    private func choiceTitle(_ ref: DeskRef) -> String {
        let displays = desks.map(\.display).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let screen = displays.count > 1 ? " · Bildschirm \((displays.firstIndex(of: ref.display) ?? displays.count) + 1)" : ""
        return (ref.name ?? "Schreibtisch \(ref.number)") + screen
    }

    private func appName(_ id: String) -> String { names[id] ?? id }

    @ViewBuilder
    private func appIcon(_ id: String) -> some View {
        if let icon = icons[id] {
            Image(nsImage: icon).resizable()
        } else {
            Image(systemName: "app.dashed").foregroundStyle(FamilyTheme.textSecondary)
        }
    }
}

/// Hülle für Szene und Vorschau (Muster wie `DimSettingsWindow`).
struct DeskLayoutWindow: View {
    var body: some View {
        ScrollView {
            DeskLayoutView().padding(FamilyTheme.Space.l)
        }
        .frame(width: 480, height: 560)
        .familyBackground()
    }
}
