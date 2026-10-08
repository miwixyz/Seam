import SwiftUI

/// Menü in der Menüleiste. Bewusst ein einfaches Systemmenü: Seam soll man
/// nicht bedienen müssen, nur einstellen.
struct MenuContent: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs

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

        Divider()

        Toggle("Fenster an gemeinsamen Kanten mitziehen", isOn: $prefs.linkEdges)
        Toggle("Andocken per Ziehen an den Bildschirmrand", isOn: $prefs.dragSnap)
        Toggle("Beim Herausziehen ursprüngliche Größe", isOn: $prefs.restoreOnDragOut)
        Toggle("Tastenkürzel", isOn: $prefs.shortcuts)
            .onChange(of: prefs.shortcuts) { engine.applyShortcutSetting() }

        Picker("Abstand zwischen Fenstern", selection: $prefs.gap) {
            ForEach(Preferences.gapChoices, id: \.self) { Text($0 == 0 ? "Kein Abstand" : "\($0) pt").tag($0) }
        }

        Menu("Tastenkürzel anzeigen") {
            Section("Querformat") { shortcutList(.landscape) }
            Section("Hochkant") { shortcutList(.portrait) }
        }

        Divider()

        Toggle("Bei Anmeldung starten", isOn: Binding(
            get: { LoginItem.state == .on },
            set: { LoginItem.set($0) }
        ))

        Divider()
        Button("Seam beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Anklickbar wie bei Magnet: wirkt auf das vorderste Fenster, das Kürzel steht
    /// rechtsbündig daneben. Als reiner Text zeigte macOS die Liste grau (Michael, 08.10.).
    @ViewBuilder
    private func shortcutList(_ o: Orientation) -> some View {
        ForEach(Layout.specs(o), id: \.command) { spec in
            if let shortcut = spec.key.menuShortcut {
                Button(spec.command.title(o)) { engine.perform(spec.key) }
                    .keyboardShortcut(shortcut)
            } else {
                Button("\(spec.command.title(o))   \(spec.key.label)") { engine.perform(spec.key) }
            }
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
