import SwiftUI

/// Einstellungen als eigenes Fenster (0.4). Vorher Untermenü „Einstellungen“ im Systemmenü.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.openWindow) private var openWindow
    /// Autostart-Zustand: von macOS gelesen, nicht gespiegelt (siehe LoginItem). Code-Audit 09.10.
    /// (C3): vorher wurde ein Fehler verworfen und „Freigabe nötig“ als „aus“ gezeigt.
    @State private var login = LoginItem.state
    @State private var loginError: String?

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section("Fenster") {
                Toggle("Fenster an gemeinsamen Kanten mitziehen", isOn: $prefs.linkEdges)
                Toggle("Andocken per Ziehen an den Bildschirmrand", isOn: $prefs.dragSnap)
                Toggle("Beim Herausziehen ursprüngliche Größe", isOn: $prefs.restoreOnDragOut)
                Toggle("Geteilte Fenster bleiben zusammen", isOn: $prefs.keepPairs)
                    .onChange(of: prefs.keepPairs) { engine.applyPairSetting() }
                Picker("Abstand zwischen Fenstern", selection: $prefs.gap) {
                    ForEach(Preferences.gapChoices, id: \.self) { Text($0 == 0 ? "Kein Abstand" : "\($0) pt").tag($0) }
                }
            }
            Section("Tastenkürzel") {
                Toggle("Tastenkürzel", isOn: $prefs.shortcuts)
                    .onChange(of: prefs.shortcuts) { engine.applyShortcutSetting() }
                if !engine.failedShortcuts.isEmpty {
                    Label("\(engine.failedShortcuts.count) Kürzel belegt, läuft Magnet noch?", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(FamilyTheme.warning)
                }
            }
            Section("Hintergrund abdunkeln") {
                Toggle("Alle Fenster außer dem aktiven abdunkeln", isOn: $prefs.dimEnabled)
                    .onChange(of: prefs.dimEnabled) { engine.applyDimSetting() }
                Picker("Stärke", selection: $prefs.dimStrength) {
                    Text("Leicht").tag(20)
                    Text("Mittel").tag(35)
                    Text("Stark").tag(50)
                }
                .pickerStyle(.segmented)
                .disabled(!prefs.dimEnabled)
                .onChange(of: prefs.dimStrength) { engine.applyDimStrength() }
            }
            if engine.spaces.available {
                Section("Spaces") {
                    Toggle("Space-Namen in der Menüleiste", isOn: $prefs.showSpaceName)
                    Toggle("Symbol ausblenden, wenn ein Space-Name steht", isOn: $prefs.hideIconWithSpaceName)
                        .disabled(!prefs.showSpaceName)
                    Button("Spaces benennen …") {
                        engine.spaces.refresh()
                        openWindow(id: "spaces")
                    }
                }
            }
            Section("Allgemein") {
                Toggle("Bei Anmeldung starten", isOn: Binding(
                    get: { login == .on || login == .needsApproval },
                    set: { on in
                        loginError = LoginItem.set(on)?.localizedDescription
                        login = LoginItem.state
                    }
                ))
                .disabled(login == .unavailable)
                if login == .needsApproval {
                    HStack {
                        Label("macOS wartet auf deine Freigabe", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(FamilyTheme.warning)
                        Spacer()
                        Button("Freigeben …") { LoginItem.openSystemSettings() }
                    }
                }
                if login == .unavailable {
                    Label("Nur möglich, wenn Seam im Ordner Programme liegt", systemImage: "info.circle")
                        .foregroundStyle(FamilyTheme.textSecondary)
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle").foregroundStyle(FamilyTheme.warning)
                }
                if let updater = engine.updater {
                    Button("Nach Updates suchen …") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }
        .formStyle(.grouped)
        .font(FamilyTheme.font(.body))
        .tint(FamilyTheme.accent)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { login = LoginItem.state }
    }
}
