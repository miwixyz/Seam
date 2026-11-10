import Foundation

/// Online-Auswahl (E19, docs/SECURE-DESIGN.md): Quellen, Treffer, Adressen, Dateinamen.
/// Reine Rechnung ohne Netz, getestet (SeamTests/OnlineMediaTests).

enum OnlineSource: String, CaseIterable, Sendable {
    case pixabay
    case pexels
    case wikimedia

    var title: String {
        switch self {
        case .pixabay: return "Pixabay"
        case .pexels: return "Pexels"
        case .wikimedia: return "Wikimedia Commons"
        }
    }

    /// Braucht einen Schlüssel des Nutzers (E19b).
    var needsKey: Bool { self != .wikimedia }
    /// Hat abspielbare Videos (Wikimedia nur webm, gemessen 10.11.).
    var hasVideos: Bool { self != .wikimedia }
}

enum OnlineKind: String, CaseIterable, Sendable {
    case photo
    case video
}

/// Ein Treffer: Vorschau, Datei, Urheber, Lizenz.
struct OnlineItem: Identifiable, Equatable, Sendable {
    let source: OnlineSource
    let kind: OnlineKind
    let number: Int
    let width: Int
    let height: Int
    let thumb: URL
    let file: URL
    /// Endung aus der Liste `OnlineFiles.extensions` (E19d), nie vom Server übernommen.
    let fileExtension: String
    let credit: String
    let license: String

    var id: String { "\(source.rawValue)-\(number)" }
}

/// Ergebnis einer Suchseite. `blockedHosts`: Dateien auf Servern außerhalb der Liste (E19a),
/// die Seam deshalb nicht anbietet — das Fenster nennt sie (nie stumm scheitern).
struct OnlinePage: Equatable, Sendable {
    let items: [OnlineItem]
    let hasMore: Bool
    let blockedHosts: [String]
}

// MARK: - E19a: feste Server

enum OnlineHosts {
    static let pexelsAPI = "api.pexels.com"
    static let pixabay = "pixabay.com"
    static let allowed: Set<String> = [
        "pixabay.com", "cdn.pixabay.com",
        "api.pexels.com", "images.pexels.com", "videos.pexels.com",
        "commons.wikimedia.org", "upload.wikimedia.org", "thumb.wikimedia.org",
    ]

    /// Nur `https`, Host exakt auf der Liste, kein Port, kein Benutzer/Passwort.
    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              allowed.contains(host), url.port == nil, url.user == nil, url.password == nil else { return false }
        return true
    }
}

// MARK: - Adressen der Suchen

enum OnlineAPI {
    static let maxQuery = 100
    static let perPage = 30

    /// Suchwort bereinigt (E19c): ohne Steuerzeichen, getrimmt, höchstens 100 Zeichen.
    static func cleanQuery(_ q: String) -> String {
        let s = String(q.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuery))
    }

    /// Pexels: mit Suchwort `/search`, ohne die Auswahl der Redaktion (Fotos) bzw. beliebte Videos.
    static func pexels(query: String, kind: OnlineKind, page: Int) -> URL? {
        let q = cleanQuery(query)
        var c = URLComponents()
        c.scheme = "https"
        c.host = OnlineHosts.pexelsAPI
        switch (kind, q.isEmpty) {
        case (.photo, false): c.path = "/v1/search"
        case (.photo, true): c.path = "/v1/curated"
        case (.video, false): c.path = "/videos/search"
        case (.video, true): c.path = "/videos/popular"
        }
        var items = [URLQueryItem(name: "per_page", value: "\(perPage)"),
                     URLQueryItem(name: "page", value: "\(max(1, page))")]
        if !q.isEmpty {
            items += [URLQueryItem(name: "query", value: q),
                      URLQueryItem(name: "orientation", value: "landscape"),
                      URLQueryItem(name: "size", value: "large")]
        }
        c.queryItems = items
        return c.url
    }

    /// Pixabay (Doku gelesen 10.11.): Schlüssel als Parameter `key` in der Adresse, Suchwort `q`
    /// ≤ 100 Zeichen, `per_page` 3–200. Fotos nur waagrecht, Videos ab 1920 px Breite.
    /// Die Adresse enthält den Schlüssel: nie protokollieren, nie weiterreichen (E19b).
    static func pixabay(query: String, kind: OnlineKind, page: Int, key: String) -> URL? {
        let q = cleanQuery(query)
        var c = URLComponents()
        c.scheme = "https"
        c.host = OnlineHosts.pixabay
        c.path = kind == .video ? "/api/videos/" : "/api/"
        var items = [URLQueryItem(name: "key", value: key),
                     URLQueryItem(name: "per_page", value: "\(perPage)"),
                     URLQueryItem(name: "page", value: "\(max(1, page))"),
                     URLQueryItem(name: "safesearch", value: "true"),
                     URLQueryItem(name: "min_width", value: "1920")]
        if kind == .photo {
            items += [URLQueryItem(name: "image_type", value: "photo"),
                      URLQueryItem(name: "orientation", value: "horizontal")]
        }
        if q.isEmpty {
            items.append(URLQueryItem(name: "editors_choice", value: "true"))
        } else {
            items.append(URLQueryItem(name: "q", value: q))
        }
        c.queryItems = items
        return c.url
    }

    /// Wikimedia Commons: nur Fotos (Videos dort sind webm, gemessen 10.11.). Ohne Suchwort die
    /// ausgezeichneten Bilder.
    static func wikimedia(query: String, offset: Int) -> URL? {
        let q = cleanQuery(query)
        let search = q.isEmpty ? "incategory:\"Featured pictures on Wikimedia Commons\" filetype:bitmap"
                               : "\(q) filetype:bitmap"
        var c = URLComponents()
        c.scheme = "https"
        c.host = "commons.wikimedia.org"
        c.path = "/w/api.php"
        c.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: search),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "\(perPage)"),
            URLQueryItem(name: "gsroffset", value: "\(max(0, offset))"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|size|mime|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "480"),
            URLQueryItem(name: "iiextmetadatafilter", value: "LicenseShortName|Artist"),
        ]
        return c.url
    }
}

// MARK: - Antworten (E19e: nur Codable)

/// Eine Videodatei aus der Pexels-Antwort.
struct OnlineVideoFile: Decodable, Equatable {
    let link: URL?
    let width: Int?
    let height: Int?
    let fileType: String?
}

private struct PexelsPhotoResponse: Decodable {
    let photos: [PexelsPhoto]
    let nextPage: String?
}

private struct PexelsPhoto: Decodable {
    let id: Int
    let width: Int
    let height: Int
    let photographer: String?
    let src: PexelsSrc
}

private struct PexelsSrc: Decodable {
    let original: URL?
    let large: URL?
    let medium: URL?
}

private struct PexelsVideoResponse: Decodable {
    let videos: [PexelsVideo]
    let nextPage: String?
}

private struct PexelsVideo: Decodable {
    let id: Int
    let width: Int
    let height: Int
    let image: URL?
    let user: PexelsUser?
    let videoFiles: [OnlineVideoFile]
}

private struct PexelsUser: Decodable { let name: String? }

private struct WikiResponse: Decodable {
    let query: WikiQuery?
    let `continue`: WikiContinue?
}

private struct WikiQuery: Decodable { let pages: [WikiPage] }

private struct WikiPage: Decodable {
    let pageid: Int
    let imageinfo: [WikiInfo]?
}

private struct WikiInfo: Decodable {
    let url: URL
    let thumburl: URL?
    let width: Int
    let height: Int
    let mime: String
    let extmetadata: WikiMeta?
}

private struct WikiMeta: Decodable {
    let licenseShortName: WikiValue?
    let artist: WikiValue?
    enum CodingKeys: String, CodingKey {
        case licenseShortName = "LicenseShortName"
        case artist = "Artist"
    }
}

private struct WikiValue: Decodable { let value: String }
private struct WikiContinue: Decodable { let gsroffset: Int? }

/// Pixabay: Adressen als Text, weil einzelne Felder leer ("") sein können — als `URL` dekodiert
/// fiele sonst die ganze Seite aus.
private struct PixabayResponse: Decodable {
    let totalHits: Int
    let hits: [PixabayHit]
}

private struct PixabayHit: Decodable {
    let id: Int
    let user: String?
    let previewURL: String?
    let webformatURL: String?
    let largeImageURL: String?
    let fullHDURL: String?
    let imageURL: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let videos: PixabayVideos?
}

private struct PixabayVideos: Decodable {
    let large: PixabayVideo?
    let medium: PixabayVideo?
}

private struct PixabayVideo: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
    let thumbnail: String?
}

private func nonEmptyURL(_ s: String?) -> URL? {
    guard let s, !s.isEmpty else { return nil }
    return URL(string: s)
}

enum OnlineDecode {

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func pexels(_ data: Data, kind: OnlineKind) throws -> OnlinePage {
        var blocked = Set<String>()
        switch kind {
        case .photo:
            let r = try decoder.decode(PexelsPhotoResponse.self, from: data)
            let items: [OnlineItem] = r.photos.compactMap { p in
                guard let file = p.src.original, let thumb = p.src.medium ?? p.src.large else { return nil }
                guard OnlineHosts.isAllowed(file), OnlineHosts.isAllowed(thumb) else {
                    blocked.insert(file.host ?? "?")
                    return nil
                }
                guard let ext = OnlineFiles.photoExtension(of: file) else { return nil }
                return OnlineItem(source: .pexels, kind: .photo, number: p.id, width: p.width, height: p.height,
                                  thumb: thumb, file: file, fileExtension: ext,
                                  credit: OnlineText.plain(p.photographer ?? "Unbekannt"), license: "Pexels-Lizenz")
            }
            return OnlinePage(items: items, hasMore: r.nextPage != nil, blockedHosts: blocked.sorted())
        case .video:
            let r = try decoder.decode(PexelsVideoResponse.self, from: data)
            let items: [OnlineItem] = r.videos.compactMap { v in
                guard let f = OnlineFiles.bestVideo(v.videoFiles), let file = f.link, let thumb = v.image else { return nil }
                guard OnlineHosts.isAllowed(file), OnlineHosts.isAllowed(thumb) else {
                    blocked.insert((OnlineHosts.isAllowed(file) ? thumb : file).host ?? "?")
                    return nil
                }
                return OnlineItem(source: .pexels, kind: .video, number: v.id, width: f.width ?? v.width,
                                  height: f.height ?? v.height, thumb: thumb, file: file, fileExtension: "mp4",
                                  credit: OnlineText.plain(v.user?.name ?? "Unbekannt"), license: "Pexels-Lizenz")
            }
            return OnlinePage(items: items, hasMore: r.nextPage != nil, blockedHosts: blocked.sorted())
        }
    }

    /// Pixabay: Fotos in der größten gelieferten Fassung (normaler Zugang: 1280 px), Videos
    /// „large“ (1920 px und mehr), sonst „medium“.
    static func pixabay(_ data: Data, kind: OnlineKind, page: Int) throws -> OnlinePage {
        let r = try decoder.decode(PixabayResponse.self, from: data)
        var blocked = Set<String>()
        let items: [OnlineItem] = r.hits.compactMap { h in
            let credit = OnlineText.plain(h.user ?? "Unbekannt")
            switch kind {
            case .photo:
                let candidates = [(h.imageURL, 0), (h.fullHDURL, 1920), (h.largeImageURL, 1280)]
                guard let (file, cap) = candidates.lazy.compactMap({ s, c in nonEmptyURL(s).map { ($0, c) } }).first,
                      let thumb = nonEmptyURL(h.webformatURL) ?? nonEmptyURL(h.previewURL) else { return nil }
                guard OnlineHosts.isAllowed(file), OnlineHosts.isAllowed(thumb) else {
                    blocked.insert(file.host ?? "?")
                    return nil
                }
                guard let ext = OnlineFiles.photoExtension(of: file) else { return nil }
                let size = OnlineFiles.scaled(width: h.imageWidth ?? 0, height: h.imageHeight ?? 0, maxEdge: cap)
                return OnlineItem(source: .pixabay, kind: .photo, number: h.id, width: size.width, height: size.height,
                                  thumb: thumb, file: file, fileExtension: ext, credit: credit, license: "Pixabay-Lizenz")
            case .video:
                let pick = [h.videos?.large, h.videos?.medium].compactMap { $0 }.first { nonEmptyURL($0.url) != nil }
                guard let v = pick, let file = nonEmptyURL(v.url), let thumb = nonEmptyURL(v.thumbnail) else { return nil }
                guard OnlineHosts.isAllowed(file), OnlineHosts.isAllowed(thumb) else {
                    blocked.insert((OnlineHosts.isAllowed(file) ? thumb : file).host ?? "?")
                    return nil
                }
                return OnlineItem(source: .pixabay, kind: .video, number: h.id, width: v.width ?? 0, height: v.height ?? 0,
                                  thumb: thumb, file: file, fileExtension: "mp4", credit: credit, license: "Pixabay-Lizenz")
            }
        }
        return OnlinePage(items: items, hasMore: page * OnlineAPI.perPage < r.totalHits, blockedHosts: blocked.sorted())
    }

    /// Zweiter Rückgabewert: Versatz der nächsten Seite (nil = keine weitere).
    static func wikimedia(_ data: Data) throws -> (OnlinePage, Int?) {
        let r = try decoder.decode(WikiResponse.self, from: data)
        var blocked = Set<String>()
        let items: [OnlineItem] = (r.query?.pages ?? []).compactMap { p in
            guard let i = p.imageinfo?.first, let thumb = i.thumburl,
                  let ext = OnlineFiles.extensionFor(mime: i.mime), ext != "mp4", ext != "mov" else { return nil }
            guard OnlineHosts.isAllowed(i.url), OnlineHosts.isAllowed(thumb) else {
                blocked.insert(i.url.host ?? "?")
                return nil
            }
            return OnlineItem(source: .wikimedia, kind: .photo, number: p.pageid, width: i.width, height: i.height,
                              thumb: thumb, file: i.url, fileExtension: ext,
                              credit: OnlineText.plain(i.extmetadata?.artist?.value ?? "Unbekannt"),
                              license: OnlineText.plain(i.extmetadata?.licenseShortName?.value ?? "Lizenz unbekannt"))
        }
        return (OnlinePage(items: items, hasMore: r.continue?.gsroffset != nil, blockedHosts: blocked.sorted()),
                r.continue?.gsroffset)
    }
}

// MARK: - E19d: Dateien

enum OnlineFiles {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "mp4", "mov"]
    static let maxFiles = 30

    static func extensionFor(mime: String) -> String? {
        switch mime.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default: return nil
        }
    }

    /// Pexels-Fotos haben keinen MIME-Typ in der Antwort: Endung der Adresse, nur aus der Liste.
    static func photoExtension(of url: URL) -> String? {
        let e = url.pathExtension.lowercased()
        switch e {
        case "jpg", "jpeg": return "jpg"
        case "png": return "png"
        default: return nil
        }
    }

    /// Bestes MP4: höchstens 4K, sonst das größte; nur Querformat-taugliche Dateien zählen gleich.
    static func bestVideo(_ files: [OnlineVideoFile]) -> OnlineVideoFile? {
        let mp4 = files.filter { $0.fileType?.lowercased() == "video/mp4" && $0.link != nil }
        let fitting = mp4.filter { ($0.width ?? 0) <= 3840 }
        return (fitting.isEmpty ? mp4 : fitting).max { ($0.width ?? 0) < ($1.width ?? 0) }
    }

    /// Größe einer verkleinerten Fassung: längste Kante höchstens `maxEdge` (0 = Original).
    static func scaled(width: Int, height: Int, maxEdge: Int) -> (width: Int, height: Int) {
        let edge = max(width, height)
        guard maxEdge > 0, edge > maxEdge else { return (width, height) }
        let k = Double(maxEdge) / Double(edge)
        return (Int((Double(width) * k).rounded()), Int((Double(height) * k).rounded()))
    }

    /// Dateiname nie vom Server: `<quelle>-<nummer>.<endung>`.
    static func name(for item: OnlineItem) -> String? {
        guard item.number > 0, extensions.contains(item.fileExtension) else { return nil }
        return "\(item.source.rawValue)-\(item.number).\(item.fileExtension)"
    }

    /// Welche Dateien weg? Älteste zuerst, bis höchstens `max` bleiben; `keep` (gerade gewählte
    /// helle/dunkle Datei) nie.
    static func toRemove(_ files: [(name: String, date: Date)], keep: Set<String>, max: Int = maxFiles) -> [String] {
        let removable = files.filter { !keep.contains($0.name) }.sorted { $0.date < $1.date }
        let excess = files.count - max
        guard excess > 0 else { return [] }
        return Array(removable.prefix(excess).map(\.name))
    }
}

// MARK: - E19e: Text aus Antworten

enum OnlineText {
    /// HTML-Tags weg, wenige Entitäten aufgelöst, Leerraum zusammengezogen, höchstens 120 Zeichen.
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(s.prefix(120))
    }
}
