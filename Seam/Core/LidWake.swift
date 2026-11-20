import AppKit
import OSLog
import ServiceManagement

/// „Wach bei zugeklapptem Deckel“ (E23). Seam setzt nichts selbst: Es bittet den Root-Helfer
/// SeamWake per XPC, und der schaltet bei Akku, Hitze oder Seams Ende von allein ab.
@MainActor
@Observable
final class LidWake {

    enum State: Equatable {
        case off, on
        /// Helfer registriert, aber unter Anmeldeobjekte noch nicht erlaubt.
        case needsApproval
        case failed(String)
    }

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "wach")
    /// Eine Instanz je Seam: Die XPC-Verbindung ist zugleich das Lebenszeichen für den Helfer.
    static let shared = LidWake()

    private(set) var state: State = .off
    /// Warum der Helfer zuletzt von allein abgeschaltet hat; nil = nichts zu melden.
    private(set) var notice: String?

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: WakeXPC.plistName)

    var isOn: Bool { state == .on }

    func toggle() {
        if isOn { turnOff() } else { turnOn() }
    }

    func dismissNotice() { notice = nil }

    func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    func turnOn() {
        notice = nil
        guard ensureRegistered() else { return }
        send(true)
    }

    func turnOff() { send(false) }

    // MARK: - Registrierung

    /// true = Helfer läuft und darf. Sonst Zustand gesetzt und, wo nötig, die Freigabe geöffnet.
    private func ensureRegistered() -> Bool {
        if service.status == .enabled { return true }
        if service.status != .requiresApproval {
            do {
                try service.register()
            } catch {
                Self.log.error("Helfer nicht registriert: \(error.localizedDescription, privacy: .public)")
            }
        }
        switch service.status {
        case .enabled:
            return true
        case .requiresApproval:
            state = .needsApproval
            openApproval()
        default:
            state = .failed("Helfer ließ sich nicht einrichten")
        }
        return false
    }

    // MARK: - XPC

    private func proxy() -> SeamWakeProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: WakeXPC.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: SeamWakeProtocol.self)
            c.setCodeSigningRequirement(WakeXPC.helperRequirement)
            let lost: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.connectionLost() }
            }
            c.invalidationHandler = lost
            c.interruptionHandler = lost
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            let text = error.localizedDescription
            Task { @MainActor in self?.fail(text) }
        } as? SeamWakeProtocol
    }

    private func send(_ on: Bool) {
        proxy()?.setAwake(on) { [weak self] isOn, reason in
            Task { @MainActor in self?.apply(isOn: isOn, reason: reason, requested: on) }
        }
    }

    private func refresh() {
        proxy()?.status { [weak self] isOn, reason in
            Task { @MainActor in self?.apply(isOn: isOn, reason: reason, requested: nil) }
        }
    }

    private func apply(isOn: Bool, reason: String, requested: Bool?) {
        let wasOn = state == .on
        state = isOn ? .on : .off
        let why = WakeReason(rawValue: reason)
        if !isOn, requested == true || wasOn, let text = Self.text(for: why) { notice = text }
        Self.log.notice("Wachmodus \(isOn ? "an" : "aus", privacy: .public) (\(reason, privacy: .public))")
        if isOn { startPolling() } else { stopPolling() }
    }

    private func connectionLost() {
        connection = nil
        if state == .on {
            // Helfer neu gestartet oder weg: Er räumt selbst ab, also gilt aus.
            state = .off
            notice = "Helfer neu gestartet: Wachmodus ist aus"
            stopPolling()
        }
    }

    private func fail(_ text: String) {
        Self.log.error("XPC: \(text, privacy: .public)")
        connection?.invalidate()
        connection = nil
        state = .failed("Helfer antwortet nicht")
        stopPolling()
    }

    /// Solange an: alle 30 s fragen, damit Seam eine Abschaltung des Helfers sofort zeigt.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// Getestet. Hinweistext für eine Abschaltung, die der Nutzer nicht selbst ausgelöst hat.
    nonisolated static func text(for reason: WakeReason?) -> String? {
        switch reason {
        case .battery: "Akku unter \(WakeGuard.minimumBattery) %: Wachmodus ist aus"
        case .heat: "Mac zu warm: Wachmodus ist aus"
        case .clientGone, .restart: "Wachmodus wurde zurückgesetzt"
        case .external: "Wachmodus von außen ausgeschaltet (pmset)"
        case .pmsetFailed: "pmset hat nicht reagiert: Wachmodus ist aus"
        case .ok, .off, nil: nil
        }
    }
}
