import AppKit
import OSLog
import UniformTypeIdentifiers

/// Welche Apps Links öffnen können, und Links an sie übergeben (docs/SECURE-DESIGN.md E16c/E16k).
/// Kein Bedienungshilfen-Zugriff (Lint-Regel `link_weg_ohne_ax`).
@MainActor
enum Browsers {

    struct Browser: Identifiable, Hashable {
        let id: String          // Bundle-ID
        let name: String
        let url: URL
    }

    nonisolated private static let log = Logger(subsystem: "dev.mwlr.seam", category: "links")

    /// Nie Ziel: Seam selbst und andere Link-Verteiler — sie würden den Link zurückreichen (E16c).
    /// Kleingeschrieben verglichen: Velja heißt `com.sindresorhus.Velja` (gemessen 10.10., mit
    /// der ersten Liste in Kleinschreibung stand Velja in der Auswahl).
    nonisolated static let excluded: Set<String> = [
        "dev.mwlr.seam", "com.sindresorhus.velja", "se.johnste.finicky", "com.choosyosx.choosy",
        "com.browserosaurus", "com.bumpr.mac", "com.zipzapmac.openin",
    ]

    nonisolated static func isExcluded(_ bundleID: String) -> Bool {
        excluded.contains(bundleID.lowercased())
    }

    private static let probe = URL(string: "https://example.com")!

    /// Browser = App, die macOS für https **und** HTML-Dateien meldet, ohne `excluded`, nach Name
    /// sortiert. Nur https reichte nicht: gemessen 10.10. standen ChatGPT/Codex und Downie in der
    /// Liste. Doppelte Bundle-IDs (zwei Kopien derselben App) nur einmal: die von macOS bevorzugte.
    static func available() -> [Browser] {
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: probe)
        let html = Set(NSWorkspace.shared.urlsForApplications(toOpen: .html)
            .compactMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() })
        var seen = Set<String>()
        var out: [Browser] = []
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        for url in ([preferred].compactMap { $0 } + urls) {
            guard let b = Bundle(url: url), let id = b.bundleIdentifier,
                  !isExcluded(id), html.contains(id.lowercased()), !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(Browser(id: id, name: displayName(b, url: url), url: url))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func icon(for b: Browser) -> NSImage {
        NSWorkspace.shared.icon(forFile: b.url.path)
    }

    /// Einzige Wirkung eines Links (E16a): diese Adresse in diesem Browser öffnen.
    static func open(_ url: URL, in browser: Browser) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: cfg) { _, error in
            // Nur Bereich und Nummer: Der Meldungstext kann Dateiname oder Adresse enthalten (E16j).
            if let error {
                let e = error as NSError
                log.error("Öffnen in \(browser.id, privacy: .public) fehlgeschlagen: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }
    }

    // MARK: - Standardbrowser (E16k)

    /// Ist Seam gerade Standard für https? Von macOS gelesen, nicht gespiegelt (wie LoginItem).
    static var seamIsDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: probe).flatMap { Bundle(url: $0)?.bundleIdentifier }
            == Bundle.main.bundleIdentifier
    }

    /// Bundle-ID des aktuellen Standardbrowsers (kann Seam oder Velja sein).
    static var currentDefaultID: String? {
        NSWorkspace.shared.urlForApplication(toOpen: probe).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// Nur auf Klick des Nutzers. macOS fragt selbst nach, ob der Standardbrowser wechseln soll.
    static func makeDefault(_ appURL: URL) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: .html)
    }

    private static func displayName(_ b: Bundle, url: URL) -> String {
        (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}
