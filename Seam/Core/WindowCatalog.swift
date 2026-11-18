import AppKit
import OSLog
import ScreenCaptureKit

/// Vorschaugröße für Umschalter und Dock-Vorschau (E21).
enum PreviewSize: String, CaseIterable, Sendable {
    case small, normal, large, xlarge

    var label: String {
        switch self {
        case .small: "Klein"
        case .normal: "Normal"
        case .large: "Groß"
        case .xlarge: "Sehr groß"
        }
    }

    /// Breite einer Kachel in Punkt; Höhe des Bildes = 0,62 × Breite.
    var tileWidth: CGFloat {
        switch self {
        case .small: 150
        case .normal: 210
        case .large: 280
        case .xlarge: 370
        }
    }
}

/// Ein Fenster für Umschalter und Dock-Vorschau. Titel ist fremder Text (E21c).
struct CatalogWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    /// Bereinigt (E21c); leer, wenn die Freigabe fehlt oder das Fenster keinen hat.
    let title: String
    /// AX-Koordinaten (Ursprung oben links), wie die Fensterliste des Systems.
    let frame: CGRect
    /// Auf einem gerade sichtbaren Schreibtisch. false = anderer Space oder minimiert.
    let onScreen: Bool

    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
}

/// `SCWindow` ist nicht als Sendable markiert; es wird nur gelesen (Filter bauen) — daher unchecked.
private struct SCWindowBox: @unchecked Sendable {
    let window: SCWindow

    /// Mit echtem Zeitlimit: Eine Task-Gruppe wartet beim Verlassen auf ALLE Kinder, eine hängende
    /// Erfassung hielte sie also fest (code-audit 18.11.). Darum ungebundene Tasks + einmaliges Fortsetzen.
    func capture(width: Int, height: Int, timeout: Duration) async -> CGImage? {
        let once = ResumeOnce()
        return await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            Task {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = width
                config.height = height
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                once.resume(cont, with: SendableImage(image: image))
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(cont, with: SendableImage(image: nil))
            }
        }
    }
}

/// CGImage ist unveränderlich; die Hülle trägt es über die Task-Grenze.
private struct SendableImage: @unchecked Sendable { let image: CGImage? }

/// Setzt eine Fortsetzung genau einmal fort (Erfassung oder Zeitlimit, wer zuerst kommt).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ cont: CheckedContinuation<CGImage?, Never>, with value: SendableImage) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { cont.resume(returning: value.image) }
    }
}

/// Fenster auflisten, Vorschaubilder erfassen, ein Fenster nach vorn holen (E21a/b/f).
@MainActor
enum WindowCatalog {

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "umschalter")
    static let maxWindows = 60
    nonisolated static let maxTitle = 200

    /// Bildschirmaufnahme erteilt? Lokale Abfrage, kein Dialog.
    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// Fragt die Freigabe an (E21a: nur, wenn der Nutzer eine Funktion einschaltet).
    static func requestCapture() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    }

    static func openCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Titel bereinigen (E21c): Steuerzeichen raus, Leerraum außen weg, gekürzt.
    nonisolated static func sanitize(_ s: String?) -> String {
        let cleaned = String((s ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxTitle))
    }

    // MARK: Liste

    /// Normale App-Fenster in der Reihenfolge der Nutzung: Apps nach `appOrder` (zuletzt aktiv zuerst),
    /// innerhalb einer App nach der Stapelfolge. Gemessen 18.11.: Die Stapelfolge des Systems allein
    /// taugt dafür nicht — unsichtbare 500×500-Hilfsfenster und Fenster anderer Schreibtische stehen
    /// darin vor dem vordersten sichtbaren Fenster (schnelles ⌘Tab sprang immer zu Notizen).
    /// Titel aus ScreenCaptureKit, Lage immer aus der Fensterliste (gleiche Koordinaten wie die
    /// Bedienungshilfen, damit das Fenster beim Wechseln wiedergefunden wird). `pid` = nur diese App.
    static func windows(pid: pid_t? = nil, currentSpaceOnly: Bool, appOrder: [pid_t] = []) async -> [CatalogWindow] {
        let infos = systemWindows()
        var titles: [CGWindowID: String] = [:]
        if canCapture, let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            scWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            for w in content.windows { titles[w.windowID] = sanitize(w.title) }
        }
        let own = ProcessInfo.processInfo.processIdentifier
        var minimizedFrames: [pid_t: [CGRect]] = [:]
        let candidates = infos.filter { i in
            i.pid != own && (pid == nil || i.pid == pid)
                && i.frame.width >= 160 && i.frame.height >= 120              // Werkzeugleisten, Popups raus
                && WindowList.isRegularApp(i.pid)
                && (!currentSpaceOnly || i.onScreen)
        }
        let list: [CatalogWindow] = candidates.compactMap { i in
            // Echt = sichtbar, auf einem Schreibtisch oder minimiert. Scheinfenster liegen auf keinem.
            if !i.onScreen && SpaceReader.spaceIDs(ofWindow: i.id).isEmpty {
                if minimizedFrames[i.pid] == nil {
                    minimizedFrames[i.pid] = AXAccess.allWindows(of: i.pid).filter(\.isMinimized).compactMap(\.frame)
                }
                guard minimizedFrames[i.pid]?.contains(where: { Geometry.close($0, i.frame) }) == true else { return nil }
            }
            return CatalogWindow(id: i.id, pid: i.pid, title: titles[i.id] ?? "", frame: i.frame, onScreen: i.onScreen)
        }
        let stack = Dictionary(uniqueKeysWithValues: infos.enumerated().map { ($1.id, $0) })
        let result = Array(order(list, stack: stack, appOrder: appOrder).prefix(maxWindows))
        let scope = pid.map { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier ?? "pid \($0)" } ?? "alle Apps"
        log.notice("Fenster gelistet: \(result.count, privacy: .public) (\(scope, privacy: .public)), Freigabe Bildschirmaufnahme: \(canCapture, privacy: .public)")
        return result
    }

    /// Reihenfolge (getestet): sichtbare Fenster zählen vor unsichtbaren derselben App; Apps nach
    /// `appOrder`, unbekannte Apps danach in Stapelfolge.
    nonisolated static func order(_ list: [CatalogWindow], stack: [CGWindowID: Int], appOrder: [pid_t]) -> [CatalogWindow] {
        let rank = Dictionary(appOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        // Apps, die Seam noch nicht aktiv gesehen hat (z. B. direkt nach dem Start): nach ihrem vordersten
        // SICHTBAREN Fenster. Unsichtbare Fenster stehen in der Stapelfolge an beliebiger Stelle (gemessen
        // 18.11.: ein verdecktes Notizen-Fenster vor dem vordersten sichtbaren). Ohne sichtbares Fenster ans Ende.
        var firstSeen: [pid_t: Int] = [:]
        for w in list where w.onScreen { firstSeen[w.pid] = min(firstSeen[w.pid] ?? .max, stack[w.id] ?? .max) }
        func key(_ w: CatalogWindow) -> [Int] {
            [rank[w.pid] ?? appOrder.count, firstSeen[w.pid] ?? .max, w.onScreen ? 0 : 1, stack[w.id] ?? .max]
        }
        return list.sorted { key($0).lexicographicallyPrecedes(key($1)) }
    }

    private struct SystemWindow {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
        let onScreen: Bool
    }

    /// Fensterliste des Systems, Stapelfolge, nur Ebene 0, alle Spaces. Nur Nummer, Prozess, Lage, sichtbar (E13).
    private static func systemWindows() -> [SystemWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return raw.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return nil }
            return SystemWindow(id: CGWindowID(n), pid: pid, frame: bounds,
                                onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) == true)
        }
    }

    // MARK: Bilder (E21b: nur Arbeitsspeicher)

    private static var scWindows: [CGWindowID: SCWindow] = [:]
    private static var cache: [CGWindowID: NSImage] = [:]
    private static var cacheOrder: [CGWindowID] = []
    static let maxCached = 120
    static let maxEdge: CGFloat = 640

    static func cachedImage(_ id: CGWindowID) -> NSImage? { cache[id] }

    /// Bilder für die Liste erfassen, höchstens 4 gleichzeitig, je Fenster höchstens 1 s.
    /// `update` bekommt jedes fertige Bild sofort (die Kacheln füllen sich nach und nach).
    /// Minimierte Fenster liefern kein frisches Bild → das zuletzt erfasste bleibt stehen.
    static func captureImages(for list: [CatalogWindow], update: @escaping @MainActor (CGWindowID, NSImage) -> Void) async {
        guard canCapture else { return }
        let targets = list.compactMap { w in scWindows[w.id].map { (w, $0) } }
        var index = 0
        while index < targets.count {
            let batch = targets[index..<min(index + 4, targets.count)]
            index += batch.count
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for (w, sc) in batch where w.onScreen || cache[w.id] == nil {
                    let scale = min(1, maxEdge / max(w.frame.width, w.frame.height, 1))
                    let width = max(1, Int(w.frame.width * scale * 2))
                    let height = max(1, Int(w.frame.height * scale * 2))
                    let box = SCWindowBox(window: sc)
                    let id = w.id
                    group.addTask { (id, await box.capture(width: width, height: height, timeout: .seconds(1))) }
                }
                for await (id, image) in group {
                    guard let image else { continue }
                    let ns = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
                    store(ns, for: id)
                    update(id, ns)
                }
            }
        }
    }

    private static func store(_ image: NSImage, for id: CGWindowID) {
        if cache[id] == nil { cacheOrder.append(id) }
        cache[id] = image
        while cacheOrder.count > maxCached { cache[cacheOrder.removeFirst()] = nil }
    }

    /// Beim Ausschalten (E21b).
    static func clearCache() {
        cache = [:]
        cacheOrder = []
        scWindows = [:]
    }

    // MARK: Nach vorn holen (E21f)

    /// App aktivieren, das passende Fenster wiederherstellen und anheben. Zuordnung über Lage
    /// (Fensterliste und Bedienungshilfen teilen keine Nummer). Liegt das Fenster auf einem anderen
    /// Space, wechselt macOS beim Aktivieren dorthin.
    static func activate(_ w: CatalogWindow) {
        guard let app = w.app else { return }
        let candidates = AXAccess.allWindows(of: w.pid)
        let target = candidates.first { $0.frame.map { Geometry.close($0, w.frame) } ?? false }
            ?? (candidates.count == 1 ? candidates.first : nil)
        if let target, target.isMinimized { target.setMinimized(false) }
        if app.isHidden { app.unhide() }     // ausgeblendete App (⌘H): sonst bliebe das Fenster unsichtbar
        app.activate()
        target?.perform(.raise)
        let id = app.bundleIdentifier ?? "pid \(w.pid)"
        // Messpunkt: Kommt die App wirklich nach vorn? (Seam ist selbst nicht aktiv, macOS kann
        // das Aktivieren dann ablehnen.) Bei Fehlschlag über die Bedienungshilfen nachhelfen.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            var front = NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid
            if !front {
                AXAccess.setFrontmost(w.pid)
                target?.perform(.raise)
                try? await Task.sleep(for: .milliseconds(150))
                front = NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid
            }
            log.notice("Nach vorn: \(id, privacy: .public), Fenster gefunden: \(target != nil, privacy: .public), App vorn: \(front, privacy: .public)")
        }
    }
}
