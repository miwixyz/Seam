import Network
import XCTest
@testable import Seam

/// `FileDownload` gegen einen echten Server auf 127.0.0.1 (Host-Liste greift erst in
/// `OnlineFetcher.download`). Gemessen 15.11.: Ein Abbruch über Task-Delegate griff nicht, deshalb
/// hier der echte Weg mit Größe angekündigt, Größe nicht angekündigt, falschem Status.
final class FileDownloadTests: XCTestCase {

    /// Winziger HTTP-Server: antwortet jeder Verbindung mit `head` und dann `bodyBytes` Byte.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "FileDownloadTests.server")
        private let head: String
        private let bodyBytes: Int
        private let chunk = Data(repeating: 0x41, count: 64 * 1024)
        private let lock = NSLock()
        private var _sent = 0

        var port: UInt16 { listener.port?.rawValue ?? 0 }
        /// Wie viel Körper der Server wirklich losgeschickt hat (beweist den frühen Abbruch).
        var sent: Int { lock.lock(); defer { lock.unlock() }; return _sent }

        init(head: String, bodyBytes: Int) throws {
            self.head = head
            self.bodyBytes = bodyBytes
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success else { throw XCTSkip("Loopback-Server nicht gestartet") }
        }

        deinit { listener.cancel() }

        private func accept(_ conn: NWConnection) {
            conn.start(queue: queue)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
                guard let self else { return }
                conn.send(content: Data(self.head.utf8), completion: .contentProcessed { _ in })
                self.pump(conn, left: self.bodyBytes)
            }
        }

        private func pump(_ conn: NWConnection, left: Int) {
            guard left > 0 else { conn.cancel(); return }
            let n = min(left, chunk.count)
            conn.send(content: chunk.prefix(n), completion: .contentProcessed { [weak self] err in
                guard let self else { return }
                if err == nil {
                    self.lock.lock(); self._sent += n; self.lock.unlock()
                    self.queue.async { self.pump(conn, left: left - n) }
                } else {
                    conn.cancel()
                }
            })
        }
    }

    private func staged() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("seam-test-\(UUID().uuidString)")
    }

    private func request(_ server: Server) -> URLRequest {
        URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/x")!)
    }

    func testDownloadsFileUnderLimit() async throws {
        let size = 3 * 1024 * 1024
        let server = try Server(head: "HTTP/1.1 200 OK\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n", bodyBytes: size)
        let target = staged()
        defer { try? FileManager.default.removeItem(at: target) }
        try await FileDownload(limit: Int64(size * 2), staged: target).run(request(server))
        let got = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int
        XCTAssertEqual(got, size)
    }

    func testAbortsWhenAnnouncedSizeExceedsLimit() async throws {
        let server = try Server(head: "HTTP/1.1 200 OK\r\nContent-Length: 50000000\r\nConnection: close\r\n\r\n", bodyBytes: 50_000_000)
        let target = staged()
        defer { try? FileManager.default.removeItem(at: target) }
        do {
            try await FileDownload(limit: 1_000_000, staged: target).run(request(server))
            XCTFail("Hätte abbrechen müssen")
        } catch let e as OnlineFetcher.Failure {
            XCTAssertEqual(e, .tooLarge)
        }
    }

    func testAbortsWhenUnannouncedBodyExceedsLimit() async throws {
        // Kein Content-Length: Server schickt bis zum Schließen, Seam muss selbst zählen.
        let server = try Server(head: "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n", bodyBytes: 50_000_000)
        let target = staged()
        defer { try? FileManager.default.removeItem(at: target) }
        do {
            try await FileDownload(limit: 1_000_000, staged: target).run(request(server))
            XCTFail("Hätte abbrechen müssen")
        } catch let e as OnlineFetcher.Failure {
            XCTAssertEqual(e, .tooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "Teil-Datei darf nicht bleiben")
        // Früh abgebrochen, nicht erst nach dem letzten Byte: höchstens ein Bruchteil der 50 MB.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThan(server.sent, 25_000_000, "Download lief weiter, obwohl das Limit überschritten war")
    }

    func testRejectsNon200Status() async throws {
        let server = try Server(head: "HTTP/1.1 404 Not Found\r\nContent-Length: 5000000\r\nConnection: close\r\n\r\n", bodyBytes: 5_000_000)
        let target = staged()
        defer { try? FileManager.default.removeItem(at: target) }
        do {
            try await FileDownload(limit: 60_000_000, staged: target).run(request(server))
            XCTFail("Hätte abbrechen müssen")
        } catch let e as OnlineFetcher.Failure {
            XCTAssertEqual(e, .status(404))
        }
    }
}
