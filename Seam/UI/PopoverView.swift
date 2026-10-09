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
    /// Beim Öffnen gelesen, nicht beobachtet (siehe `Engine.targetInfo`).
    @State private var targetName: String?

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
            footer
        }
        .padding(FamilyTheme.Space.l)
        .frame(width: 364)   // 332 pt Inhalt: so breit ist die Zeile „Ganz“ (5 Kacheln)
        .tint(FamilyTheme.accent)
        .onAppear {
            // Kacheln passend zum Bildschirm des Zielfensters (Code-Audit 09.10., C1).
            let info = engine.targetInfo()
            targetName = info.name
            if let o = info.orientation { orientation = o }
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: FamilyTheme.Space.s) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FamilyTheme.accent)
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
            notice(icon: "exclamationmark.triangle", text: "Bedienungshilfen-Freigabe fehlt",
                   action: "Öffnen", color: FamilyTheme.warning) { engine.openAccessibilitySettings() }
        }
        if !engine.failedShortcuts.isEmpty {
            notice(icon: "keyboard", text: "\(engine.failedShortcuts.count) Kürzel belegt (läuft Magnet noch?)",
                   action: nil, color: FamilyTheme.warning) {}
        }
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
                Picker("Ausrichtung", selection: $orientation) {
                    Text("Quer").tag(Orientation.landscape)
                    Text("Hochkant").tag(Orientation.portrait)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(space.isCurrent ? FamilyTheme.accent : FamilyTheme.cardStroke.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(space.isCurrent ? "Aktueller Space – klicken zum Benennen"
                              : "Wechseln mit ⌃← / ⌃→ oder Mission Control – klicken zum Benennen")
        .accessibilityLabel(space.isCurrent ? "\(title), aktueller Space" : title)
    }

    // MARK: - Fuß

    private var footer: some View {
        @Bindable var prefs = prefs
        return HStack(spacing: FamilyTheme.Space.s) {
            Button {
                prefs.dimEnabled.toggle()
                engine.applyDimSetting()
            } label: {
                Image(systemName: prefs.dimEnabled ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled")
                    .foregroundStyle(prefs.dimEnabled ? FamilyTheme.accent : FamilyTheme.textPrimary)
            }
            .buttonStyle(.familyGlass(.circle, size: 30))
            .help(prefs.dimEnabled ? "Hintergrund abdunkeln: an" : "Hintergrund abdunkeln: aus")
            .accessibilityLabel("Hintergrund abdunkeln")

            if engine.spaces.available {
                Button { openSpaces() } label: { Image(systemName: "square.on.square") }
                    .buttonStyle(.familyGlass(.circle, size: 30))
                    .help("Spaces benennen")
                    .accessibilityLabel("Spaces benennen")
            }
            Spacer()
            Button {
                open("einstellungen")
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.familyGlass(.circle, size: 30))
                .help("Einstellungen")
                .accessibilityLabel("Einstellungen")
            Button {
                open("hilfe")
            } label: { Image(systemName: "questionmark") }
                .buttonStyle(.familyGlass(.circle, size: 30))
                .help("Hilfe")
                .accessibilityLabel("Hilfe")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.familyGlass(.circle, size: 30))
                .help("Seam beenden")
                .accessibilityLabel("Seam beenden")
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
