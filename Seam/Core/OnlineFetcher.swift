import Foundation
import OSLog
import Security

/// Netzabrufe der Online-Auswahl (E19). Nur auf Handlung des Nutzers, nur feste Server (E19a),
/// mit Größen- und Zeitgrenzen (E19c). Keine Cookies, kein Platten-Cache.
final class OnlineFetcher: Sendable {

    static let shared = OnlineFetcher()
    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "online")

    static let maxJSON = 2 * 1024 * 1024
    static let maxThumb = 2 * 1024 * 1024
    static let maxPhoto = 60 * 1024 * 1024
    static let maxVideo = 600 * 1024 * 1024

    enum Failure: Error, Equatable {
        case hostNotAllowed(String)
        case unauthorized
        case rateLimited
        case status(Int)
        case tooLarge
        case badData
        case noKey

        var message: String {
            switch self {
            case .hostNotAllowed(let h): return "Datei liegt auf einem unbekannten Server (\(h)), Seam lädt sie nicht."
            case .unauthorized: return "Der Dienst lehnt den Schlüssel ab. Bitte prüfen oder neu eingeben."
            case .rateLimited: return "Zu viele Anfragen in kurzer Zeit. Bitte später noch einmal."
            case .status(let c): return c == 400 ? "Anfrage abgelehnt (400). Stimmt der Schlüssel?" : "Server antwortet mit Fehler \(c)."
            case .tooLarge: return "Datei ist zu groß."
            case .badData: return "Antwort des Servers ist unlesbar."
            case .noKey: return "Für diese Quelle fehlt noch dein Schlüssel."
            }
        }
    }

    /// Einmal beim Anlegen erzeugt (rafter-code-review 10.11.: als `lazy var` konnten gleichzeitige
    /// Vorschau-Abrufe sie doppelt anlegen — Data Race).
    private let session: URLSession

    private init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 600
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        // E19f: Wikimedia verlangt einen Kontakt; Projektadresse, keine Mail.
        c.httpAdditionalHeaders = ["User-Agent": "Seam/\(version) (https://github.com/miwixyz/Seam)"]
        session = URLSession(configuration: c, delegate: OnlineRedirectGuard(), delegateQueue: nil)
    }

    // MARK: - Abrufe

    /// Kleine Antworten (JSON, Vorschau) in den Speicher, höchstens `limit` Byte.
    func data(_ url: URL, key: String? = nil, limit: Int) async throws -> Data {
        let req = try request(url, key: key)
        let (bytes, response) = try await session.bytes(for: req)
        try check(response, limit: limit)
        var data = Data()
        data.reserveCapacity(min(limit, 256 * 1024))
        for try await b in bytes {
            data.append(b)
            if data.count > limit { throw Failure.tooLarge }
        }
        return data
    }

    /// Datei auf die Platte (E19d): erst Temp-Datei, Größe beim Empfangen gezählt, dann umbenannt.
    func download(_ url: URL, to target: URL, limit: Int) async throws {
        let req = try request(url, key: nil)
        let (bytes, response) = try await session.bytes(for: req)
        try check(response, limit: limit)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".laden-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: temp) else { throw Failure.badData }
        var ok = false
        defer {
            try? handle.close()
            if !ok { try? FileManager.default.removeItem(at: temp) }
        }
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var total = 0
        for try await b in bytes {
            buffer.append(b)
            if buffer.count >= 1 << 20 {
                total += buffer.count
                if total > limit { throw Failure.tooLarge }
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        total += buffer.count
        if total > limit { throw Failure.tooLarge }
        try handle.write(contentsOf: buffer)
        try handle.close()
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temp, to: target)
        ok = true
    }

    private func request(_ url: URL, key: String?) throws -> URLRequest {
        guard OnlineHosts.isAllowed(url) else { throw Failure.hostNotAllowed(url.host ?? "?") }
        var r = URLRequest(url: url)
        if let key {
            // E19b: Schlüssel nur an api.pexels.com.
            guard url.host?.lowercased() == OnlineHosts.pexelsAPI else { throw Failure.hostNotAllowed(url.host ?? "?") }
            r.setValue(key, forHTTPHeaderField: "Authorization")
        }
        return r
    }

    private func check(_ response: URLResponse, limit: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw Failure.badData }
        // E19f: nur Statuscode ins Protokoll, keine Adresse.
        if http.statusCode != 200 { Self.log.notice("Online: Status \(http.statusCode)") }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw Failure.unauthorized
        case 429: throw Failure.rateLimited
        default: throw Failure.status(http.statusCode)
        }
        if http.expectedContentLength > Int64(limit) { throw Failure.tooLarge }
    }
}

/// E19a: Weiterleitungen nur auf die Liste. Trägt die Anfrage einen Schlüssel (Kopf bei Pexels,
/// Parameter `key` bei Pixabay), nur auf denselben Server — sonst ginge der Schlüssel mit.
private final class OnlineRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard OnlineHosts.isAllowed(request.url) else { return nil }
        guard let original = task.originalRequest else { return nil }
        if OnlineRedirectGuard.carriesKey(original),
           request.url?.host?.lowercased() != original.url?.host?.lowercased() {
            return nil
        }
        return request
    }

    static func carriesKey(_ r: URLRequest) -> Bool {
        if r.value(forHTTPHeaderField: "Authorization") != nil { return true }
        guard let url = r.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { $0.name == "key" }
    }
}

/// Schlüssel der Nutzer im Schlüsselbund (E19b), nie in UserDefaults, nie im Protokoll.
/// Je Quelle ein Eintrag (`dev.mwlr.seam.pexels`, `dev.mwlr.seam.pixabay`).
struct ApiKey: Sendable {
    let service: String
    private let account = "api"

    static let pexels = ApiKey(service: "dev.mwlr.seam.pexels")
    static let pixabay = ApiKey(service: "dev.mwlr.seam.pixabay")

    static func of(_ source: OnlineSource) -> ApiKey? {
        switch source {
        case .pexels: return .pexels
        case .pixabay: return .pixabay
        case .wikimedia: return nil
        }
    }

    /// 20–100 Zeichen, nur Buchstaben, Ziffern und Bindestrich (Pixabay: „12345678-abc…“).
    static func isValid(_ key: String) -> Bool {
        (20...100).contains(key.count)
            && key.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    func load() -> String? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                  kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), Self.isValid(s) else { return nil }
        return s
    }

    @discardableResult
    func save(_ key: String) -> Bool {
        guard Self.isValid(key) else { return false }
        delete()
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                  kSecValueData: Data(key.utf8),
                                  kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(q as CFDictionary)
    }
}
