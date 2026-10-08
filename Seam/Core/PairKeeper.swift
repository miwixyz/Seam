import AppKit
import OSLog

/// Geteiltes Paar folgt dem Nutzer (docs/SECURE-DESIGN.md E12, Idee aus WindowGlue).
///
/// - Wird ein Fenster eines Paars nach vorn geholt (angeklickt, App aktiviert), hebt Seam
///   den Partner mit `AXRaise` an. Ohne App-Aktivierung, ohne Fokuswechsel: gemessen
///   09.10., `AXRaise` allein hebt das Fenster einer nicht aktiven App über ein
///   verdeckendes Fenster, die vordere App bleibt vorn.
/// - Wird eines minimiert oder wiederhergestellt, folgt der Partner.
/// - Das Paar löst sich auf, wenn ein Fenster verschwindet, die App endet oder
///   ausgeblendet wird, oder die beiden nicht mehr Kante an Kante stehen.
///
/// Paare entstehen nur durch ⌃⌥S (`WindowActions.split`). Nur im Speicher (E10).
@MainActor
final class PairKeeper {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "paar")

    private let prefs: Preferences
    private var book = PairBook<AXWindow>()
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    /// Fenster, auf die Seam gerade selbst gewirkt hat. Deren Meldungen werden kurz
    /// ignoriert, sonst schaukeln sich Paare auf (E6/E12).
    private var echo: [AXWindow: Date] = [:]
    /// Ab Anlass UND noch einmal ab Ende der Abfolge. Gemessen 09.10. (Finder-Paar):
    /// Nur ab Anlass gesetzt lief die Abfolge (Anheben nach 150 + 400 ms) samt verspäteter
    /// Fokusmeldung über die Sperre hinaus → 6 Runden im Takt von ~0,58 s, dann zufälliges Ende.
    private static let echoWindow: TimeInterval = 0.6
    /// Raise/Minimieren auf eigener Warteschlange: eine hängende App blockiert nicht (E12 D).
    private let writer = NeighborWriter()

    /// Nach dem Anheben eines Partners (z. B. Abdunklung neu einsortieren, E13).
    var onRaised: (() -> Void)?

    init(prefs: Preferences) { self.prefs = prefs }

    func partner(of w: AXWindow) -> AXWindow? { book.partner(of: w) }

    // MARK: - Ein/Aus

    func start() {
        guard workspaceTokens.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ handle: @escaping @MainActor (pid_t) -> Void) {
            workspaceTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { handle(pid) }
            })
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] pid in self?.appActivated(pid) }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] pid in self?.dissolveApp(pid, "App beendet") }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] pid in self?.dissolveApp(pid, "App ausgeblendet") }
    }

    func stop() {
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceTokens = []
        book.removeAll()
        syncObservers()
    }

    // MARK: - Paare

    /// ⌃⌥S hat zwei Fenster nebeneinander gesetzt.
    func pair(_ a: AXWindow, _ b: AXWindow) {
        guard prefs.keepPairs, a != b else { return }
        book.add(a, b)
        syncObservers()
        Self.log.notice("Paar gebildet: \(Self.app(a), privacy: .public) + \(Self.app(b), privacy: .public), \(self.book.pairs.count) Paar(e)")
    }

    /// Schalter „Geteilte Fenster bleiben zusammen“ geändert.
    func applySetting() {
        if !prefs.keepPairs { book.removeAll(); syncObservers() }
    }

    private func dissolve(_ w: AXWindow, _ reason: String) {
        guard let p = book.remove(containing: w) else { return }
        syncObservers()
        Self.log.notice("Paar aufgelöst (\(reason, privacy: .public)): \(Self.app(w), privacy: .public) + \(Self.app(p), privacy: .public)")
    }

    private func dissolveApp(_ pid: pid_t, _ reason: String) {
        let before = book.pairs.count
        book.removeAll { $0.pid == pid }
        guard book.pairs.count != before else { return }
        syncObservers()
        Self.log.notice("Paar aufgelöst (\(reason, privacy: .public)): pid \(pid)")
    }

    // MARK: - Anlässe

    private func appActivated(_ pid: pid_t) {
        guard !book.isEmpty, book.windows.contains(where: { $0.pid == pid }),
              let w = AXAccess.focusedWindow(of: pid) else { return }
        broughtForward(w)
    }

    /// Ein Paarfenster ist nach vorn gekommen: Partner anheben, falls beide noch Kante an Kante stehen.
    private func broughtForward(_ w: AXWindow) {
        guard !isEcho(w), let partner = book.partner(of: w) else { return }
        guard !w.isMinimized, !partner.isMinimized else { return }
        guard let wf = w.frame, let pf = partner.frame,
              Geometry.stillSideBySide(wf, pf, gap: CGFloat(prefs.gap)) else {
            dissolve(w, "nicht mehr nebeneinander")
            return
        }
        markEcho(w, partner)
        let sameApp = w.pid == partner.pid
        let log = Self.log, name = Self.app(partner)
        writer.run {
            // Nicht sofort: Die Meldung „App aktiviert“ kommt, BEVOR macOS die Fenster neu
            // stapelt. Gemessen 09.10. (Fensterliste alle 20 ms): Seam hob den Partner an,
            // 26 ms später sortierte die Aktivierung neu und er lag wieder unter dem Finder.
            // Darum nach 150 ms anheben und nach 400 ms noch einmal (beides innerhalb der
            // Echo-Sperre von 0,5 s).
            var rc = AXError.success
            for pause: useconds_t in [150_000, 250_000] {
                usleep(pause)
                rc = partner.perform(.raise)
                // Gleiche App: Anheben des Partners macht ihn zum Hauptfenster. Das angeklickte
                // Fenster danach wieder obenauf, damit der Fokus bleibt, wo der Nutzer klickte.
                if sameApp { w.perform(.raise) }
            }
            log.notice("Partner angehoben: \(name, privacy: .public) rc \(rc.rawValue)\(sameApp ? " (gleiche App)" : "", privacy: .public)")
            Task { @MainActor [weak self] in
                self?.markEcho(w, partner)
                self?.onRaised?()
            }
        }
    }

    private func minimizedChanged(_ w: AXWindow, minimized: Bool) {
        guard !isEcho(w), let partner = book.partner(of: w) else { return }
        markEcho(w, partner)
        let log = Self.log, name = Self.app(partner)
        writer.run {
            guard partner.isMinimized != minimized else { return }
            partner.setMinimized(minimized)
            log.notice("Partner \(minimized ? "minimiert" : "wiederhergestellt", privacy: .public): \(name, privacy: .public)")
            Task { @MainActor [weak self] in self?.markEcho(w, partner) }
        }
    }

    // MARK: - Rückkopplung

    private func markEcho(_ ws: AXWindow...) {
        let until = Date().addingTimeInterval(Self.echoWindow)
        for w in ws { echo[w] = until }
    }

    private func isEcho(_ w: AXWindow) -> Bool {
        let now = Date()
        echo = echo.filter { $0.value > now }
        return echo[w] != nil
    }

    // MARK: - Beobachter (nur für Apps mit Paarfenstern)

    private func syncObservers() {
        // Alle bisherigen abmelden und neu aufbauen: wenige Fenster, und so hängt nie eine
        // alte Fenster-Meldung an einem aufgelösten Paar.
        let retired = Array(observers.values)
        for obs in retired {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observers = [:]
        for pid in Set(book.windows.map(\.pid)) {
            observers[pid] = makeObserver(pid)
        }
        // Aufruf kommt oft aus einem AX-Rückruf (z. B. „Fenster geschlossen“). Den Beobachter,
        // der gerade zurückruft, erst nach diesem Durchlauf freigeben (rafter-code-review 09.10.).
        DispatchQueue.main.async { withExtendedLifetime(retired) {} }
    }

    private func makeObserver(_ pid: pid_t) -> AXObserver? {
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, element, note, refcon in
            guard let refcon else { return }
            let name = note as String
            MainActor.assumeIsolated {
                Unmanaged<PairKeeper>.fromOpaque(refcon).takeUnretainedValue().received(name, element)
            }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(obs, app, kAXFocusedWindowChangedNotification as CFString, me)
        for w in book.windows where w.pid == pid {
            for n in [kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(obs, w.element, n as CFString, me)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        return obs
    }

    private func received(_ name: String, _ element: AXUIElement) {
        let w = AXWindow(element)
        switch name {
        case kAXFocusedWindowChangedNotification: broughtForward(w)
        case kAXWindowMiniaturizedNotification: minimizedChanged(w, minimized: true)
        case kAXWindowDeminiaturizedNotification: minimizedChanged(w, minimized: false)
        case kAXUIElementDestroyedNotification: dissolve(w, "Fenster geschlossen")
        default: break
        }
    }

    private static func app(_ w: AXWindow) -> String {
        NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "\(w.pid)"
    }
}
