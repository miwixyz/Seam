#if DEBUG
import AppKit
import SwiftUI

/// Selbsttest (BAMA `test-mac-app`, Muster aus Gnotchi/Tippi/Kalli/TippAI/Qotti; Seam 2026-11-16). Startoption
/// statt Befehlskanal: `scripts/selftest.sh` baut eine Kopie mit eigener Kennung `dev.mwlr.seam.sichtpruefung` und
/// startet sie mit `--selftest` – kein Socket, kein Steuerprogramm, keine neue Angriffsfläche. PASS/FAIL je Zeile,
/// Exit 0 = alles bestanden, 1 = Fehlschlag, 64 = falsche Kennung.
///
/// Der Aufruf sitzt ganz oben in `Engine.init()`, **vor** Sparkle, Bedienungshilfen-Abfrage, Kürzeln, Maus-
/// Beobachtern, Abdunklung, Hintergrundbild und Paar-Wächter. Die Kopie legt also keine Fenster um, startet keine
/// Event-Taps, registriert keine globalen Kürzel (die hätten dieselben Tasten wie die echte Seam) und fragt keine
/// Freigabe an. Schreibende Schritte laufen in einer Wegwerf-Einstellungs-Suite.
@MainActor
enum SelfTest {
    struct Step: Sendable {
        let name: String
        let ok: Bool
        let detail: String
    }

    static let testBundleID = "dev.mwlr.seam.sichtpruefung"
    private static let scratchSuite = "dev.mwlr.seam.sichtpruefung.selftest"
    private static let timeLimit: Duration = .seconds(60)

    /// Ohne Schritte gilt es nicht als bestanden.
    static func passed(_ steps: [Step]) -> Bool { !steps.isEmpty && steps.allSatisfy(\.ok) }

    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    /// Beim Start der Engine aufrufen; kehrt zurück, die Schritte laufen danach und beenden den Prozess.
    static func start(engine: Engine) {
        guard Bundle.main.bundleIdentifier == testBundleID else {
            fputs("Selbsttest nur in der abgeschotteten Testkopie (\(testBundleID)), nicht als \(Bundle.main.bundleIdentifier ?? "?"). scripts/selftest.sh benutzen.\n", stderr)
            exit(64)
        }
        setvbuf(stdout, nil, _IOLBF, 0)   // Zeilenpuffer: bei einem Absturz bleiben die PASS-Zeilen davor erhalten
        Task { @MainActor in
            try? await Task.sleep(for: timeLimit)
            print("FAIL Zeitlimit — Selbsttest nach 60 s nicht fertig")
            exit(1)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))   // Szenen aufbauen lassen
            let steps = await run(engine: engine)
            let ok = passed(steps)
            print(ok ? "Selbsttest bestanden (\(steps.count) Schritte)" : "Selbsttest GESCHEITERT")
            exit(ok ? 0 : 1)
        }
    }

    private static func run(engine: Engine) async -> [Step] {
        var steps: [Step] = []
        func add(_ step: Step) {
            steps.append(step)
            print("\(step.ok ? "PASS" : "FAIL") \(step.name) — \(step.detail)")
        }
        add(isolation(engine: engine))
        add(resources())
        add(bundleSeal())
        add(preferencesRoundTrip())
        add(geometry())
        add(linkRules())
        add(await windows(engine: engine))
        add(await spaceWatcherSmoke())
        return steps
    }

    // MARK: Schritte

    /// Eigene Kennung und nichts gestartet: keine Freigabe, keine Engines (Kürzel, Maus, Abdunkeln, Paare).
    private static func isolation(engine: Engine) -> Step {
        let id = Bundle.main.bundleIdentifier ?? "?"
        let trusted = AXAccess.isTrusted
        let idle = !engine.isTrusted && !engine.deskRunning
        return Step(name: "Abschottung", ok: id == testBundleID && !trusted && idle,
                    detail: "Kennung \(id), Bedienungshilfen für die Kopie: \(trusted ? "ERTEILT" : "keine"), Engines: " + (idle ? "nicht gestartet" : "LAUFEN"))
    }

    /// Schrift und Texte im Bündel – fehlt die Schrift, fällt die Oberfläche still auf die Systemschrift zurück.
    private static func resources() -> Step {
        let font = NSFontManager.shared.availableMembers(ofFontFamily: FamilyTheme.fontFamily) != nil
        let names: [String] = ["HILFE", "CHANGELOG", "THIRD-PARTY-LICENSES"]
        let missing: [String] = names.filter { Bundle.main.url(forResource: $0, withExtension: "md") == nil }
        let fontText = font ? "da" : "FEHLT"
        let missingText = missing.isEmpty ? "" : ", fehlt: " + missing.joined(separator: ", ")
        return Step(name: "Ressourcen", ok: font && missing.isEmpty, detail: "Schrift " + fontText + missingText)
    }

    /// Siegel unversehrt (ad hoc signierte Kopie, deshalb ohne Team-Anforderung).
    private static func bundleSeal() -> Step {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
            status = SecStaticCodeCheckValidity(code, flags, nil)
        }
        return Step(name: "Bundle-Siegel", ok: status == errSecSuccess, detail: "OSStatus \(status)")
    }

    /// Einstellung schreiben, mit neuer Instanz lesen – in einer Wegwerf-Suite, nie in den echten Einstellungen.
    private static func preferencesRoundTrip() -> Step {
        guard let suite = UserDefaults(suiteName: scratchSuite) else {
            return Step(name: "Einstellungen", ok: false, detail: "Suite nicht angelegt")
        }
        suite.removePersistentDomain(forName: scratchSuite)
        defer { suite.removePersistentDomain(forName: scratchSuite) }
        // Abstand kennt nur `Preferences.gapChoices`; ein ungültiger gespeicherter Wert fällt auf 5 zurück.
        let before = Preferences(defaults: suite).gap
        guard let target = Preferences.gapChoices.first(where: { $0 != before }) else {
            return Step(name: "Einstellungen", ok: false, detail: "keine zweite Abstandswahl")
        }
        Preferences(defaults: suite).gap = target
        let after = Preferences(defaults: suite).gap
        suite.set(7, forKey: "gap")   // keine gültige Wahl
        let fallback = Preferences(defaults: suite).gap
        return Step(name: "Einstellungen", ok: after == target && fallback == 5,
                    detail: "Abstand \(before) → \(after), ungültiger Wert 7 → \(fallback)")
    }

    /// Raster im echten Bündel, mit Magnets Werten von Hand gerechnet (Erwartung aus `GeometryTests`): linke und
    /// rechte Hälfte eines 3440 × 1440-Bildschirms mit Abstand 5, beide treffen sich mit genau einem Abstand.
    private static func geometry() -> Step {
        let visible = CGRect(x: 0, y: 40, width: 3440, height: 1400)
        let left = Geometry.rect(for: Cells(0, 0, 12, 12), in: visible, .landscape, gap: 5)
        let right = Geometry.rect(for: Cells(12, 0, 12, 12), in: visible, .landscape, gap: 5)
        let leftOK = left == CGRect(x: 5, y: 45, width: 1713, height: 1390)
        let gapOK = right.minX - left.maxX == 5
        return Step(name: "Fenster-Raster", ok: leftOK && gapOK,
                    detail: "linke Hälfte \(Int(left.width))×\(Int(left.height)): \(leftOK ? "ja" : "NEIN"), Lücke zur rechten Hälfte \(Int(right.minX - left.maxX)): \(gapOK ? "ja" : "NEIN")")
    }

    /// Link-Regeln im echten Bündel: nur http/https, kein Host-Trick, Verfolgungsparameter raus, Teilstring-Hosts treffen nicht.
    private static func linkRules() -> Step {
        let accepts = LinkRules.accept("https://cineweb.de/kino") != nil
        let rejects = LinkRules.accept("javascript:alert(1)") == nil && LinkRules.accept("file:///etc/passwd") == nil
            && LinkRules.accept("http://evil.com\\@cineweb.de/x") == nil
        let stripped = URL(string: "https://example.com/a?id=7&utm_source=nl&fbclid=abc#teil").map { LinkRules.stripTracking($0).absoluteString }
        let stripOK = stripped == "https://example.com/a?id=7#teil"
        let hosts = LinkRules.hostMatches("www.cineweb.de", rule: "cineweb.de") && !LinkRules.hostMatches("evilcineweb.de", rule: "cineweb.de")
            && !LinkRules.hostMatches("cineweb.de.evil.com", rule: "cineweb.de")
        return Step(name: "Link-Regeln", ok: accepts && rejects && stripOK && hosts,
                    detail: "annehmen \(accepts), ablehnen \(rejects), Tracking raus \(stripOK), Host-Vergleich \(hosts)")
    }

    /// Einstellungen und Hilfe bauen sich mit der Engine auf und haben eine sinnvolle Größe. Danach wieder zu.
    private static func windows(engine: Engine) async -> Step {
        func open(_ view: some View) async -> (visible: Bool, size: CGSize) {
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.makeKeyAndOrderFront(nil)
            var visible = false
            for _ in 0..<20 where !visible {
                visible = window.isVisible
                if !visible { try? await Task.sleep(for: .milliseconds(100)) }
            }
            try? await Task.sleep(for: .milliseconds(500))   // ein Zeichendurchlauf
            let size = host.view.fittingSize
            window.close()
            return (visible, size)
        }
        let settings = await open(SettingsView().environment(engine).environment(engine.prefs))
        let help = await open(HelpView().padding(16).frame(width: 520))
        let ok = settings.visible && settings.size.height > 100 && help.visible && help.size.height > 100
        return Step(name: "Fenster", ok: ok,
                    detail: "Einstellungen \(Int(settings.size.width))×\(Int(settings.size.height)), Hilfe \(Int(help.size.width))×\(Int(help.size.height))")
    }

    /// Rauchtest der Space-Beobachtung (Rückrufe über Systembenachrichtigungen, ohne Freigabe lesbar): eigene
    /// Beobachter-Instanz ohne `onChange` (schreibt also nichts in Einstellungen), 3 s laufen lassen.
    private static func spaceWatcherSmoke() async -> Step {
        let watcher = SpaceWatcher()
        watcher.start()
        for _ in 0..<6 {
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try? await Task.sleep(for: .milliseconds(500))
        }
        return Step(name: "Space-Beobachtung", ok: watcher.available,
                    detail: "\(watcher.spaces.count) Spaces gelesen, aktueller Space: " + (watcher.current == nil ? "unbekannt" : "erkannt") + ", 3 s ohne Absturz")
    }
}
#endif
