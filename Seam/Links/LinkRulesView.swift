import AppKit
import SwiftUI

/// Regeln bearbeiten (docs/SECURE-DESIGN.md E16e/E16f). Erste passende Regel gewinnt, deshalb
/// lässt sich die Reihenfolge ändern. Kein Bedienungshilfen-Zugriff (Lint-Regel `link_weg_ohne_ax`).
struct LinkRulesView: View {
    @Bindable var router: LinkRouter
    @State private var apps: [(id: String, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            Text("Erste passende Regel gewinnt. Eine Website gilt auch für ihre Subdomains (cineweb.de → www.cineweb.de).")
                .font(FamilyTheme.font(.callout))
                .foregroundStyle(FamilyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if router.rules.isEmpty {
                Text("Noch keine Regeln. Tipp: Im Auswahlfenster (Fn beim Klick) legt ⌘-Klick eine Regel an.")
                    .font(FamilyTheme.font(.callout))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .padding(FamilyTheme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .familyCard(radius: FamilyTheme.Radius.field)
            } else {
                ScrollView {
                    VStack(spacing: FamilyTheme.Space.s) {
                        ForEach(router.rules) { rule in
                            RuleRow(rule: rule, index: index(of: rule), count: router.rules.count,
                                    browsers: router.browsers, apps: apps,
                                    update: { new in replace(rule, with: new) },
                                    move: { move(rule, by: $0) },
                                    delete: { router.rules.removeAll { $0.id == rule.id } })
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Button("Regel hinzufügen") { add() }
                    .disabled(router.rules.count >= LinkRules.maxRules || router.browsers.isEmpty)
                Spacer()
                Text("\(router.rules.count) von \(LinkRules.maxRules)")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
        }
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .onAppear {
            router.refresh()
            apps = Self.runningApps()
        }
    }

    private func index(of rule: LinkRule) -> Int { router.rules.firstIndex { $0.id == rule.id } ?? 0 }

    private func replace(_ rule: LinkRule, with new: LinkRule) {
        router.replaceRule(new)
    }

    private func move(_ rule: LinkRule, by delta: Int) {
        guard let i = router.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let j = i + delta
        guard router.rules.indices.contains(j) else { return }
        router.rules.swapAt(i, j)
    }

    private func add() {
        let target = router.fallback ?? router.browsers.first?.id ?? ""
        // Platzhalter-Website, damit die Regel gültig ist (E16i verlangt eine Bedingung).
        router.addRule(LinkRule(host: "beispiel.de", browser: target))
    }

    /// Laufende Apps mit Fenstern, als Auswahl für „Aus App“. Nur Name und Bundle-ID.
    private static func runningApps() -> [(id: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (id: String, name: String)? in
                guard let id = app.bundleIdentifier, id != own, !seen.contains(id) else { return nil }
                seen.insert(id)
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct RuleRow: View {
    let rule: LinkRule
    let index: Int
    let count: Int
    let browsers: [Browsers.Browser]
    let apps: [(id: String, name: String)]
    let update: (LinkRule) -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    @State private var hostText = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack(spacing: FamilyTheme.Space.s) {
                Text("\(index + 1).").foregroundStyle(FamilyTheme.textSecondary).frame(width: 24, alignment: .leading)
                TextField("Website (leer = jede)", text: $hostText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitHost)
                    .onChange(of: hostText) { invalid = false }
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
                        r.sourceApp = v.isEmpty ? nil : v
                        // Ohne Website und ohne App wäre die Regel leer (E16i) → nicht übernehmen.
                        if r.host != nil || r.sourceApp != nil { update(r) }
                    })) {
                    Text("jeder App").tag("")
                    ForEach(appChoices, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                Picker("öffnen in", selection: Binding(
                    get: { rule.browser },
                    set: { v in var r = rule; r.browser = v; update(r) })) {
                    ForEach(browserChoices, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
            }
            if invalid {
                Text("Ungültige Website. Erlaubt: Buchstaben, Ziffern, Punkt, Bindestrich.")
                    .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.warning)
            }
        }
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.field)
        .onAppear { hostText = rule.host ?? "" }
        .onChange(of: rule.host) { hostText = rule.host ?? "" }
    }

    /// Website übernehmen: leer = jede Website (dann muss eine App gewählt sein).
    private func commitHost() {
        var r = rule
        if hostText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard r.sourceApp != nil else { invalid = true; return }
            r.host = nil
        } else {
            guard let h = LinkRules.normalizeHost(hostText) else { invalid = true; return }
            r.host = h
            hostText = h
        }
        update(r)
    }

    /// Gespeicherte App auch zeigen, wenn sie gerade nicht läuft.
    private var appChoices: [(id: String, name: String)] {
        guard let s = rule.sourceApp, !apps.contains(where: { $0.id == s }) else { return apps }
        return apps + [(s, s)]
    }

    /// Gespeicherter Browser auch zeigen, wenn er fehlt (dann greift der Standard-Browser, E16c).
    private var browserChoices: [(id: String, name: String)] {
        let list = browsers.map { (id: $0.id, name: $0.name) }
        guard !list.contains(where: { $0.id == rule.browser }) else { return list }
        return list + [(rule.browser, "\(rule.browser) (fehlt)")]
    }
}
