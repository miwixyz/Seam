import SwiftUI

/// Einstellungen als eigenes Fenster (0.4). Vorher Untermenü „Einstellungen“ im Systemmenü.
/// 0.4.2: gleiche Bausteine wie das Seam-Fenster (Verlauf, weiße Karten, Titel in der Karte,
/// Plus Jakarta Sans) statt Apples grauem Formular — Michael: „passt optisch nicht“ (09.10.).
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.openWindow) private var openWindow
    /// Autostart-Zustand: von macOS gelesen, nicht gespiegelt (siehe LoginItem). Code-Audit 09.10.
    /// (C3): vorher wurde ein Fehler verworfen und „Freigabe nötig“ als „aus“ gezeigt.
    @State private var login = LoginItem.state
    @State private var loginError: String?
    @State private var router = LinkRouter.shared
    @State private var linkError: String?

    var body: some View {
        @Bindable var prefs = prefs
        // 0.5: zwei Spalten, mit „Links“ war eine Spalte höher als der MacBook-Bildschirm.
        HStack(alignment: .top, spacing: FamilyTheme.Space.m) {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            card("Fenster") {
                toggleRow("Fenster an gemeinsamen Kanten mitziehen", isOn: $prefs.linkEdges)
                divider
                toggleRow("Andocken per Ziehen an den Bildschirmrand", isOn: $prefs.dragSnap)
                divider
                toggleRow("Beim Herausziehen ursprüngliche Größe", isOn: $prefs.restoreOnDragOut)
                divider
                toggleRow("Geteilte Fenster bleiben zusammen", isOn: $prefs.keepPairs)
                    .onChange(of: prefs.keepPairs) { engine.applyPairSetting() }
                divider
                row("Abstand zwischen Fenstern") {
                    Picker("Abstand zwischen Fenstern", selection: $prefs.gap) {
                        ForEach(Preferences.gapChoices, id: \.self) { Text($0 == 0 ? "Kein Abstand" : "\($0) pt").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            card("Tastenkürzel") {
                toggleRow("Tastenkürzel", isOn: $prefs.shortcuts)
                    .onChange(of: prefs.shortcuts) { engine.applyShortcutSetting() }
                if !engine.failedShortcuts.isEmpty {
                    note("\(engine.failedShortcuts.count) Kürzel belegt, läuft Magnet noch?",
                         symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                }
            }
            card("Hintergrund abdunkeln") {
                toggleRow("Alle Fenster außer dem aktiven abdunkeln", isOn: $prefs.dimEnabled)
                    .onChange(of: prefs.dimEnabled) { engine.applyDimSetting() }
                divider
                row("Stärke") {
                    Picker("Stärke", selection: $prefs.dimStrength) {
                        Text("Leicht").tag(20)
                        Text("Mittel").tag(35)
                        Text("Stark").tag(50)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: prefs.dimStrength) { engine.applyDimStrength() }
                }
                .disabled(!prefs.dimEnabled)
            }
        }
        .frame(width: 428)
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            if engine.spaces.available {
                card("Spaces") {
                    toggleRow("Space-Namen in der Menüleiste", isOn: $prefs.showSpaceName)
                    divider
                    toggleRow("Symbol ausblenden, wenn ein Space-Name steht", isOn: $prefs.hideIconWithSpaceName)
                        .disabled(!prefs.showSpaceName)
                    divider
                    Button("Spaces benennen …") {
                        engine.spaces.refresh()
                        openWindow(id: "spaces")
                    }
                    .buttonStyle(CardButtonStyle())
                    .padding(.vertical, FamilyTheme.Space.s)
                }
            }
            linksCard
            card("Allgemein") {
                toggleRow("Bei Anmeldung starten", isOn: Binding(
                    get: { login == .on || login == .needsApproval },
                    set: { on in
                        loginError = LoginItem.set(on)?.localizedDescription
                        login = LoginItem.state
                    }
                ))
                .disabled(login == .unavailable)
                if login == .needsApproval {
                    row(nil) {
                        Label("macOS wartet auf deine Freigabe", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(FamilyTheme.warning)
                        Spacer()
                        Button("Freigeben …") { LoginItem.openSystemSettings() }
                            .buttonStyle(CardButtonStyle())
                    }
                }
                if login == .unavailable {
                    note("macOS meldet einen unbekannten Autostart-Status",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
                if let loginError {
                    note(loginError, symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                }
                if let updater = engine.updater {
                    divider
                    Button("Nach Updates suchen …") { updater.checkForUpdates() }
                        .buttonStyle(CardButtonStyle())
                        .disabled(!updater.canCheck)
                        .padding(.vertical, FamilyTheme.Space.s)
                }
            }
        }
        .frame(width: 428)
        }
        .padding(FamilyTheme.Space.l)
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .fixedSize(horizontal: false, vertical: true)
        .familyBackground()
        .onAppear {
            login = LoginItem.state
            router.refresh()
        }
    }

    // MARK: - Links (E16)

    private var linksCard: some View {
        @Bindable var router = router
        return card("Links") {
            toggleRow("Seam verteilt Links (Standardbrowser)", isOn: Binding(
                get: { router.isDefault },
                set: { on in
                    linkError = nil
                    Task {
                        do {
                            if on { try await router.becomeDefault() } else { try await router.resignDefault() }
                        } catch {
                            linkError = error.localizedDescription
                            router.refresh()
                        }
                    }
                }))
            divider
            row("Standard-Browser") {
                Picker("Standard-Browser", selection: Binding(
                    get: { router.fallback ?? "" },
                    set: { router.fallback = $0.isEmpty ? nil : $0 })) {
                    Text("Jedes Mal fragen").tag("")
                    ForEach(router.browsers) { Text(verbatim: $0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
            divider
            toggleRow("Tracking-Parameter entfernen", isOn: $router.stripTracking)
            divider
            Button("Regeln bearbeiten … (\(router.rules.count))") {
                router.refresh()
                openWindow(id: "linkregeln")
            }
            .buttonStyle(CardButtonStyle())
            .padding(.vertical, FamilyTheme.Space.s)
            note("Fn beim Klick auf einen Link: Browser auswählen", symbol: "globe",
                 color: FamilyTheme.textSecondary)
            if let linkError {
                note(linkError, symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
            }
        }
    }

    // MARK: - Bausteine (wie Karten „Anordnen“ und „Spaces“ im Seam-Fenster)

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(FamilyTheme.font(.headline))
                .foregroundStyle(FamilyTheme.textPrimary)
                .padding(.bottom, FamilyTheme.Space.xs)
            content()
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func row<Control: View>(_ title: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            if let title {
                Text(title).foregroundStyle(FamilyTheme.textPrimary)
                Spacer(minLength: FamilyTheme.Space.m)
            }
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

    private func note(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(FamilyTheme.font(.callout))
            .foregroundStyle(color)
            .padding(.vertical, FamilyTheme.Space.xs)
    }

    private var divider: some View {
        Rectangle().fill(FamilyTheme.cardStroke).frame(height: 0.8)
    }
}

/// Knopf in einer Karte: gleiche Fläche wie die Kacheln im Seam-Fenster
/// (Kartenrand-Ton, Radius 9, beim Überfahren Akzent).
private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardButtonLabel(configuration: configuration)
    }
}

private struct CardButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let active = hovered && isEnabled
        configuration.label
            .font(FamilyTheme.font(.callout, weight: .medium))
            .foregroundStyle(active ? FamilyTheme.accent : FamilyTheme.textPrimary)
            .padding(.horizontal, FamilyTheme.Space.m)
            .frame(minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? FamilyTheme.accent.opacity(0.14) : FamilyTheme.cardStroke.opacity(0.45))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? FamilyTheme.accent.opacity(0.6) : .clear, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// Eigener Schalter: Apples `.switch` wird grau, sobald das Fenster nicht aktiv ist
/// (gemessen 09.10. im Vorschau-Render und in Michaels Screenshot) — das Seam-Fenster
/// hat nur eigene Bedienelemente und sieht immer gleich aus. Für VoiceOver bleibt es ein Toggle.
private struct FamilySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        FamilySwitch(configuration: configuration)
    }
}

private struct FamilySwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let on = configuration.isOn
        Capsule()
            .fill(on ? FamilyTheme.accent : FamilyTheme.textSecondary.opacity(0.28))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.18), value: on)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}
