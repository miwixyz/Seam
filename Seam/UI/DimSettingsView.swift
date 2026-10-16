import AppKit
import SwiftUI

/// Fenster „Abdunkeln“ (0.6, docs/SECURE-DESIGN.md E13): je Bildschirm Art und Stärke, Apps, die
/// nie abgedunkelt werden, Spaces ohne Abdunkeln. Michael, 16.10.: „für unterschiedliche Monitore
/// wählen“, dazu Apps, Spaces, Stärke je Monitor. Jede Änderung wirkt sofort (`applyDimDetails`).
struct DimSettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @State private var monitors: [Monitor] = []
    @State private var apps: [AppChoice] = []

    /// Angeschlossener Bildschirm: Kennung (UUID, gespeichert) und Name (nur angezeigt).
    struct Monitor: Identifiable, Equatable {
        let id: String
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            if !prefs.dimEnabled {
                note("Hintergrund abdunkeln ist gerade aus. Einschalten mit dem Halbkreis-Knopf im Seam-Fenster.",
                     symbol: "info.circle")
            }
            screensCard
            appsCard
            if engine.spaces.available { spacesCard }
        }
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        monitors = NSScreen.screens.compactMap { s in
            SpaceReader.displayIdentifier(of: s).map { Monitor(id: $0, name: s.localizedName) }
        }
        apps = AppChoice.running()
        engine.spaces.refresh()
    }

    // MARK: - Bildschirme

    private var screensCard: some View {
        card("Bildschirme") {
            ForEach(Array(monitors.enumerated()), id: \.element.id) { i, m in
                if i > 0 { divider }
                Text(verbatim: m.name)
                    .font(FamilyTheme.font(.callout, weight: .semibold))
                    .padding(.vertical, FamilyTheme.Space.s)
                // Eigene Zeile: drei Felder mit Beschriftung daneben waren zu breit (Vorschau 16.10.).
                Picker("Abdunkeln auf \(m.name)", selection: Binding(
                    get: { prefs.dimMode(for: m.id) },
                    set: { prefs.setDimMode($0, for: m.id); engine.applyDimDetails() })) {
                    Text("Ganz dunkel").tag(DimScreenMode.dim)
                    Text("Oberstes Fenster hell").tag(DimScreenMode.topBright)
                    Text("Nicht abdunkeln").tag(DimScreenMode.off)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                row("Stärke") {
                    Picker("Stärke", selection: Binding(
                        get: { prefs.dimStrength(for: m.id) },
                        set: { prefs.setDimStrength($0, for: m.id); engine.applyDimDetails() })) {
                        Text("Leicht").tag(20)
                        Text("Mittel").tag(35)
                        Text("Stark").tag(50)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .disabled(prefs.dimMode(for: m.id) == .off)
            }
            note("Das aktive Fenster bleibt immer hell. „Oberstes Fenster hell“ gilt, solange das aktive Fenster auf einem anderen Bildschirm liegt.",
                 symbol: "info.circle")
        }
    }

    // MARK: - Apps

    private var appsCard: some View {
        card("Apps nie abdunkeln") {
            if prefs.dimNeverApps.isEmpty {
                note("Keine. Fenster dieser Apps bleiben hell, auch wenn sie hinten liegen.", symbol: "info.circle")
            }
            ForEach(prefs.dimNeverApps, id: \.self) { id in
                row(appName(id)) {
                    Button {
                        prefs.dimNeverApps.removeAll { $0 == id }
                        engine.applyDimDetails()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .help("Entfernen")
                    .accessibilityLabel("\(appName(id)) entfernen")
                }
                divider
            }
            Menu("App hinzufügen …") {
                ForEach(apps.filter { !prefs.dimNeverApps.contains($0.id) }, id: \.id) { app in
                    Button(app.name) { add(app.id) }
                }
                Divider()
                Button("Andere App …") { if let app = AppChoice.pick() { add(app.id) } }
            }
            .menuStyle(.button)
            .buttonStyle(CardButtonStyle())
            .fixedSize()
            .padding(.vertical, FamilyTheme.Space.s)
            .disabled(prefs.dimNeverApps.count >= Preferences.maxDimApps)
        }
    }

    private func add(_ id: String) {
        prefs.addDimNeverApp(id)
        engine.applyDimDetails()
    }

    private func appName(_ id: String) -> String {
        AppChoice.merged(apps, with: id).first { $0.id == id }?.name ?? id
    }

    // MARK: - Spaces

    private var spacesCard: some View {
        let spaces = engine.spaces.spaces.filter { !$0.isFullScreen }
        let displays = spaces.map(\.display).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return card("Spaces") {
            note("Ausgeschaltet: In diesem Space dunkelt Seam nichts ab.", symbol: "info.circle")
            ForEach(displays, id: \.self) { display in
                if displays.count > 1 {
                    Text(verbatim: monitors.first { $0.id == display }?.name ?? "Bildschirm")
                        .font(FamilyTheme.font(.callout, weight: .semibold))
                        .padding(.top, FamilyTheme.Space.s)
                }
                ForEach(spaces.filter { $0.display == display }) { space in
                    toggleRow(SpaceNames.title(space, prefs.spaceNames), isOn: Binding(
                        get: { !prefs.dimOffSpaces.contains(space.key) },
                        set: { prefs.setSpaceDimmed($0, key: space.key); engine.applyDimDetails() }))
                }
            }
        }
    }

    // MARK: - Bausteine (wie in den Einstellungen)

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(FamilyTheme.font(.headline))
                .padding(.bottom, FamilyTheme.Space.xs)
            content()
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Text(verbatim: title)
            Spacer(minLength: FamilyTheme.Space.m)
            control()
        }
        .frame(minHeight: 34)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(FamilySwitchStyle())
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(FamilyTheme.font(.callout))
            .foregroundStyle(FamilyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, FamilyTheme.Space.xs)
    }

    private var divider: some View {
        Rectangle().fill(FamilyTheme.cardStroke).frame(height: 0.8)
    }
}

/// Inhalt des Fensters „Abdunkeln“ samt Rand und Hintergrund. Von der Szene in `SeamApp` UND von
/// der Vorschau benutzt (Lehre 0.5.3: Vorschau nur über dieselbe Hülle wie die Szene).
struct DimSettingsWindow: View {
    static let size = CGSize(width: 500, height: 620)

    var body: some View {
        ScrollView {
            DimSettingsView().padding(FamilyTheme.Space.l)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .familyBackground()
    }
}
