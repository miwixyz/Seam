import SwiftUI

/// Menü in der Menüleiste. Bewusst ein einfaches Systemmenü.
/// Querformat-Kürzel stehen direkt im Hauptmenü (schneller auszuführen, Michael 08.10.),
/// alles andere im Untermenü „Einstellungen“. Hinweise, die man sehen muss
/// (Freigabe fehlt, Kürzel belegt, Update verfügbar), bleiben oben.
struct MenuContent: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var prefs = prefs

        if engine.isTrusted {
            Text("Seam ist aktiv")
        } else {
            Text("Bedienungshilfen-Freigabe fehlt")
            Button("Freigabe in den Systemeinstellungen öffnen …") { engine.openAccessibilitySettings() }
        }
        if !engine.failedShortcuts.isEmpty {
            // Typisch: Magnet läuft noch und hält dieselben Kürzel.
            Text("\(engine.failedShortcuts.count) Kürzel belegt (läuft Magnet noch?)")
        }
        if let version = engine.updater?.pendingVersion {
            Button("Update \(version) verfügbar …") { engine.updater?.checkForUpdates() }
        }

        Divider()

        shortcutList(.landscape)

        Divider()

        Menu("Einstellungen") {
            Toggle("Fenster an gemeinsamen Kanten mitziehen", isOn: $prefs.linkEdges)
            Toggle("Andocken per Ziehen an den Bildschirmrand", isOn: $prefs.dragSnap)
            Toggle("Beim Herausziehen ursprüngliche Größe", isOn: $prefs.restoreOnDragOut)
            Toggle("Tastenkürzel", isOn: $prefs.shortcuts)
                .onChange(of: prefs.shortcuts) { engine.applyShortcutSetting() }

            Picker("Abstand zwischen Fenstern", selection: $prefs.gap) {
                ForEach(Preferences.gapChoices, id: \.self) { Text($0 == 0 ? "Kein Abstand" : "\($0) pt").tag($0) }
            }

            Menu("Kürzel für Hochkant-Bildschirme") { shortcutList(.portrait) }

            Divider()

            Toggle("Bei Anmeldung starten", isOn: Binding(
                get: { LoginItem.state == .on },
                set: { LoginItem.set($0) }
            ))

            Divider()

            if let updater = engine.updater {
                Button("Nach Updates suchen …") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
            Button("Hilfe …") {
                openWindow(id: "hilfe")
                // Menüleisten-App ohne Dock-Symbol: sonst öffnet das Fenster hinter der aktiven App.
                NSApp.activate()
            }
        }

        Divider()
        Button("Seam beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Anklickbar wie bei Magnet: wirkt auf das vorderste Fenster, das Kürzel steht
    /// rechtsbündig daneben. Als reiner Text zeigte macOS die Liste grau (Michael, 08.10.).
    @ViewBuilder
    private func shortcutList(_ o: Orientation) -> some View {
        ForEach(Layout.specs(o), id: \.command) { spec in
            let shortcut = spec.key.menuShortcut
            let title = shortcut == nil ? "\(spec.command.title(o))   \(spec.key.label)" : spec.command.title(o)
            Button { engine.perform(spec.key) } label: {
                if let icon = MenuIcon.image(spec, o) {
                    Label { Text(title) } icon: { Image(nsImage: icon) }
                } else {
                    Text(title)
                }
            }
            .keyboardShortcut(shortcut)
            // macOS 27 blendet Menübilder sonst aus (Michael, 08.10.: keine Piktogramme sichtbar).
            .labelStyle(.titleAndIcon)
        }
    }
}

private extension KeyCombo {
    /// Dasselbe Kürzel als SwiftUI-Tastenkürzel, nur für die Anzeige im Menü.
    var menuShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch keyCode {
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        case 36: key = .return
        case 51: key = .delete
        case 115: key = .home
        default:
            guard let s = KeyboardLayout.character(for: keyCode)?.lowercased(), s.count == 1,
                  let c = s.first else { return nil }
            key = KeyEquivalent(c)
        }
        var mods: EventModifiers = []
        if modifiers & 4096 != 0 { mods.insert(.control) }
        if modifiers & 2048 != 0 { mods.insert(.option) }
        if modifiers & 512 != 0 { mods.insert(.shift) }
        if modifiers & 256 != 0 { mods.insert(.command) }
        return KeyboardShortcut(key, modifiers: mods)
    }
}
