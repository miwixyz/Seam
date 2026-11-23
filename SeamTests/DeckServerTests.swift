import Darwin
import Security
import XCTest
@testable import Seam

/// Stream Deck (E20): Socket-Server. Echte Sockets in einem Wegwerf-Ordner, nie in Michaels Application Support.
final class DeckServerTests: XCTestCase {

    private var dir: URL!
    /// Der Testlauf ist ad hoc signiert, trägt aber die Kennung der App: als „gültiger Peer“ im Test.
    private static let testPeer = #"identifier "dev.mwlr.seam""#

    override func setUp() {
        dir = URL(fileURLWithPath: "/tmp/seamdeck-test-\(UInt32.random(in: 0...999_999))", isDirectory: true)
    }

    override func tearDown() {
        // Aufräumen ohne rm: Socket und Ordner einzeln entfernen.
        unlink(dir.appendingPathComponent(DeckWire.socketName).path)
        rmdir(dir.path)
    }

    private func req(_ s: String) -> SecRequirement {
        var r: SecRequirement?
        precondition(SecRequirementCreateWithString(s as CFString, [], &r) == errSecSuccess)
        return r!
    }

    /// Sammelt, was der Server nach außen gibt.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [DeckWire.Command?] = []
        var values: [DeckWire.Command?] { lock.lock(); defer { lock.unlock() }; return _values }
        func add(_ c: DeckWire.Command?) { lock.lock(); _values.append(c); lock.unlock() }
        var commands: [DeckWire.Command] { values.compactMap { $0 } }
    }

    private func connect(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) } }
        precondition(r == 0, "connect: \(errno)")
        return fd
    }

    private func write(_ fd: Int32, _ obj: [String: Any]) {
        let data = DeckWire.frame(obj)!
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
    }

    /// Wartet bis zu 1 s auf Bytes oder Ende (read liefert 0).
    private func readResult(_ fd: Int32) -> Int {
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 64)
        return read(fd, &buf, buf.count)
    }

    // MARK: Dateisystem

    func testDirectoryIs0700AndSocketIs0600() throws {
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer), parentRequirement: req("anchor apple generic")) { _ in }
        try server.start()
        defer { server.stop() }
        var st = stat()
        XCTAssertEqual(lstat(dir.path, &st), 0)
        XCTAssertEqual(st.st_mode & 0o777, 0o700)
        XCTAssertEqual(lstat(server.socketPath, &st), 0)
        XCTAssertEqual(st.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(st.st_mode & 0o777, 0o600)
        server.stop()
        XCTAssertNotEqual(lstat(server.socketPath, &st), 0, "Socket-Datei beim Ausschalten gelöscht")
    }

    func testPrepareDirectoryRefusesSymlinkAndFixesRights() throws {
        XCTAssertTrue(DeckServer.prepareDirectory(dir))
        XCTAssertEqual(chmod(dir.path, 0o755), 0)
        XCTAssertTrue(DeckServer.prepareDirectory(dir))
        var st = stat()
        lstat(dir.path, &st)
        XCTAssertEqual(st.st_mode & 0o777, 0o700, "zu weite Rechte werden zurückgenommen")
        let link = URL(fileURLWithPath: "/tmp/seamdeck-link-\(UInt32.random(in: 0...999_999))")
        XCTAssertEqual(symlink(dir.path, link.path), 0)
        defer { unlink(link.path) }
        XCTAssertFalse(DeckServer.prepareDirectory(link), "ein Link statt Ordner wird abgelehnt")
    }

    func testStaleFileThatIsNoSocketIsNeverDeleted() throws {
        XCTAssertTrue(DeckServer.prepareDirectory(dir))
        let path = dir.appendingPathComponent(DeckWire.socketName).path
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        XCTAssertFalse(DeckServer.removeStaleSocket(path))
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer), parentRequirement: req("anchor apple generic")) { _ in }
        XCTAssertThrowsError(try server.start())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "fremde Datei bleibt liegen")
    }

    func testRealSocketPathStaysUnderTheLimit() {
        // sun_path fasst 104 Byte inkl. Ende. Benutzername bis 48 Zeichen geht (gemessen 23.11.: Pfad 59 Zeichen bei „mwlr“).
        let name = String(repeating: "a", count: 48)
        let path = "/Users/\(name)/Library/Application Support/Seam/\(DeckWire.socketFolder)/\(DeckWire.socketName)"
        XCTAssertLessThan(path.utf8.count, MemoryLayout.size(ofValue: sockaddr_un().sun_path))
    }

    // MARK: Prüfung vor dem ersten Byte

    func testWrongPeerGetsNothingAndIsClosed() throws {
        let sink = Sink()
        // Der Testlauf ist nicht das Plugin: weder Kennung noch Developer ID passen.
        let server = DeckServer(directory: dir, requirement: req(DeckWire.pluginRequirement),
                                parentRequirement: req(DeckWire.streamDeckRequirement)) { sink.add($0) }
        try server.start()
        defer { server.stop() }
        let fd = connect(server.socketPath)
        defer { close(fd) }
        write(fd, DeckWire.encode(.place(.left)))
        XCTAssertEqual(readResult(fd), 0, "keine Bestätigung, Verbindung zu")
        XCTAssertTrue(sink.commands.isEmpty, "kein Befehl kommt durch")
    }

    func testParentCheckRejectsEvenAValidPeer() throws {
        let sink = Sink()
        // Peer passt (Apple-signierter Testlauf), aber der Elternprozess ist nicht Elgatos Stream Deck.
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer),
                                parentRequirement: req(DeckWire.streamDeckRequirement)) { sink.add($0) }
        try server.start()
        defer { server.stop() }
        let fd = connect(server.socketPath)
        defer { close(fd) }
        write(fd, DeckWire.encode(.seam(dir: 1)))
        XCTAssertEqual(readResult(fd), 0)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    // MARK: Befehle, Grenzen

    func testValidPeerGetsAckAndCommandsAreDelivered() throws {
        let sink = Sink()
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer),
                                parentRequirement: req("anchor apple generic"), parentCheck: { _, _ in errSecSuccess }, onValue: { sink.add($0) })
        try server.start()
        defer { server.stop() }
        let fd = connect(server.socketPath)
        defer { close(fd) }
        XCTAssertGreaterThan(readResult(fd), 0, "Bestätigung kommt")
        write(fd, DeckWire.encode(.hello(version: "0.12.0")))
        write(fd, DeckWire.encode(.seam(dir: -1)))
        write(fd, DeckWire.encode(.place(.maximize)))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(sink.commands, [.hello(version: "0.12.0"), .seam(dir: -1), .place(.maximize)])
    }

    func testFloodIsCappedPerSecondAndInvalidMessageClosesTheConnection() throws {
        let sink = Sink()
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer),
                                parentRequirement: req("anchor apple generic"), perSecond: 5,
                                parentCheck: { _, _ in errSecSuccess }, onValue: { sink.add($0) })
        try server.start()
        defer { server.stop() }
        let fd = connect(server.socketPath)
        defer { close(fd) }
        _ = readResult(fd)
        for _ in 0..<30 { write(fd, DeckWire.encode(.seam(dir: 1))) }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(sink.commands.count, 5, "höchstens perSecond Befehle je Sekunde, der Rest fällt weg")
        // Ungültig (nicht in der Liste) → Verbindung zu.
        write(fd, ["v": 1, "cmd": "wallpaper"])
        XCTAssertEqual(readResult(fd), 0)
    }

    func testOversizedFrameClosesTheConnection() throws {
        let server = DeckServer(directory: dir, requirement: req(Self.testPeer),
                                parentRequirement: req("anchor apple generic"), parentCheck: { _, _ in errSecSuccess }, onValue: { _ in })
        try server.start()
        defer { server.stop() }
        let fd = connect(server.socketPath)
        defer { close(fd) }
        _ = readResult(fd)
        let header = Data([0, 0, 0x10, 0])      // Länge 4096 > 512
        _ = header.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, 4) }
        XCTAssertEqual(readResult(fd), 0)
    }
}
