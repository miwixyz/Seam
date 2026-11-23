import Darwin
import Foundation
import OSLog
import Security

/// Lokaler Socket für das Stream-Deck-Plugin (E20). Aus Gnotchis `PeerSocketServer` übernommen und auf Seams Bedarf verkürzt:
/// ein Client, feste Befehle, keine Drosselung des „letzten Stands“. Alles auf einer eigenen seriellen Warteschlange; nach außen
/// nur `onValue` (geprüft, gedrosselt; `nil` = getrennt). Jede Verbindung wird **vor dem ersten gelesenen Byte** über das
/// Audit-Token der Gegenseite gegen `requirement` und über den Elternprozess gegen `parentRequirement` geprüft. Nie Inhalte
/// ins Protokoll, nur feste Texte.
final class DeckServer: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case directory, staleFile, pathTooLong, socket(Int32)
    }

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "streamdeck")

    let socketPath: String
    private let requirement: SecRequirement
    private let parentRequirement: SecRequirement
    private let perSecond: Int
    /// Prüfung des Elternprozesses; nur im Test ersetzt (der Testlauf hat keinen Stream Deck als Eltern).
    private let parentCheck: @Sendable (Int32, SecRequirement) -> OSStatus
    private let onValue: @Sendable (DeckWire.Command?) -> Void
    private let queue = DispatchQueue(label: "dev.mwlr.seam.deck.socket")

    // Nur auf `queue`:
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientFD: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private var buffer = Data()
    private var windowStart = Date.distantPast
    private var windowCount = 0
    private var dropped = 0

    init(directory: URL, requirement: SecRequirement, parentRequirement: SecRequirement,
         perSecond: Int = DeckWire.maxPerSecond,
         parentCheck: @escaping @Sendable (Int32, SecRequirement) -> OSStatus = DeckServer.checkParent,
         onValue: @escaping @Sendable (DeckWire.Command?) -> Void) {
        socketPath = directory.appendingPathComponent(DeckWire.socketName).path
        self.requirement = requirement
        self.parentRequirement = parentRequirement
        self.perSecond = perSecond
        self.parentCheck = parentCheck
        self.onValue = onValue
    }

    // MARK: Dateisystem

    /// Ordner anlegen bzw. prüfen: echter Ordner (kein Link), gehört uns, Rechte 0700.
    static func prepareDirectory(_ url: URL) -> Bool {
        let path = url.path
        var st = stat()
        if lstat(path, &st) != 0 {
            guard errno == ENOENT, mkdir(path, 0o700) == 0, lstat(path, &st) == 0 else { return false }
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else { return false }
        return chmod(path, 0o700) == 0
    }

    /// Alte Socket-Datei entfernen, aber nur, wenn es wirklich ein Socket ist und uns gehört.
    static func removeStaleSocket(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT }
        guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }

    // MARK: Start/Stopp

    func start() throws(StartError) {
        let dir = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        guard Self.prepareDirectory(dir) else { throw .directory }
        guard Self.removeStaleSocket(socketPath) else { throw .staleFile }
        var addr = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw .pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socket(errno) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 2) == 0 else {
            let e = errno
            close(fd)
            unlink(socketPath)
            throw .socket(e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        queue.sync {
            listenFD = fd
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.resume()
            listenSource = src
        }
        Self.log.notice("Stream Deck: Socket bereit")
    }

    func stop() {
        queue.sync {
            closeClient(reason: nil)
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 { close(listenFD); listenFD = -1; unlink(socketPath) }
        }
    }

    // MARK: Verbindungen (auf queue)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var status = Self.checkPeer(fd, requirement)
            if status == errSecSuccess { status = parentCheck(fd, parentRequirement) }
            guard status == errSecSuccess else {
                close(fd)
                Self.log.error("Stream Deck: Verbindung abgelehnt (OSStatus \(status, privacy: .public))")
                continue
            }
            // Eine geprüfte neue Verbindung ersetzt die alte (höchstens eine).
            closeClient(reason: nil)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            // Vorschau-Nachrichten sind ≈ 7 KB, lokale Sockets puffern ab Werk 8 KB (bei Gnotchi gemessen 17.11.): ein Teil-Schreiben
            // schlösse die Verbindung.
            var sndbuf: Int32 = 65_536
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, socklen_t(MemoryLayout<Int32>.size))
            clientFD = fd
            buffer = Data()
            windowStart = .distantPast
            windowCount = 0
            if let ack = DeckWire.frame(["v": 1, "ok": true]) { _ = ack.withUnsafeBytes { write(fd, $0.baseAddress, ack.count) } }
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readClient() }
            src.resume()
            clientSource = src
            Self.log.notice("Stream Deck: Plugin verbunden")
        }
    }

    /// Audit-Token der Gegenseite → Code → Anforderung. Audit-Token statt PID: kein Wettlauf mit wiederverwendeten Prozessnummern.
    static func checkPeer(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        return SecCodeCheckValidity(code, [], requirement)
    }

    /// Elternprozess des Peers gegen `requirement`. Sonst könnte jedes Programm das echte, signierte Plugin selbst starten und
    /// fernsteuern (gemessen bei Gnotchi 17.11. und für Seam am 23.11., M2). PID aus dem Audit-Token, Eltern-PID aus
    /// `proc_pidinfo`, Elterncode per PID. Restrisiko PID-Wiederverwendung: SECURE-DESIGN E20.
    static func checkParent(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let pid = pid_t(bitPattern: token.val.5)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else {
            return errSecCSGuestInvalid
        }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: info.pbi_ppid)] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private func readClient() {
        var chunk = [UInt8](repeating: 0, count: DeckWire.maxFrame)
        let n = read(clientFD, &chunk, chunk.count)
        if n == 0 { return closeClient(reason: "getrennt") }
        if n < 0 { return errno == EAGAIN ? () : closeClient(reason: "Lesefehler") }
        buffer.append(contentsOf: chunk[0..<n])
        while true {
            switch DeckWire.nextFrame(&buffer) {
            case .needMore:
                return
            case .invalid:
                return closeClient(reason: "ungültiger Rahmen")
            case .message(let payload):
                guard let value = DeckWire.parse(payload) else { return closeClient(reason: "ungültige Nachricht") }
                deliver(value)
            }
        }
    }

    private func closeClient(reason: String?) {
        clientSource?.cancel()
        clientSource = nil
        if clientFD >= 0 { close(clientFD); clientFD = -1 }
        buffer = Data()
        if let reason { Self.log.notice("Stream Deck: \(reason, privacy: .public)") }
        onValue(nil)
    }

    /// An den verbundenen, geprüften Client schreiben. Ohne Client nichts.
    func send(_ object: [String: Any], max: Int = DeckWire.maxFrame) {
        guard let data = DeckWire.frame(object, max: max) else { return }
        queue.async { [weak self] in
            guard let self, clientFD >= 0 else { return }
            let n = data.withUnsafeBytes { write(self.clientFD, $0.baseAddress, data.count) }
            if n != data.count { closeClient(reason: "Schreibfehler") }
        }
    }

    /// Jede Nachricht zählt, aber höchstens `perSecond` je Sekunde; der Rest fällt weg (Zähler, nie der Inhalt).
    private func deliver(_ value: DeckWire.Command) {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 {
            if dropped > 0 { Self.log.notice("Stream Deck: \(self.dropped, privacy: .public) Befehle verworfen (zu schnell)") }
            windowStart = now
            windowCount = 0
            dropped = 0
        }
        windowCount += 1
        if windowCount <= perSecond { onValue(value) } else { dropped += 1 }
    }
}
