import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Regeln bearbeiten (docs/SECURE-DESIGN.md E16e/E16f). Erste passende Regel gewinnt, deshalb
/// lässt sich die Reihenfolge ändern. Kein Bedienungshilfen-Zugriff (Lint-Regel `link_weg_ohne_ax`).
///
/// 0.5.1 (Michael, 10.10.): Fenster war zu klein (Liste kollabierte auf eine halbe Zeile), eine
/// getippte Website ging ohne Return verloren, und eine reine App-Regel („Links aus Outlook → Edge“)
/// ließ sich nur über Umwege anlegen. Jetzt: feste Größe, oben ein Bereich zum Anlegen (Website
/// oder App, auch nicht laufende Apps über „Andere App …“), Website wird beim Tippen übernommen.
struct LinkRulesView: View {
    @Bindable var router: LinkRouter
    @State private var apps: [AppChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            NewRuleCard(router: router, apps: $apps)
            Text(verbatim: "Erste passende Regel gewinnt. Eine Website gilt auch für ihre Subdomains (cineweb.de → www.cineweb.de).")
                .font(FamilyTheme.font(.callout))
                .foregroundStyle(FamilyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: FamilyTheme.Space.s) {
                    if router.rules.isEmpty {
                        Text("Noch keine Regeln. Tipp: Im Auswahlfenster (Fn beim Klick) legt ⌘-Klick eine Regel an.")
                            .font(FamilyTheme.font(.callout))
                            .foregroundStyle(FamilyTheme.textSecondary)
                            .padding(FamilyTheme.Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .familyCard(radius: FamilyTheme.Radius.field)
                    }
                    ForEach(router.rules) { rule in
                        RuleRow(rule: rule, index: index(of: rule), count: router.rules.count,
                                browsers: router.browsers, apps: $apps,
                                update: { router.replaceRule($0) },
                                move: { move(rule, by: $0) },
                                delete: { router.rules.removeAll { $0.id == rule.id } })
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Text("\(router.rules.count) von \(LinkRules.maxRules)")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
        }
        .frame(width: 620, height: 520)
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .onAppear {
            router.refresh()
            apps = AppChoice.running()
        }
    }

    private func index(of rule: LinkRule) -> Int { router.rules.firstIndex { $0.id == rule.id } ?? 0 }

    private func move(_ rule: LinkRule, by delta: Int) {
        guard let i = router.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let j = i + delta
        guard router.rules.indices.contains(j) else { return }
        router.rules.swapAt(i, j)
    }
}

/// App als Auswahl für „Aus App“: Bundle-ID + Name. Nur diese beiden Werte, nichts anderes.
struct AppChoice: Hashable {
    let id: String
    let name: String

    /// Laufende Apps mit Fenstern, nach Name.
    static func running() -> [AppChoice] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier, id != own, !seen.contains(id) else { return nil }
                seen.insert(id)
                return AppChoice(id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// „Andere App …“: Auswahl im Programme-Ordner, auch für Apps, die gerade nicht laufen.
    @MainActor
    static func pick() -> AppChoice? {
        let panel = NSOpenPanel()
        panel.title = "App auswählen"
        panel.prompt = "Auswählen"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let b = Bundle(url: url),
              let id = b.bundleIdentifier, LinkRules.isBundleID(id) else { return nil }
        let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppChoice(id: id, name: name)
    }

    /// Liste mit der gewählten App, auch wenn sie gerade nicht läuft.
    static func merged(_ list: [AppChoice], with id: String?) -> [AppChoice] {
        guard let id, !list.contains(where: { $0.id == id }) else { return list }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .map { $0.deletingPathExtension().lastPathComponent } ?? id
        return list + [AppChoice(id: id, name: name)]
    }
}

/// Wert im App-Picker, der statt einer App das Auswahlfenster öffnet.
private let pickOtherTag = "\u{0}andere"

/// Neue Regel anlegen: Website ODER App, dazu der Browser.
private struct NewRuleCard: View {
    @Bindable var router: LinkRouter
    @Binding var apps: [AppChoice]

    private enum Kind: String { case site, app }
    @State private var kind: Kind = .site
    @State private var host = ""
    @State private var app: String?
    @State private var browser = ""

    private var validHost: String? { LinkRules.normalizeHost(host) }
    private var canAdd: Bool {
        guard router.browsers.contains(where: { $0.id == browser }),
              router.rules.count < LinkRules.maxRules else { return false }
        return kind == .site ? validHost != nil : app != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack {
                Text("Neue Regel").font(FamilyTheme.font(.headline))
                Spacer()
                Picker("Art", selection: $kind) {
                    Text("Website").tag(Kind.site)
                    Text("App").tag(Kind.app)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack(spacing: FamilyTheme.Space.s) {
                if kind == .site {
                    TextField("z. B. cineweb.de", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                } else {
                    Picker("Links aus", selection: Binding(
                        get: { app ?? "" },
                        set: { v in
                            if v == pickOtherTag {
                                if let c = AppChoice.pick() {
                                    apps = AppChoice.merged(apps, with: c.id)
                                    app = c.id
                                }
                            } else {
                                app = v.isEmpty ? nil : v
                            }
                        })) {
                        Text("App wählen …").tag("")
                        ForEach(AppChoice.merged(apps, with: app), id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                        Divider()
                        Text("Andere App …").tag(pickOtherTag)
                    }
                }
                Text("öffnen in").foregroundStyle(FamilyTheme.textSecondary)
                Picker("öffnen in", selection: $browser) {
                    ForEach(router.browsers) { Text(verbatim: $0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Hinzufügen", action: add)
                    .disabled(!canAdd)
                    .keyboardShortcut(.defaultAction)
            }
            if kind == .site, !host.trimmingCharacters(in: .whitespaces).isEmpty, validHost == nil {
                Text("Ungültige Website. Erlaubt: Buchstaben, Ziffern, Punkt, Bindestrich.")
                    .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.warning)
            }
        }
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.field)
        .onAppear { if browser.isEmpty { browser = router.fallback ?? router.browsers.first?.id ?? "" } }
        .onChange(of: router.browsers) {
            if !router.browsers.contains(where: { $0.id == browser }) {
                browser = router.fallback ?? router.browsers.first?.id ?? ""
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        let rule = kind == .site ? LinkRule(host: validHost, browser: browser)
                                 : LinkRule(sourceApp: app, browser: browser)
        if router.addRule(rule) {
            host = ""
            app = nil
        }
    }
}

private struct RuleRow: View {
    let rule: LinkRule
    let index: Int
    let count: Int
    let browsers: [Browsers.Browser]
    @Binding var apps: [AppChoice]
    let update: (LinkRule) -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    @State private var hostText = ""

    private var invalid: Bool {
        let t = hostText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return rule.sourceApp == nil }
        return LinkRules.normalizeHost(t) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack(spacing: FamilyTheme.Space.s) {
                Text("\(index + 1).").foregroundStyle(FamilyTheme.textSecondary).frame(width: 24, alignment: .leading)
                TextField(rule.sourceApp == nil ? "Website" : "Website (leer = jede)", text: $hostText)
                    .textFieldStyle(.roundedBorder)
                    // Beim Tippen übernehmen, sobald gültig (0.5.1: ohne Return ging die Eingabe verloren).
                    .onChange(of: hostText) { commitHost() }
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).help("Nach oben")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index >= count - 1).help("Nach unten")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.help("Löschen")
            }
            .buttonStyle(.borderless)
            HStack(spacing: FamilyTheme.Space.s) {
                Spacer().frame(width: 24)
                Picker("Aus App", selection: Binding(
                    get: { rule.sourceApp ?? "" },
                    set: { v in
                        var r = rule
                        if v == pickOtherTag {
                            guard let c = AppChoice.pick() else { return }
                            apps = AppChoice.merged(apps, with: c.id)
                            r.sourceApp = c.id
                        } else {
                            r.sourceApp = v.isEmpty ? nil : v
                        }
                        // Ohne Website und ohne App wäre die Regel leer (E16i) → nicht übernehmen.
                        if r.host != nil || r.sourceApp != nil { update(r) }
                    })) {
                    Text("jeder App").tag("")
                    ForEach(AppChoice.merged(apps, with: rule.sourceApp), id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                    Divider()
                    Text("Andere App …").tag(pickOtherTag)
                }
                Picker("öffnen in", selection: Binding(
                    get: { rule.browser },
                    set: { v in var r = rule; r.browser = v; update(r) })) {
                    ForEach(browserChoices, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
            }
            if invalid {
                Text(hostText.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Website oder App angeben, sonst gilt die Regel nicht."
                     : "Ungültige Website. Erlaubt: Buchstaben, Ziffern, Punkt, Bindestrich.")
                    .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.warning)
            }
        }
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.field)
        .onAppear { hostText = rule.host ?? "" }
    }

    /// Website übernehmen, sobald gültig: leer = jede Website (dann muss eine App gewählt sein).
    private func commitHost() {
        var r = rule
        let t = hostText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            guard r.sourceApp != nil, r.host != nil else { return }
            r.host = nil
        } else {
            guard let h = LinkRules.normalizeHost(t), h != r.host else { return }
            r.host = h
        }
        update(r)
    }

    /// Gespeicherter Browser auch zeigen, wenn er fehlt (dann greift der Standard-Browser, E16c).
    private var browserChoices: [(id: String, name: String)] {
        let list = browsers.map { (id: $0.id, name: $0.name) }
        guard !list.contains(where: { $0.id == rule.browser }) else { return list }
        return list + [(rule.browser, "\(rule.browser) (fehlt)")]
    }
}
