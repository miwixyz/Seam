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
        session = URLSession(configuration: Self.makeConfiguration(), delegate: OnlineRedirectGuard(), delegateQueue: nil)
    }

    /// Eine Fassung für die gemeinsame Sitzung und jede Datei-Ladung.
    fileprivate static func makeConfiguration() -> URLSessionConfiguration {
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
        return c
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

    /// Datei auf die Platte (E19d): URLSession schreibt blockweise selbst in eine Temp-Datei (vorher
    /// Byte für Byte über `bytes`, code-audit 15.11.). `FileDownload` zählt beim Empfangen und
    /// bricht bei Überschreitung oder Status ≠ 200 ab; die fertige Datei liegt neben dem Ziel und
    /// ersetzt es in einem Schritt.
    func download(_ url: URL, to target: URL, limit: Int) async throws {
        let req = try request(url, key: nil)
        let fm = FileManager.default
        let staged = target.deletingLastPathComponent().appendingPathComponent(".laden-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staged) }
        try await FileDownload(limit: Int64(limit), staged: staged).run(req)
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: target)
        }
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
        try Self.checkStatus(http.statusCode)
        if http.expectedContentLength > Int64(limit) { throw Failure.tooLarge }
    }

    static func checkStatus(_ code: Int) throws {
        if let f = statusFailure(code) { throw f }
    }

    fileprivate static func statusFailure(_ code: Int) -> Failure? {
        // E19f: nur Statuscode ins Protokoll, keine Adresse.
        if code != 200 { log.notice("Online: Status \(code)") }
        switch code {
        case 200: return nil
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .status(code)
        }
    }
}

/// Eine Datei-Ladung mit eigener Sitzung (E19c/d). Gemessen 15.11.: Der Abbruch über einen
/// Task-Delegate von `session.download(for:delegate:)` greift nicht (Limit 20 MB, 120 MB kamen an),
/// darum Sitzungs-Delegate. Die Datei wandert schon in `didFinishDownloadingTo` nach `staged`,
/// denn URLSession löscht sie danach. Weiterleitungs-Regel kommt von der Basisklasse.
final class FileDownload: OnlineRedirectGuard, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limit: Int64
    private let staged: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: OnlineFetcher.Failure?
    private var moved = false

    init(limit: Int64, staged: URL) {
        self.limit = limit
        self.staged = staged
    }

    func run(_ request: URLRequest) async throws {
        let session = URLSession(configuration: OnlineFetcher.makeConfiguration(), delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); continuation = c; lock.unlock()
            session.downloadTask(with: request).resume()
        }
    }

    private func fail(_ f: OnlineFetcher.Failure, cancel task: URLSessionTask) {
        lock.lock()
        if failure == nil { failure = f }
        lock.unlock()
        task.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, let f = OnlineFetcher.statusFailure(code) {
            fail(f, cancel: downloadTask)
        } else if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            fail(.tooLarge, cancel: downloadTask)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let ok = (try? FileManager.default.moveItem(at: location, to: staged)) != nil
        lock.lock(); moved = ok; lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        var result = failure
        let didMove = moved
        lock.unlock()
        guard let c else { return }
        if result == nil, error == nil {
            if let http = task.response as? HTTPURLResponse {
                result = OnlineFetcher.statusFailure(http.statusCode)
            } else {
                result = .badData
            }
        }
        if result == nil, error == nil {
            let size = (try? FileManager.default.attributesOfItem(atPath: staged.path))?[.size] as? Int64
            if !didMove || size == nil { result = .badData } else if let size, size > limit { result = .tooLarge }
        }
        if let result { c.resume(throwing: result) } else if let error { c.resume(throwing: error) } else { c.resume() }
    }
}

/// E19a: Weiterleitungen nur auf die Liste. Trägt die Anfrage einen Schlüssel (Kopf bei Pexels,
/// Parameter `key` bei Pixabay), nur auf denselben Server — sonst ginge der Schlüssel mit.
class OnlineRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
