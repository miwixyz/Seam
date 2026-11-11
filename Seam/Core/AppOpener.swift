import AppKit
import OSLog

// „Alles öffnen“ (docs/SECURE-DESIGN.md E17k, Michael 11.11.): Apps des Layouts, die kein Fenster
// haben, öffnen und warten, bis ihre Fenster stehen. Danach räumt die Engine wie gewohnt auf.
// Nur auf Knopfdruck, nie automatisch.

enum AppOpener {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "layouts")
    /// So lange auf ruhige Fenster warten.
    static let windowWait: TimeInterval = 30
    /// Rahmen so lange unverändert = Fenster steht.
    static let settle: TimeInterval = 1

    /// Welche Apps fehlen: im Plan als „kein Fenster“ ausgelassen. Einmal je App, sortiert, begrenzt.
    static func missing(in plan: DeskPlan) -> [String] {
        Array(Set(plan.skipped.filter { $0.reason == .notRunning }.map(\.bundleID)).sorted().prefix(DeskLayouts.maxEntries))
    }

    /// Fenster einer App für den Vergleich „steht still?“ (alle, auch „auf allen Schreibtischen“), sortiert.
    static func frames(of id: String, in windows: [LiveWindow]) -> [CGRect] {
        windows.filter { $0.bundleID == id && !$0.spaceIDs.isEmpty }.map(\.frame)
            .sorted { ($0.minX, $0.minY, $0.width, $0.height) < ($1.minX, $1.minY, $1.width, $1.height) }
    }

    /// Seit wann stehen die Fenster still? Leer → noch kein Fenster (nil); gleich → bisheriger
    /// Zeitpunkt; anders → jetzt.
    static func stillSince(previous: [CGRect]?, current: [CGRect], since: Date?, now: Date) -> Date? {
        guard !current.isEmpty else { return nil }
        return previous == current ? (since ?? now) : now
    }

    /// Öffnet die Apps (ohne Argumente, ohne sie nach vorn zu holen) und wartet auf ruhige Fenster.
    /// Rückgabe: Apps, die macOS nicht kennt (`notFound`) oder nicht starten konnte (`failed`).
    @MainActor
    static func open(_ ids: [String]) async -> (notFound: [String], failed: [String]) {
        var notFound: [String] = []
        var failed: [String] = []
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        for id in ids {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                notFound.append(id)
                continue
            }
            // rafter-code-review 11.11., Fund 1: Startfehler nicht still verschlucken (Vault-Regel 7).
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            } catch {
                failed.append(id)
                log.error("Alles öffnen: Start fehlgeschlagen, Code \((error as NSError).code)")
            }
        }
        let opened = ids.filter { !notFound.contains($0) && !failed.contains($0) }
        let ready = await waitForWindows(opened)
        log.notice("Alles öffnen: \(opened.count) Apps geöffnet, \(ready) mit ruhigem Fenster, \(notFound.count) nicht gefunden, \(failed.count) fehlgeschlagen")
        return (notFound, failed)
    }

    /// Bis jede App ein Fenster hat, das `settle` lang stillsteht (höchstens `windowWait`).
    /// Rückgabe: Zahl der Apps, deren Fenster stehen.
    @MainActor
    private static func waitForWindows(_ ids: [String]) async -> Int {
        let end = Date().addingTimeInterval(windowWait)
        var previous: [String: [CGRect]] = [:]
        var since: [String: Date] = [:]
        var ready = 0
        while Date() < end {
            let windows = DeskLayouts.liveWindows()
            let now = Date()
            for id in ids {
                let f = frames(of: id, in: windows)
                since[id] = stillSince(previous: previous[id], current: f, since: since[id], now: now)
                previous[id] = f
            }
            ready = ids.filter { since[$0].map { now.timeIntervalSince($0) >= settle } ?? false }.count
            if ready == ids.count { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return ready
    }
}
