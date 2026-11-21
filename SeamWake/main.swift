import Foundation
import IOKit.ps
import OSLog

// SeamWake — Root-Helfer für „Wach bei zugeklapptem Deckel“ (docs/SECURE-DESIGN.md E23).
// Kann genau eins: `/usr/bin/pmset -a disablesleep 1|0`, auf Wunsch von Seam, und schaltet
// selbst wieder ab (Akku, Hitze, Seam weg, Neustart). Kein Netz, keine Shell, keine Pfade von außen.

private let log = Logger(subsystem: "dev.mwlr.seam.wake", category: "wach")

/// Merkt, dass DIESER Helfer den Wachmodus gesetzt hat. Nur dann räumt er nach Neustart/Absturz ab;
/// ein vom Nutzer selbst gesetztes `disablesleep` bleibt unangetastet (E23d).
private let markerURL = URL(fileURLWithPath: "/Library/Application Support/dev.mwlr.seam.wake/aktiv")

/// Prüftakt, solange der Wachmodus an ist.
private let checkInterval: DispatchTimeInterval = .seconds(30)

/// So lange wartet der Helfer, aus und ohne Verbindung, bevor er sich beendet.
private let idleExit: DispatchTimeInterval = .seconds(10)

/// Aller Zustand lebt auf der Hauptwarteschlange; XPC-Aufrufe springen dorthin.
final class Helper: NSObject, NSXPCListenerDelegate, SeamWakeProtocol, @unchecked Sendable {

    private var isOn = false
    private var lastReason: WakeReason = .off
    /// Die Seam-Verbindung, die eingeschaltet hat. Bricht sie weg, schaltet der Helfer ab (E23c).
    /// Als Kennung, nicht als Objekt: die Verbindung gehört der XPC-Warteschlange (Swift 6).
    private var owner: ObjectIdentifier?
    private var timer: DispatchSourceTimer?
    /// Offene Seam-Verbindungen. Aus + keine Verbindung → nach `idleExit` beenden (1.1.1): launchd
    /// startet den Helfer beim nächsten Auftrag neu, aus der dann aktuellen Programmdatei. Sonst lief
    /// nach einem Update der alte Helfer weiter, und Seam lehnte ihn an der Signatur ab.
    private var connections = Set<ObjectIdentifier>()
    private var idleGeneration = 0

    // MARK: - Start

    func start() {
        if FileManager.default.fileExists(atPath: markerURL.path) {
            // Neustart oder Absturz, während der Wachmodus an war: abräumen.
            lastReason = .restart
            // Marker nur nach gemessenem Ausschalten entfernen (code-audit 20.11.): sonst bliebe
            // disablesleep still an, und kein späterer Start würde es noch einmal versuchen.
            if setPmset(false) {
                removeMarker()
                log.notice("Beim Start abgeräumt (Wachmodus war noch von Seam gesetzt)")
            } else {
                lastReason = .pmsetFailed
                log.error("Beim Start NICHT abgeräumt: pmset scheiterte, Marker bleibt")
            }
        }
        scheduleIdleExit()
    }

    /// Beendet den Helfer, wenn er nach `idleExit` immer noch aus ist und keine Verbindung hat.
    /// Exit 0: KeepAlive {SuccessfulExit: false} startet ihn dann nicht sofort neu, erst bei Bedarf.
    private func scheduleIdleExit() {
        guard !isOn, connections.isEmpty else { return }
        idleGeneration += 1
        let generation = idleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + idleExit) { [weak self] in
            guard let self, generation == self.idleGeneration, !self.isOn, self.connections.isEmpty else { return }
            log.notice("Beendet (aus, keine Verbindung)")
            exit(0)
        }
    }

    // MARK: - XPC

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Die Signaturprüfung macht der Listener selbst (setConnectionCodeSigningRequirement).
        connection.exportedInterface = NSXPCInterface(with: SeamWakeProtocol.self)
        connection.exportedObject = self
        let id = ObjectIdentifier(connection)
        DispatchQueue.main.async {
            self.connections.insert(id)
            self.idleGeneration += 1   // laufende Beenden-Wartezeit verwerfen
        }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.lost(id) }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }

    func setAwake(_ on: Bool, reply: @escaping @Sendable (Bool, String) -> Void) {
        let caller = NSXPCConnection.current().map(ObjectIdentifier.init)
        DispatchQueue.main.async {
            if on { self.turnOn(caller: caller) } else { self.turnOff(.off) }
            reply(self.isOn, self.lastReason.rawValue)
        }
    }

    func status(reply: @escaping @Sendable (Bool, String) -> Void) {
        DispatchQueue.main.async {
            self.check()
            reply(self.isOn, self.lastReason.rawValue)
        }
    }

    // MARK: - Ein/Aus

    private func turnOn(caller: ObjectIdentifier?) {
        guard let caller else { return }
        let power = powerState()
        if let reason = WakeGuard.offReason(onBattery: power.onBattery, percent: power.percent,
                                            thermal: ProcessInfo.processInfo.thermalState.rawValue) {
            lastReason = reason
            log.notice("Einschalten abgelehnt: \(reason.rawValue, privacy: .public)")
            return
        }
        writeMarker()   // vor pmset: stirbt der Helfer dazwischen, räumt der Neustart sicher ab
        guard setPmset(true) else {
            removeMarker()
            lastReason = .pmsetFailed
            return
        }
        isOn = true
        owner = caller
        lastReason = .ok
        startTimer()
        log.notice("Wachmodus an")
    }

    private func turnOff(_ reason: WakeReason) {
        timer?.cancel()
        timer = nil
        owner = nil
        if isOn || FileManager.default.fileExists(atPath: markerURL.path) {
            if setPmset(false) { removeMarker() } else { log.error("Ausschalten fehlgeschlagen, Marker bleibt") }
        }
        isOn = false
        lastReason = reason
        log.notice("Wachmodus aus: \(reason.rawValue, privacy: .public)")
    }

    private func lost(_ connection: ObjectIdentifier) {
        // Die einschaltende Verbindung ist weg (Seam beendet, abgestürzt).
        connections.remove(connection)
        if isOn, connection == owner { turnOff(.clientGone) }
        scheduleIdleExit()
    }

    // MARK: - Überwachung

    private func startTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
    }

    private func check() {
        guard isOn else { return }
        let power = powerState()
        if let reason = WakeGuard.offReason(onBattery: power.onBattery, percent: power.percent,
                                            thermal: ProcessInfo.processInfo.thermalState.rawValue) {
            turnOff(reason)
            return
        }
        // Von außen zurückgesetzt (z. B. `sudo pmset -a disablesleep 0`): Zustand übernehmen.
        if readSleepDisabled() == false {
            timer?.cancel()
            timer = nil
            owner = nil
            removeMarker()
            isOn = false
            lastReason = .external
            log.notice("Von außen ausgeschaltet")
        }
    }

    // MARK: - System

    /// Fester Befehl, feste Argumente, keine Shell. Danach gemessen (Regel 7).
    private func setPmset(_ on: Bool) -> Bool {
        guard run(["-a", "disablesleep", on ? "1" : "0"]) != nil else { return false }
        let ok = readSleepDisabled() == on
        if !ok { log.error("pmset gesetzt, Messung widerspricht (Soll \(on, privacy: .public))") }
        return ok
    }

    private func readSleepDisabled() -> Bool? {
        run(["-g"]).flatMap(WakeGuard.sleepDisabled(inPmsetOutput:))
    }

    private func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()   // vor dem Warten lesen
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                log.error("pmset Exit \(p.terminationStatus, privacy: .public)")
                return nil
            }
            return String(bytes: data, encoding: .utf8) ?? ""
        } catch {
            log.error("pmset nicht startbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func powerState() -> (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (false, nil)   // kein Akku (Mac mini): nur die Hitze zählt
        }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = source == kIOPSBatteryPowerValue
        for item in list {
            guard let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int,
                  max > 0 else { continue }
            return (onBattery, cur * 100 / max)
        }
        return (onBattery, nil)
    }

    private func writeMarker() {
        let dir = markerURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
            try Data().write(to: markerURL)
        } catch {
            log.error("Marker nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }
}

let helper = Helper()
helper.start()
let listener = NSXPCListener(machServiceName: WakeXPC.machService)
listener.setConnectionCodeSigningRequirement(WakeXPC.clientRequirement)
listener.delegate = helper
listener.resume()
log.notice("SeamWake bereit")
dispatchMain()
