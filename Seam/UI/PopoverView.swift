import SwiftUI

/// Glas-Popover (0.4, Michael 09.10.: „moderneres und schöneres Design“). Ersetzt das
/// Systemmenü. Aufbau nach dem Familien-Design: Popover = Glasfläche, darin feste Karten
/// (Regel G1), ein Akzent (Iris), Plus Jakarta Sans.
///
/// Kacheln wirken auf das Fenster der App, die vor dem Öffnen vorn war (`Engine.perform`).
struct PopoverView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var orientation: Orientation = .landscape
    @State private var hovered: Command?
    /// Beschriftung des runden Knopfs unter der Maus (Fuß), nil = keiner.
    @State private var footerHint: String?
    /// Beim Öffnen gelesen, nicht beobachtet (siehe `Engine.targetInfo`).
    @State private var targetName: String?
    /// Beim Öffnen berechnet (E17): weicht die Anordnung vom Layout ab? nil = kein Layout.
    @State private var deskDeviates: Bool?

    /// Gruppen in der Reihenfolge der Kürzeltabelle auf der Website.
    private static let groups: [(String, [Command])] = [
        ("Naht", [.split, .seamLeft, .seamRight]),
        ("Hälften", [.left, .right, .up, .down]),
        ("Viertel", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Drittel", [.firstThird, .centerThird, .lastThird]),
        ("Zwei Drittel", [.firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
        ("Ganz", [.maximize, .center, .restore, .previousDisplay, .nextDisplay]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            header
            notices
            arrangeCard
            if engine.spaces.available { spacesCard }
            if engine.spaces.available { layoutCard }
            footer
        }
        .padding(FamilyTheme.Space.l)
        .frame(width: 364)   // 332 pt Inhalt: so breit ist die Zeile „Ganz“ (5 Kacheln)
        .tint(FamilyTheme.accent)
        // Glas-Sprache (1.5.0): deckender, ruhig lebender Verlauf statt Systemglas. Ein buntes
        // Schreibtischbild färbt das Popover damit nicht mehr ein.
        .familyAmbientBackground()
        .onAppear {
            // Kacheln passend zum Bildschirm des Zielfensters (Code-Audit 09.10., C1).
            let info = engine.targetInfo()
            targetName = info.name
            if let o = info.orientation { orientation = o }
            deskDeviates = engine.deskDeviates()
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: FamilyTheme.Space.s) {
            // Familien-Symbol (Menüleiste, Fassung C) statt Systemsymbol, damit Kopf und Leiste gleich aussehen.
            Image("MenuBarSeam")
                .renderingMode(.template)
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(FamilyTheme.accent)
                .accessibilityHidden(true)
            Text("Seam").font(FamilyTheme.font(.title3, weight: .semibold)).foregroundStyle(FamilyTheme.textPrimary)
            Spacer()
            if let current = engine.spaces.current {
                Button { openSpaces() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.on.square").font(.system(size: 11, weight: .medium))
                        Text(SpaceNames.title(current, prefs.spaceNames)).font(FamilyTheme.font(.callout, weight: .medium))
                        if current.number > 0 {
                            // Nummer zählt je Bildschirm, also auch der Nenner (Code-Audit 09.10., C10).
                            Text("\(current.number)/\(engine.spaces.spaces.filter { !$0.isFullScreen && $0.display == current.display }.count)")
                                .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.familyGlass(.capsule, size: 26))
                .help("Aktueller Space – klicken zum Benennen")
            }
        }
    }

    // MARK: - Hinweise

    @ViewBuilder
    private var notices: some View {
        if !engine.isTrusted {
            notice(icon: "exclamationmark.triangle", text: "Freigabe „Gerätesteuerung und Datenzugriff“ fehlt",
                   action: "Öffnen", color: FamilyTheme.warning) { engine.openAccessibilitySettings() }
        }
        if !engine.failedShortcuts.isEmpty {
            notice(icon: "keyboard", text: "\(engine.failedShortcuts.count) Kürzel belegt (läuft Magnet noch?)",
                   action: nil, color: FamilyTheme.warning) {}
        }
        lidWakeNotices
        if let version = engine.updater?.pendingVersion {
            notice(icon: "arrow.down.circle", text: "Update \(version) verfügbar",
                   action: "Laden", color: FamilyTheme.accent) { engine.updater?.checkForUpdates() }
        }
    }

    private func notice(icon: String, text: String, action: String?, color: Color, perform: @escaping () -> Void) -> some View {
        HStack(spacing: FamilyTheme.Space.s) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textPrimary)
            Spacer()
            if let action {
                Button(action, action: perform).buttonStyle(.familyGlass(.capsule, size: 22))
            }
        }
        .padding(.horizontal, FamilyTheme.Space.m).padding(.vertical, FamilyTheme.Space.s)
        .familyCard(radius: FamilyTheme.Radius.field)
    }

    // MARK: - Kacheln

    private var arrangeCard: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack {
                Text("Anordnen").font(FamilyTheme.font(.headline)).foregroundStyle(FamilyTheme.textPrimary)
                Spacer()
                // Glas-Sprache: gleitende Akzent-Pille statt Systemumschalter.
                GlassPillBar(items: [Orientation.landscape, .portrait], selection: orientation,
                             label: { Text($0 == .landscape ? "Quer" : "Hochkant") },
                             onSelect: { orientation = $0 })
                    .accessibilityLabel("Ausrichtung")
            }
            ForEach(Self.groups, id: \.0) { group in
                HStack(spacing: 6) {
                    Text(group.0)
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(FamilyTheme.textSecondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(group.1, id: \.self) { cmd in
                        if let spec = Layout.spec(cmd, orientation) { tile(spec) }
                    }
                    Spacer(minLength: 0)
                }
            }
            Divider().padding(.top, 2)
            infoLine
        }
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func tile(_ spec: CommandSpec) -> some View {
        let isHovered = hovered == spec.command
        return Button {
            engine.perform(spec.command)
            dismiss()
        } label: {
            Group {
                if let icon = MenuIcon.image(spec, orientation) {
                    Image(nsImage: icon).renderingMode(.template)
                } else {
                    Image(systemName: "square.dashed")
                }
            }
            .foregroundStyle(isHovered ? FamilyTheme.accent : FamilyTheme.textPrimary)
            .frame(width: 42, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? FamilyTheme.accent.opacity(0.14) : FamilyTheme.cardStroke.opacity(0.45))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovered ? FamilyTheme.accent.opacity(0.6) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = spec.command } else if hovered == spec.command { hovered = nil }
        }
        .help("\(spec.command.title(orientation))  \(spec.key.label)")
        .accessibilityLabel(spec.command.title(orientation))
    }

    /// Unter den Kacheln: was die Kachel unter dem Zeiger tut, sonst worauf sie wirken.
    @ViewBuilder
    private var infoLine: some View {
        HStack {
            if let cmd = hovered, let spec = Layout.spec(cmd, orientation) {
                Text(cmd.title(orientation)).font(FamilyTheme.font(.callout, weight: .medium))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Spacer()
                Text(spec.key.label).font(FamilyTheme.font(.callout)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(FamilyTheme.cardStroke.opacity(0.7)))
                    .foregroundStyle(FamilyTheme.textSecondary)
            } else if let app = targetName {
                Text("Wirkt auf das vordere Fenster von \(app)")
                    .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary)
                Spacer()
            } else {
                Text("Wirkt auf das vordere Fenster").font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
                Spacer()
            }
        }
        .frame(minHeight: 22)
    }

    // MARK: - Spaces

    /// Alle Spaces, der aktuelle hervorgehoben (0.3 hatte die Liste im Menü, 0.4.0 nur noch unter
    /// „Spaces benennen“; Michael 09.10.: „Spaces-Liste zurück ins Popover“). Ein Klick öffnet
    /// „Spaces benennen“: Wechseln kann Seam nicht (E14, keine künstlichen Tastendrücke).
    private var spacesCard: some View {
        let spaces = engine.spaces.spaces.filter { !$0.isFullScreen }
        let displays = spaces.map(\.display).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            Text("Spaces").font(FamilyTheme.font(.headline)).foregroundStyle(FamilyTheme.textPrimary)
            ForEach(displays, id: \.self) { display in
                if displays.count > 1 {
                    Text("Bildschirm \((displays.firstIndex(of: display) ?? 0) + 1)")
                        .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(spaces.filter { $0.display == display }) { spaceChip($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func spaceChip(_ space: SpaceInfo) -> some View {
        let title = SpaceNames.title(space, prefs.spaceNames)
        return Button { openSpaces() } label: {
            HStack(spacing: 5) {
                Text("\(space.number)").font(FamilyTheme.font(.caption2, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(space.isCurrent ? FamilyTheme.onAccent : FamilyTheme.textSecondary)
                Text(title).font(FamilyTheme.font(.callout, weight: space.isCurrent ? .semibold : .regular))
                    .foregroundStyle(space.isCurrent ? FamilyTheme.onAccent : FamilyTheme.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background {
                // Aktueller Space: dieselbe leuchtende Akzent-Pille wie die Ausrichtung.
                if space.isCurrent {
                    FamilyAccentPill(shape: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FamilyTheme.cardStroke.opacity(0.45))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(space.isCurrent ? "Aktueller Space – klicken zum Benennen"
                              : "Wechseln mit ⌃← / ⌃→ oder Mission Control – klicken zum Benennen")
        .accessibilityLabel(space.isCurrent ? "\(title), aktueller Space" : title)
    }

    // MARK: - Layout (E17)

    /// Layouts pro Schreibtisch: Stand, Speichern, Aufräumen. Schreibtische am falschen Platz
    /// stehen als Hinweis mit Anleitung darüber (`→ ZU TUN`).
    private var layoutCard: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack {
                Text("Layout").font(FamilyTheme.font(.headline)).foregroundStyle(FamilyTheme.textPrimary)
                Spacer()
                Text("\(layoutStatus) · \(DeskMessages.shortcut)").font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            if !engine.deskIssues.isEmpty, let text = engine.deskMessage {
                Label(text, systemImage: "exclamationmark.triangle")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: FamilyTheme.Space.s) {
                Button {
                    engine.saveDeskLayout()
                    deskDeviates = false
                } label: { Label("Speichern", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .help("Jetzige Anordnung als Layout speichern: welche App auf welchem Schreibtisch, in welcher Größe")
                Button {
                    dismiss()
                    engine.tidyUp(automatic: false)
                } label: { Label("Aufräumen", systemImage: "rectangle.3.group") }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(deskDeviates == nil || engine.deskRunning)
                    .help("Nur offene Fenster auf ihren Schreibtisch und in ihre Größe (\(DeskMessages.shortcut))")
                Button {
                    dismiss()
                    engine.openAllAndTidy()
                } label: { Label("Alles öffnen", systemImage: "macwindow.badge.plus") }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(deskDeviates == nil || engine.deskRunning)
                    .help("Apps aus dem Layout öffnen, die noch nicht offen sind, dann aufräumen")
                Spacer(minLength: 0)
            }
            // Drei Knöpfe: Beschriftung nie umbrechen (Vorschau 11.11.: „Spei-cher-n“); mit Symbol
            // passten sie nicht nebeneinander („Speic…“), deshalb nur Text.
            .lineLimit(1)
            .labelStyle(.titleOnly)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private var layoutStatus: String {
        if engine.deskRunning { return "räumt auf …" }
        switch deskDeviates {
        case nil: return "noch nicht gespeichert"
        case true?: return "weicht ab"
        case false?: return "alles am Platz"
        }
    }

    // MARK: - Fuß

    /// Michael, 10.11.: Die macOS-Hinweise (`.help`) erscheinen im Menüleisten-Fenster nicht, die
    /// runden Knöpfe blieben rätselhaft. `onHover` kommt dort an (wie bei den Kacheln), also zeigt
    /// eine eigene Zeile unter den Knöpfen sofort, was der Knopf unter der Maus tut.
    private var footer: some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: FamilyTheme.Space.s) {
                Button {
                    prefs.dimEnabled.toggle()
                    engine.applyDimSetting()
                } label: {
                    Image(systemName: prefs.dimEnabled ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled")
                        .foregroundStyle(prefs.dimEnabled ? FamilyTheme.accent : FamilyTheme.textPrimary)
                }
                .islandButton()
                .modifier(HoverHint(text: prefs.dimEnabled ? "Hintergrund abdunkeln ist an – klicken zum Ausschalten"
                                                         : "Hintergrund abdunkeln ist aus – klicken zum Einschalten",
                                    current: $footerHint))
                .accessibilityLabel("Hintergrund abdunkeln")

                if engine.spaces.available {
                    Button { openSpaces() } label: { Image(systemName: "square.on.square") }
                        .islandButton()
                        .modifier(HoverHint(text: "Spaces benennen", current: $footerHint))
                        .accessibilityLabel("Spaces benennen")
                }
                Button { open("hintergrund") } label: {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(prefs.wallpaperEnabled ? FamilyTheme.accent : FamilyTheme.textPrimary)
                }
                .islandButton()
                .modifier(HoverHint(text: "Eigener Hintergrund: Video oder Bild", current: $footerHint))
                .accessibilityLabel("Hintergrund")
                lidWakeButton
                Spacer()
                Button {
                    open("einstellungen")
                } label: { Image(systemName: "gearshape") }
                    .islandButton()
                    .modifier(HoverHint(text: "Einstellungen", current: $footerHint))
                    .accessibilityLabel("Einstellungen")
                Button {
                    open("hilfe")
                } label: { Image(systemName: "questionmark") }
                    .islandButton()
                    .modifier(HoverHint(text: "Hilfe", current: $footerHint))
                    .accessibilityLabel("Hilfe")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .islandButton()
                    .modifier(HoverHint(text: "Seam beenden", current: $footerHint))
                    .accessibilityLabel("Seam beenden")
            }
            // Glas-Sprache: Die ganze Knopfreihe schwebt als eine Glas-Insel (wie Kallis Fußleiste),
            // die Knöpfe darin ohne eigenes Glas.
            .padding(.horizontal, 6).padding(.vertical, 4)
            .floatingGlassIsland(in: Capsule(style: .continuous))
            // Leerzeichen hält die Höhe, damit das Fenster beim Darüberfahren nicht springt.
            Text(verbatim: footerHint ?? " ")
                .padding(.leading, 8)
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(FamilyTheme.textSecondary)
                .lineLimit(1)
                .accessibilityIdentifier("seam.footerHint")
        }
    }

    private func openSpaces() {
        engine.spaces.refresh()
        open("spaces")
    }

    private func open(_ id: String) {
        // Erst öffnen, dann schließen: Nach `dismiss()` ist die Ansicht weg, die `openWindow`
        // ausführt (gemessen 09.10.: Zahnrad löste aus, Fenster kam nicht).
        openWindow(id: id)
        dismiss()
        // Menüleisten-App ohne Dock-Symbol: aktivieren und das neue Fenster ausdrücklich zum
        // Schlüsselfenster machen, sonst liegt es oben, bleibt aber inaktiv (Schalter grau).
        // Gemessen 09.10. mit NSWorkspace (System Events meldet bei Menüleisten-Apps Veraltetes).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Wach bei zugeklapptem Deckel (E23)

extension PopoverView {

    /// Freigabe des Helfers fehlt, er antwortet nicht, oder er hat von allein abgeschaltet.
    @ViewBuilder
    fileprivate var lidWakeNotices: some View {
        let wake = engine.lidWake
        if wake.state == .needsApproval {
            notice(icon: "cup.and.saucer", text: "Wach-Helfer erlauben: „App-Hintergrundaktivitäten“",
                   action: "Öffnen", color: FamilyTheme.warning) { wake.openApproval() }
        }
        if case .failed(let text) = wake.state {
            notice(icon: "cup.and.saucer", text: text, action: nil, color: FamilyTheme.warning) {}
        }
        if let text = wake.notice {
            notice(icon: "cup.and.saucer", text: text, action: "OK", color: FamilyTheme.warning) { wake.dismissNotice() }
        }
    }

    fileprivate var lidWakeButton: some View {
        let wake = engine.lidWake
        return Button { wake.toggle() } label: {
            Image(systemName: wake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(wake.isOn ? FamilyTheme.accent : FamilyTheme.textPrimary)
        }
        .islandButton()
        .modifier(HoverHint(text: wake.isOn ? "Wach bei zugeklapptem Deckel ist an – klicken zum Ausschalten"
                                            : "Wach bei zugeklapptem Deckel – klicken zum Einschalten",
                            current: $footerHint))
        .accessibilityLabel("Wach bei zugeklapptem Deckel")
    }
}

/// Beschriftung beim Darüberfahren: setzt `current`, solange die Maus auf dem Knopf steht.
/// `.help` bleibt dabei (für Fenster, in denen macOS Hinweise zeigt, und für Bedienungshilfen).
private struct HoverHint: ViewModifier {
    let text: String
    @Binding var current: String?

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { inside in
                if inside { current = text } else if current == text { current = nil }
            }
    }
}
