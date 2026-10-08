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

    @ViewBuilder
    private func shortcutList(_ o: Orientation) -> some View {
        ForEach(Layout.specs(o), id: \.command) { spec in
            Text("\(spec.command.title(o))   \(spec.key.label)")
        }
    }
}
