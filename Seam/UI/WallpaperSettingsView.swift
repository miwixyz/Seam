import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fenster „Hintergrund“ (0.9, docs/SECURE-DESIGN.md E18): Datei wählen, Gesamtbild oder je
/// Bildschirm, welche Bildschirme. Michael, 10.11.: „Wallpaper für alle meine Monitor als Gesamtbild“.
/// Jede Änderung wirkt sofort (`applyWallpaper`).
struct WallpaperSettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @State private var monitors: [DimSettingsView.Monitor] = []

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            fileCard
            layoutCard
            screensCard
            statusNote
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
            SpaceReader.displayIdentifier(of: s).map { DimSettingsView.Monitor(id: $0, name: s.localizedName) }
        }
    }

    // MARK: - Datei

    private var fileCard: some View {
        @Bindable var prefs = prefs
        return card("Datei") {
            row("Eigener Hintergrund") {
                Toggle("Eigener Hintergrund", isOn: Binding(
                    get: { prefs.wallpaperEnabled },
                    set: { prefs.wallpaperEnabled = $0; engine.applyWallpaper() }))
                    .labelsHidden()
                    .toggleStyle(FamilySwitchStyle())
            }
            divider
            fileRow(label: "Hell", symbol: "sun.max", name: fileName(prefs.wallpaperPath) ?? "Keine Datei gewählt", dark: false)
            divider
            fileRow(label: "Dunkel", symbol: "moon", name: fileName(prefs.wallpaperPathDark) ?? "wie hell", dark: true)
            note("Video (mp4, mov) läuft ohne Ton in Endlosschleife hinter den Schreibtisch-Symbolen. "
                 + "Ein Bild setzt Seam als macOS-Hintergrund. Bei einem Video wird das erste Bild "
                 + "ebenfalls als macOS-Hintergrund gesetzt (Mission Control, Sperrbildschirm). "
                 + "Schaltet macOS zwischen hell und dunkel um, wechselt Seam die Datei mit; ohne "
                 + "eigene dunkle Datei bleibt die helle. Ausschalten beendet das Video, das macOS-Bild bleibt.",
                 symbol: "info.circle")
        }
    }

    /// Eine Zeile je Darstellung: Symbol, Dateiname, wählen (und bei dunkel: entfernen).
    private func fileRow(label: String, symbol: String, name: String, dark: Bool) -> some View {
        HStack(spacing: FamilyTheme.Space.s) {
            Label(label, systemImage: symbol)
                .frame(width: 84, alignment: .leading)
            Text(verbatim: name)
                .foregroundStyle(FamilyTheme.textSecondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: FamilyTheme.Space.s)
            if dark, prefs.wallpaperPathDark != nil {
                Button {
                    prefs.clearWallpaperPathDark()
                    engine.applyWallpaper()
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.familyGlass(.circle, size: 26))
                    .help("Dunkle Datei entfernen, dann gilt auch im Dunkeln die helle")
                    .accessibilityLabel("Dunkle Datei entfernen")
            }
            Button("Wählen …") { choose(dark: dark) }
                .buttonStyle(.familyGlass(.capsule, size: 26))
                .help(dark ? "Video oder Bild für die dunkle Darstellung wählen"
                           : "Video oder Bild für die helle Darstellung wählen")
        }
        .frame(minHeight: 34)
    }

    private func fileName(_ path: String?) -> String? {
        path.map { ($0 as NSString).lastPathComponent }
    }

    /// E18a: Der Pfad kommt nur aus diesem Dialog.
    private func choose(dark: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = dark ? "Video oder Bild für die dunkle Darstellung wählen"
                             : "Video oder Bild für die helle Darstellung wählen"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.setWallpaperPath(url.path, dark: dark)
        prefs.wallpaperEnabled = true
        engine.applyWallpaper()
    }

    // MARK: - Verteilung

    private var layoutCard: some View {
        card("Verteilung") {
            Picker("Verteilung", selection: Binding(
                get: { prefs.wallpaperLayout },
                set: { prefs.wallpaperLayout = $0; engine.applyWallpaper() })) {
                Text("Ein Bild über alle").tag(WallpaperLayout.span)
                Text("Jeder Bildschirm ganz").tag(WallpaperLayout.each)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, FamilyTheme.Space.xs)
            note(prefs.wallpaperLayout == .span
                 ? "Verteilt nach echter Größe: Linien laufen über die Kante gerade weiter, auch wenn die "
                   + "Bildschirme verschieden fein sind. Lage wie in Systemeinstellungen → Displays angeordnet; "
                   + "Rahmen und Lücken zwischen den Monitoren kennt macOS nicht."
                 : "Jeder Bildschirm zeigt das ganze Bild, füllend zugeschnitten.",
                 symbol: "rectangle.3.group")
        }
    }

    // MARK: - Bildschirme

    private var screensCard: some View {
        card("Bildschirme") {
            ForEach(Array(monitors.enumerated()), id: \.element.id) { i, m in
                if i > 0 { divider }
                row(m.name) {
                    Toggle("Hintergrund auf \(m.name)", isOn: Binding(
                        get: { !prefs.wallpaperOffScreens.contains(m.id) },
                        set: { prefs.setWallpaperScreen($0, id: m.id); engine.applyWallpaper() }))
                        .labelsHidden()
                        .toggleStyle(FamilySwitchStyle())
                }
            }
        }
    }

    // MARK: - Status (nie stumm scheitern)

    @ViewBuilder private var statusNote: some View {
        switch engine.wallpaper.status {
        case .off:
            note("Aus.", symbol: "pause.circle")
        case .loading:
            note("Lädt …", symbol: "hourglass")
        case .video(let n):
            note("Video läuft auf \(n) \(n == 1 ? "Bildschirm" : "Bildschirmen").", symbol: "play.circle")
        case .image(let n):
            note("Bild gesetzt auf \(n) \(n == 1 ? "Bildschirm" : "Bildschirmen").", symbol: "checkmark.circle")
        case .problem(let msg):
            note(msg, symbol: "exclamationmark.triangle")
        }
    }

    // MARK: - Bausteine (wie im Fenster „Abdunkeln“)

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
            Text(verbatim: title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: FamilyTheme.Space.m)
            control()
        }
        .frame(minHeight: 34)
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

/// Inhalt des Fensters „Hintergrund“ samt Rand und Hintergrund (wie `DimSettingsWindow`).
struct WallpaperSettingsWindow: View {
    static let size = CGSize(width: 500, height: 560)

    var body: some View {
        ScrollView {
            WallpaperSettingsView().padding(FamilyTheme.Space.l)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .familyBackground()
    }
}
