import AppKit
import Observation
import OSLog
import SwiftUI

/// Zustand der Online-Auswahl (E19): Suche, Treffer, Vorschauen, Laden.
@MainActor
@Observable
final class OnlineGallery {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "online")
    /// Pixabay verlangt, Antworten 24 Stunden zu speichern (Doku 10.11.). Nur im Arbeitsspeicher.
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60

    var source: OnlineSource = .pixabay { didSet { if !source.hasVideos { kind = .photo } } }
    var kind: OnlineKind = .photo
    var query = ""
    var selected: OnlineItem?
    private(set) var items: [OnlineItem] = []
    private(set) var thumbs: [String: NSImage] = [:]
    private(set) var hasMore = false
    private(set) var busy = false
    private(set) var downloading = false
    private(set) var message: String?
    /// Quellen mit gespeichertem Schlüssel (E19b).
    private(set) var keyed: Set<OnlineSource> = OnlineGallery.storedKeys()

    @ObservationIgnored private var page = 1
    @ObservationIgnored private var nextOffset: Int?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadingThumbs: Set<String> = []
    @ObservationIgnored private var cache: [String: (date: Date, data: Data)] = [:]

    var hasKey: Bool { !source.needsKey || keyed.contains(source) }

    private static func storedKeys() -> Set<OnlineSource> {
        Set(OnlineSource.allCases.filter { ApiKey.of($0)?.load() != nil })
    }

    // MARK: Suchen

    func search() {
        searchTask?.cancel()
        items = []
        thumbs = [:]
        selected = nil
        page = 1
        nextOffset = 0
        message = nil
        load()
    }

    func more() { load() }

    private func load() {
        guard hasKey else { message = OnlineFetcher.Failure.noKey.message; return }
        busy = true
        let source = source, kind = kind, query = query, page = page, offset = nextOffset ?? 0
        searchTask = Task { [weak self] in
            do {
                let result: OnlinePage
                var next: Int?
                switch source {
                case .pixabay:
                    guard let key = ApiKey.pixabay.load(),
                          let url = OnlineAPI.pixabay(query: query, kind: kind, page: page, key: key) else {
                        throw OnlineFetcher.Failure.noKey
                    }
                    let data = try await self?.cached(url) { try await OnlineFetcher.shared.data(url, limit: OnlineFetcher.maxJSON) }
                    result = try OnlineDecode.pixabay(data ?? Data(), kind: kind, page: page)
                case .pexels:
                    guard let url = OnlineAPI.pexels(query: query, kind: kind, page: page), let key = ApiKey.pexels.load() else {
                        throw OnlineFetcher.Failure.noKey
                    }
                    let data = try await OnlineFetcher.shared.data(url, key: key, limit: OnlineFetcher.maxJSON)
                    result = try OnlineDecode.pexels(data, kind: kind)
                case .wikimedia:
                    guard let url = OnlineAPI.wikimedia(query: query, offset: offset) else { throw OnlineFetcher.Failure.badData }
                    let data = try await OnlineFetcher.shared.data(url, limit: OnlineFetcher.maxJSON)
                    (result, next) = try OnlineDecode.wikimedia(data)
                }
                guard !Task.isCancelled, let self else { return }
                self.items += result.items.filter { new in !self.items.contains { $0.id == new.id } }
                self.hasMore = result.hasMore
                self.page += 1
                self.nextOffset = next
                self.busy = false
                if !result.blockedHosts.isEmpty {
                    self.message = "Nicht angeboten: Dateien auf unbekannten Servern (\(result.blockedHosts.joined(separator: ", ")))."
                } else if self.items.isEmpty {
                    self.message = "Keine Treffer."
                }
                // E19f: Quelle und Zahl, kein Suchwort, keine Adresse (Pixabay-Adressen tragen den Schlüssel).
                Self.log.notice("Online: \(source.rawValue, privacy: .public) \(result.items.count) Treffer")
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.busy = false
                self.message = (error as? OnlineFetcher.Failure)?.message ?? "Keine Verbindung zum Server."
            }
        }
    }

    /// Gleiche Anfrage innerhalb von 24 Stunden aus dem Speicher (Pixabay-Bedingung).
    private func cached(_ url: URL, fetch: () async throws -> Data) async throws -> Data {
        let k = url.absoluteString
        if let hit = cache[k], Date().timeIntervalSince(hit.date) < Self.cacheLifetime { return hit.data }
        let data = try await fetch()
        cache = cache.filter { Date().timeIntervalSince($0.value.date) < Self.cacheLifetime }
        if cache.count < 200 { cache[k] = (Date(), data) }
        return data
    }

    // MARK: Vorschauen

    func loadThumb(_ item: OnlineItem) {
        guard thumbs[item.id] == nil, !loadingThumbs.contains(item.id) else { return }
        loadingThumbs.insert(item.id)
        Task { [weak self] in
            let data = try? await OnlineFetcher.shared.data(item.thumb, limit: OnlineFetcher.maxThumb)
            guard let self else { return }
            self.loadingThumbs.remove(item.id)
            if let data, let img = NSImage(data: data) { self.thumbs[item.id] = img }
        }
    }

    // MARK: Schlüssel (E19b)

    func saveKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store = ApiKey.of(source), store.save(k) else {
            message = "So sieht ein Schlüssel nicht aus (20–100 Buchstaben, Ziffern, Bindestriche)."
            return false
        }
        keyed.insert(source)
        message = nil
        return true
    }

    func removeKey() {
        ApiKey.of(source)?.delete()
        keyed.remove(source)
        items = []
    }

    // MARK: Als Hintergrund setzen (E19d → E18)

    func use(_ item: OnlineItem, dark: Bool, prefs: Preferences, engine: Engine) {
        guard !downloading, let name = OnlineFiles.name(for: item), let dir = Self.folder() else {
            message = "Datei lässt sich nicht ablegen."
            return
        }
        downloading = true
        message = "Lädt \(item.kind == .video ? "Video" : "Foto") …"
        let target = dir.appendingPathComponent(name)
        Task { [weak self] in
            do {
                if !FileManager.default.fileExists(atPath: target.path) {
                    let limit = item.kind == .video ? OnlineFetcher.maxVideo : OnlineFetcher.maxPhoto
                    try await OnlineFetcher.shared.download(item.file, to: target, limit: limit)
                }
                guard let self else { return }
                prefs.setWallpaperPath(target.path, dark: dark)
                prefs.wallpaperEnabled = true
                engine.applyWallpaper()
                Self.cleanUp(dir, keep: [prefs.wallpaperPath, prefs.wallpaperPathDark])
                self.downloading = false
                self.message = "Gesetzt als Hintergrund für \(dark ? "dunkel" : "hell")."
            } catch {
                guard let self else { return }
                self.downloading = false
                self.message = (error as? OnlineFetcher.Failure)?.message ?? "Laden fehlgeschlagen."
            }
        }
    }

    /// `~/Library/Application Support/Seam/Hintergrund/Online/`.
    static func folder() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Seam/Hintergrund/Online", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// E19d: höchstens 30 Dateien, die gewählten nie. Nur Dateien mit bekannter Form.
    private static func cleanUp(_ dir: URL, keep: [String?]) {
        let keepNames = Set(keep.compactMap { $0 }.filter { $0.hasPrefix(dir.path) }.map { ($0 as NSString).lastPathComponent })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let files: [(name: String, date: Date)] = names.compactMap { n in
            guard OnlineSource.allCases.contains(where: { n.hasPrefix("\($0.rawValue)-") }),
                  OnlineFiles.extensions.contains((n as NSString).pathExtension.lowercased()) else { return nil }
            let d = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(n).path))?[.modificationDate] as? Date
            return (n, d ?? .distantPast)
        }
        for n in OnlineFiles.toRemove(files, keep: keepNames) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }
}

/// Fenster „Online-Auswahl“ (0.10, Michael 10.11.).
struct OnlineGalleryView: View {
    @Environment(Engine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @State private var gallery = OnlineGallery()
    @State private var keyInput = ""

    var body: some View {
        @Bindable var gallery = gallery
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            HStack(spacing: FamilyTheme.Space.s) {
                Picker("Quelle", selection: $gallery.source) {
                    ForEach(OnlineSource.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 340)
                .help("Woher die Bilder kommen")
                Picker("Art", selection: $gallery.kind) {
                    Text("Fotos").tag(OnlineKind.photo)
                    Text("Videos").tag(OnlineKind.video)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                .disabled(!gallery.source.hasVideos)
                .help(gallery.source.hasVideos ? "Fotos oder Videos"
                                               : "Wikimedia-Videos spielt macOS nicht ab, deshalb nur Fotos")
            }
            HStack(spacing: FamilyTheme.Space.s) {
                TextField("Suchwort, z. B. Berge, Meer, Nebel (leer = Auswahl der Redaktion)", text: $gallery.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { gallery.search() }
                Button("Suchen") { gallery.search() }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(gallery.busy || !gallery.hasKey)
            }
            if gallery.hasKey { grid } else { keyCard }
            footer
        }
        .padding(FamilyTheme.Space.l)
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .onChange(of: gallery.source) { gallery.search() }
        .onChange(of: gallery.kind) { gallery.search() }
        .onAppear { if gallery.items.isEmpty { gallery.search() } }
    }

    // MARK: Schlüssel

    private var keyHelp: SourceText {
        switch gallery.source {
        case .pixabay:
            return SourceText("Pixabay braucht einen kostenlosen Schlüssel. Anmelden, auf der API-Seite steht er beim Parameter "
                    + "„key“. Kopieren und hier einfügen.",
                    "https://pixabay.com/api/docs/", "Schlüssel bei pixabay.com/api/docs holen")
        default:
            return SourceText("Pexels braucht einen kostenlosen Schlüssel. Konto anlegen, unter „Your API Key“ den Schlüssel "
                    + "kopieren und hier einfügen. (Stand 10.11.: Pexels gibt gerade keine neuen Schlüssel aus.)",
                    "https://www.pexels.com/api/", "Schlüssel bei pexels.com/api holen")
        }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            Text("\(gallery.source.title)-Schlüssel").font(FamilyTheme.font(.headline))
            Text(keyHelp.text + " Seam legt ihn in deinem Schlüsselbund ab und schickt ihn nur an \(gallery.source.title).")
                .font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: keyHelp.link) {
                Link(keyHelp.linkTitle, destination: url)
            }
            HStack {
                SecureField("Schlüssel einfügen", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                Button("Speichern", action: saveKey)
                    .buttonStyle(.familyGlass(.capsule, size: 26))
            }
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func saveKey() {
        if gallery.saveKey(keyInput) { keyInput = ""; gallery.search() }
    }

    // MARK: Treffer

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(gallery.items) { item in tile(item) }
            }
            .padding(2)
            if gallery.hasMore, !gallery.items.isEmpty {
                Button("Mehr laden") { gallery.more() }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(gallery.busy)
                    .padding(.vertical, FamilyTheme.Space.s)
            }
            if gallery.busy { ProgressView().controlSize(.small).padding() }
        }
        .frame(maxHeight: .infinity)
    }

    private func tile(_ item: OnlineItem) -> some View {
        let isSelected = gallery.selected?.id == item.id
        return Button { gallery.selected = item } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = gallery.thumbs[item.id] {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(FamilyTheme.cardStroke)
                    }
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipped()
                if item.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? FamilyTheme.accent : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .help("\(item.credit) · \(item.width) × \(item.height)")
        .accessibilityLabel("\(item.kind == .video ? "Video" : "Foto") von \(item.credit)")
        .onAppear { gallery.loadThumb(item) }
    }

    // MARK: Fuß: Auswahl, Urheber, setzen

    private var origin: SourceText {
        switch gallery.source {
        case .pixabay: return SourceText("Fotos und Videos von Pixabay", "https://pixabay.com", "pixabay.com")
        case .pexels: return SourceText("Fotos und Videos von Pexels", "https://www.pexels.com", "pexels.com")
        case .wikimedia: return SourceText("Fotos von Wikimedia Commons, Lizenz je Bild", "https://commons.wikimedia.org", "commons.wikimedia.org")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            if let item = gallery.selected {
                HStack(spacing: FamilyTheme.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.credit).font(FamilyTheme.font(.callout, weight: .semibold)).lineLimit(1)
                        Text(verbatim: "\(item.license) · \(item.width) × \(item.height) · \(item.source.title)")
                            .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button { gallery.use(item, dark: false, prefs: prefs, engine: engine) } label: {
                        Label("Für hell", systemImage: "sun.max")
                    }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(gallery.downloading)
                    .help("Laden und als Hintergrund für die helle Darstellung setzen")
                    Button { gallery.use(item, dark: true, prefs: prefs, engine: engine) } label: {
                        Label("Für dunkel", systemImage: "moon")
                    }
                    .buttonStyle(.familyGlass(.capsule, size: 26))
                    .disabled(gallery.downloading)
                    .help("Laden und als Hintergrund für die dunkle Darstellung setzen")
                }
                if item.kind == .photo, max(item.width, item.height) < 2560 {
                    Label("Nur \(item.width) × \(item.height) Pixel: auf großen Monitoren unscharf. Videos sind bei Pixabay größer.",
                          systemImage: "exclamationmark.triangle")
                        .font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.warning)
                }
            }
            if let msg = gallery.message {
                Label(msg, systemImage: gallery.downloading ? "arrow.down.circle" : "info.circle")
                    .font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
            }
            HStack {
                Text(origin.text).font(FamilyTheme.font(.caption)).foregroundStyle(FamilyTheme.textSecondary)
                if let url = URL(string: origin.link) {
                    Link(origin.linkTitle, destination: url).font(FamilyTheme.font(.caption))
                }
                Spacer()
                if gallery.source.needsKey, gallery.hasKey {
                    Button("Schlüssel entfernen") { gallery.removeKey() }
                        .buttonStyle(.link).font(FamilyTheme.font(.caption))
                        .help("\(gallery.source.title)-Schlüssel aus dem Schlüsselbund löschen")
                }
            }
        }
    }
}

/// Fensterhülle wie die anderen Seam-Fenster.
struct OnlineGalleryWindow: View {
    static let size = CGSize(width: 760, height: 680)

    var body: some View {
        OnlineGalleryView()
            .frame(width: Self.size.width, height: Self.size.height)
            .familyBackground()
    }
}

/// Erklärtext und Link einer Quelle (Schlüssel holen, Herkunft nennen).
private struct SourceText {
    let text: String
    let link: String
    let linkTitle: String

    init(_ text: String, _ link: String, _ linkTitle: String) {
        self.text = text
        self.link = link
        self.linkTitle = linkTitle
    }
}
