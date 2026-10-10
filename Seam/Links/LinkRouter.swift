import AppKit
import Observation
import OSLog

/// Seam als Standardbrowser: nimmt Links an und gibt sie nach Regeln an einen Browser weiter
/// (docs/SECURE-DESIGN.md E16). Abgeschottet von den Fenster-Funktionen: kein Bedienungshilfen-
/// Zugriff, keine Fenster fremder Apps, kein Netz. Lint-Regel `link_weg_ohne_ax` (E16a).
@MainActor
@Observable
final class LinkRouter {

    static let shared = LinkRouter()

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "links")

    private enum Key {
        static let rules = "linkRules"
        static let fallback = "linkFallback"
        static let stripTracking = "linkStripTracking"
        static let pickerKeys = "linkPickerKeys"
    }

    private let defaults: UserDefaults

    /// Regeln in Reihenfolge, erste passende gewinnt (E16e).
    var rules: [LinkRule] { didSet { defaults.set(LinkRules.encode(rules), forKey: Key.rules) } }
    /// Standard-Browser, wenn keine Regel passt (Bundle-ID).
    var fallback: String? { didSet { defaults.set(fallback, forKey: Key.fallback) } }
    /// Tracking-Parameter entfernen (E16h), ab Werk an.
    var stripTracking: Bool { didSet { defaults.set(stripTracking, forKey: Key.stripTracking) } }
    /// Tasten, die beim Klick die Auswahl öffnen (E16g, ab 0.5.2 wählbar).
    var pickerKeys: Set<PickerKey> {
        didSet { defaults.set(pickerKeys.map(\.rawValue).sorted(), forKey: Key.pickerKeys) }
    }

    /// Ist Seam gerade Standardbrowser? Von macOS gelesen (E16k), bei `refresh()` aktualisiert.
    private(set) var isDefault = false
    private(set) var browsers: [Browsers.Browser] = []

    @ObservationIgnored private var sink: AppleEventSink?
    @ObservationIgnored private var picker: BrowserPickerPanel?
    @ObservationIgnored private var recent = RecentHandoffs()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = LinkRules.decode(defaults.data(forKey: Key.rules))
        let f = defaults.string(forKey: Key.fallback)
        fallback = f.flatMap { LinkRules.isBundleID($0) ? $0 : nil }
        stripTracking = defaults.object(forKey: Key.stripTracking) as? Bool ?? true
        pickerKeys = LinkRules.pickerKeys(from: defaults.stringArray(forKey: Key.pickerKeys))
    }

    /// Vor dem Ende des App-Starts, damit auch der Link ankommt, der Seam gestartet hat.
    func installHandler() {
        let sink = AppleEventSink { [weak self] raw, source, held in
            guard let self else { return }
            self.route(raw, source: source, picker: LinkRules.pickerRequested(held, keys: self.pickerKeys))
        }
        NSAppleEventManager.shared().setEventHandler(
            sink, andSelector: #selector(AppleEventSink.handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        self.sink = sink
    }

    func refresh() {
        browsers = Browsers.available()
        isDefault = Browsers.seamIsDefault
    }

    // MARK: - Links

    /// Ein Link von einer beliebigen App. Nie Adresse oder Host protokollieren (E16j).
    func route(_ raw: String, source: String?, picker wantsPicker: Bool) {
        guard let accepted = LinkRules.accept(raw) else {
            Self.log.notice("Link verworfen: kein http/https oder zu lang")
            return
        }
        let url = stripTracking ? LinkRules.stripTracking(accepted) : accepted
        browsers = Browsers.available()
        if wantsPicker {
            showPicker(url, source: source)
            return
        }
        // Kam der Link gerade von der App zurück, an die Seam ihn gegeben hat (unbekannter
        // Link-Verteiler)? Dann nicht wieder dorthin (E16c).
        let bounce = recent.isBounce(url, from: source)
        var ids = Set(browsers.map(\.id))
        if bounce, let s = source { ids = ids.filter { $0.lowercased() != s.lowercased() } }
        if let id = LinkRules.decide(url: url, source: source, rules: rules, available: ids, fallback: fallback),
           let b = browsers.first(where: { $0.id == id }) {
            Self.log.notice("Link → \(id, privacy: .public)\(bounce ? " (Rückläufer umgeleitet)" : "", privacy: .public)")
            hand(url, to: b)
        } else if bounce {
            Self.log.notice("Rückläufer ohne anderes Ziel, Link nicht geöffnet")
        } else {
            showPicker(url, source: source)
        }
    }

    private func hand(_ url: URL, to b: Browsers.Browser) {
        recent.record(url, to: b.id)
        Browsers.open(url, in: b)
    }

    /// HTML-Dateien (Seam ist als Browser auch für `public.html` eingetragen): ohne Regeln an
    /// den Standard-Browser (E16b, Ergänzung). Nur echte, lokale Dateien mit HTML-Endung nach dem
    /// Auflösen von Symlinks, höchstens 20 je Aufruf (Rafter-Review 10.10.).
    func openFiles(_ urls: [URL]) {
        let files = urls.prefix(20).compactMap(Self.htmlFile)
        if files.count < urls.count {
            Self.log.notice("\(urls.count - files.count, privacy: .public) Datei(en) ignoriert: keine lokale HTML-Datei oder zu viele")
        }
        guard !files.isEmpty else { return }
        browsers = Browsers.available()
        for url in files {
            if let b = browsers.first(where: { $0.id == fallback }) {
                hand(url, to: b)
            } else {
                showPicker(url, source: nil)
            }
        }
    }

    private static func htmlFile(_ url: URL) -> URL? {
        let html: Set<String> = ["html", "htm", "xhtml", "shtml"]
        guard url.isFileURL, url.host() == nil || url.host() == "" || url.host() == "localhost" else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        guard html.contains(resolved.pathExtension.lowercased()),
              (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return resolved
    }

    private func showPicker(_ url: URL, source: String?) {
        // Nur eine Auswahl zur Zeit (STRIDE D): Ein neuer Link ersetzt die offene Auswahl. Vorher
        // ging er an den Standard-Browser oder verloren, und ein liegengebliebenes Fenster
        // blockierte alle weiteren Links (0.5.1).
        picker?.replace()
        guard !browsers.isEmpty else {
            Self.log.error("Kein Browser gefunden, Link nicht geöffnet")
            return
        }
        let panel = BrowserPickerPanel(url: url, browsers: browsers, fallback: fallback) { [weak self] choice in
            self?.picked(choice, url: url)
        }
        picker = panel
        panel.present()
        Self.log.notice("Auswahl gezeigt (\(self.browsers.count, privacy: .public) Browser)")
    }

    private func picked(_ choice: BrowserPickerPanel.Choice, url: URL) {
        picker = nil
        switch choice {
        case .cancel(let why):
            Self.log.notice("Auswahl abgebrochen (\(why, privacy: .public)), Link nicht geöffnet")
        case .open(let b, let remember):
            var added = false
            if remember, !url.isFileURL, let host = LinkRules.urlHost(url) {
                added = addRule(LinkRule(host: host, browser: b.id))
            }
            Self.log.notice("Auswahl → \(b.id, privacy: .public)\(added ? " (Regel angelegt)" : "", privacy: .public)")
            hand(url, to: b)
        }
    }

    // MARK: - Regeln

    /// Hängt an und bereinigt. `true`, wenn die Regel wirklich in der Liste steht.
    @discardableResult
    func addRule(_ rule: LinkRule) -> Bool {
        rules = LinkRules.sanitize(rules + [rule])
        return rules.contains { $0.id == rule.id }
    }

    /// Regel ersetzen (Regel-Editor), bereinigt wie beim Laden (E16i).
    func replaceRule(_ rule: LinkRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var next = rules
        next[i] = rule
        rules = LinkRules.sanitize(next)
    }

    // MARK: - Standardbrowser (E16k, nur auf Klick)

    /// Seam als Standardbrowser. Vorher den bisherigen Standard als Rückfall merken.
    func becomeDefault() async throws {
        refresh()
        if fallback == nil {
            let current = Browsers.currentDefaultID
            fallback = browsers.contains { $0.id == current } ? current
                : browsers.first { $0.id == "com.apple.Safari" }?.id ?? browsers.first?.id
        }
        try await Browsers.makeDefault(Bundle.main.bundleURL)
        refresh()
    }

    /// Rolle an den Standard-Browser zurückgeben.
    func resignDefault() async throws {
        refresh()
        guard let b = browsers.first(where: { $0.id == fallback }) ?? browsers.first(where: { $0.id == "com.apple.Safari" })
        else { return }
        try await Browsers.makeDefault(b.url)
        refresh()
    }
}

/// Empfänger für das Apple Event „GetURL“. Liest Adresse, Absender und einmalig den Zustand der
/// Sondertasten (E16g: Zustand, keine Tastatur-Ereignisse).
/// Apple Events kommen auf dem Hauptthread an (NSAppleEventManager), daher `@MainActor`.
@MainActor
private final class AppleEventSink: NSObject {
    private let onURL: @MainActor (String, String?, HeldKeys) -> Void

    init(onURL: @escaping @MainActor (String, String?, HeldKeys) -> Void) {
        self.onURL = onURL
    }

    @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        let f = NSEvent.modifierFlags
        let held = HeldKeys(fn: f.contains(.function), option: f.contains(.option),
                            shift: f.contains(.shift), control: f.contains(.control))
        let source = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        onURL(raw, source, held)
    }
}
