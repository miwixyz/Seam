import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

/// Einziger Zugang zu den Bedienungshilfen.
///
/// **Positivliste (docs/SECURE-DESIGN.md E3):** Seam liest von fremden Apps nur
/// Struktur, Rolle, Lage und Größe, nie Titel oder Inhalte. Andere Dateien
/// dürfen `AXUIElementCopyAttributeValue` nicht aufrufen; das prüft die
/// SwiftLint-Regel `ax_nur_ueber_allowlist`.
enum AXAttribute: String, CaseIterable {
    case role = "AXRole"
    case subrole = "AXSubrole"
    case position = "AXPosition"
    case size = "AXSize"
    case minimized = "AXMinimized"
    case fullScreen = "AXFullScreen"
    case windows = "AXWindows"
    case focusedApplication = "AXFocusedApplication"
    case focusedWindow = "AXFocusedWindow"
    /// E17a: Fenster, zu dem ein Element unter dem Griffpunkt gehört (nur dort gelesen).
    case window = "AXWindow"
    /// E21e: nur am Dock-Prozess gelesen (`AXAccess.dock…`), nie an fremden Apps.
    case children = "AXChildren"
    case selectedChildren = "AXSelectedChildren"
    case url = "AXURL"
}

/// **Positivliste der Aktionen (docs/SECURE-DESIGN.md E12):** die einzige Aktion, die Seam
/// auf fremden Fenstern auslöst. Ein Test hält die Liste fest, die Lint-Regel
/// `ax_schreiben_nur_ueber_axaccess` verbietet Aktionen außerhalb dieser Datei.
enum AXActionName: String, CaseIterable {
    case raise = "AXRaise"
}

/// Ein Fenster einer fremden App, identifiziert über die AX-Referenz (nicht
/// über Titel oder Lage, Lehre aus dem Prototyp).
struct AXWindow: Hashable, @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    /// Zeitlimit je Aufruf: Eine hängende App darf Seam nicht einfrieren (STRIDE D).
    static let timeout: Float = 0.25

    init(_ element: AXUIElement) {
        self.element = element
        var p: pid_t = 0
        AXUIElementGetPid(element, &p)
        self.pid = p
        AXUIElementSetMessagingTimeout(element, Self.timeout)
    }

    static func == (a: AXWindow, b: AXWindow) -> Bool { CFEqual(a.element, b.element) }
    func hash(into h: inout Hasher) { h.combine(CFHash(element)) }

    var frame: CGRect? {
        guard let p: CGPoint = AXAccess.point(element, .position),
              let s: CGSize = AXAccess.size(element, .size) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Nur echte App-Fenster (E4): Rolle Fenster, Unterrolle Standardfenster,
    /// nicht minimiert, nicht im Vollbild.
    var isManageable: Bool {
        AXAccess.string(element, .role) == "AXWindow"
            && AXAccess.string(element, .subrole) == "AXStandardWindow"
            && AXAccess.bool(element, .minimized) != true
            && AXAccess.bool(element, .fullScreen) != true
    }

    /// Setzt Lage und Größe und liest danach zurück (E5): Manche Apps übernehmen
    /// eine Position nicht (Prototyp: Helium). Rückgabe ist der IST-Wert.
    @discardableResult
    func setFrame(_ r: CGRect) -> CGRect? {
        var pt = r.origin, sz = r.size
        // Erst Größe, dann Lage, dann noch einmal Größe: Wird ein Fenster auf einen
        // anderen Bildschirm verschoben, begrenzt macOS die Größe am alten Ort.
        if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(element, "AXSize" as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(element, "AXPosition" as CFString, v) }
        if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(element, "AXSize" as CFString, v) }
        return frame
    }

    var isMinimized: Bool { AXAccess.bool(element, .minimized) == true }

    /// Bezeichnung fürs Protokoll: Bundle-ID der App, sonst die Prozessnummer (E11: keine Titel).
    var logName: String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
    }

    /// E12: Partner eines geteilten Paars mit minimieren bzw. wiederherstellen.
    func setMinimized(_ on: Bool) {
        AXUIElementSetAttributeValue(element, AXAttribute.minimized.rawValue as CFString, on as CFBoolean)
    }

    /// E12: Fenster anheben, ohne seine App zu aktivieren (kein Fokuswechsel).
    /// Rückgabe nur fürs Protokoll: Der Rechner meldete −25205 und wurde trotzdem gehoben.
    @discardableResult
    func perform(_ action: AXActionName) -> AXError {
        AXUIElementPerformAction(element, action.rawValue as CFString)
    }
}

enum AXAccess {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fragt die Freigabe an (öffnet den System-Dialog genau einmal je Start).
    static func requestTrust() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private static func copy(_ e: AXUIElement, _ a: AXAttribute) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, a.rawValue as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ e: AXUIElement, _ a: AXAttribute) -> String? { copy(e, a) as? String }
    static func bool(_ e: AXUIElement, _ a: AXAttribute) -> Bool? { (copy(e, a) as? NSNumber)?.boolValue }

    static func point(_ e: AXUIElement, _ a: AXAttribute) -> CGPoint? {
        guard let v = copy(e, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil   // swiftlint:disable:this force_cast
    }

    static func size(_ e: AXUIElement, _ a: AXAttribute) -> CGSize? {
        guard let v = copy(e, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil    // swiftlint:disable:this force_cast
    }

    static func element(_ e: AXUIElement, _ a: AXAttribute) -> AXUIElement? {
        guard let v = copy(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)                                        // swiftlint:disable:this force_cast
    }

    static func elements(_ e: AXUIElement, _ a: AXAttribute) -> [AXUIElement] {
        (copy(e, a) as? [AXUIElement]) ?? []
    }

    /// E17a: oberstes Bedienelement an einem Bildschirmpunkt (Bedienungshilfen-Koordinaten).
    /// Nur für die Prüfung des Griffpunkts; liest selbst keine Attribute.
    static func element(at p: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, AXWindow.timeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success else { return nil }
        return hit
    }

    /// E17a: Namen der Aktionen eines Elements — nur um zu erkennen, ob es etwas auslöst
    /// (Knopf, Link). Keine Inhalte.
    static func actionNames(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    /// Zeitlimit für ALLE Bedienungshilfen-Aufrufe dieses Prozesses, einmal beim Start.
    /// Code-Audit 09.10.: Vorher wurde es global erst beim ersten Tastenkürzel gesetzt (als
    /// Nebenwirkung von `focusedWindow()`); bis dahin galt für frisch erzeugte App-Elemente
    /// (Beobachter-Anmeldung in Dimmer/PairKeeper) der Systemwert von mehreren Sekunden.
    static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AXWindow.timeout)
    }

    /// Das gerade fokussierte Fenster (für Tastenkürzel). Nie ein Fenster von Seam selbst (E4):
    /// sonst setzte ⌃⌥← bei offenem Einstellungsfenster Seams eigenes Fenster (Code-Audit 09.10.).
    static func focusedWindow() -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, AXWindow.timeout)
        guard let app = element(system, .focusedApplication),
              let win = element(app, .focusedWindow) else { return nil }
        let w = AXWindow(win)
        return w.pid != ProcessInfo.processInfo.processIdentifier && w.isManageable ? w : nil
    }

    /// Fokusfenster einer bestimmten App (E12: App wurde aktiviert, gehört ihr Fenster zu einem Paar?).
    static func focusedWindow(of pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        return element(app, .focusedWindow).map(AXWindow.init)
    }

    // MARK: Dock (E21e) — nur lesend, nur am Dock-Prozess

    /// Das Dock: Bundle-ID `com.apple.dock` UND Programm unter `/System/` (STRIDE S).
    static func dockProcess() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first { $0.executableURL?.path.hasPrefix("/System/") == true }?.processIdentifier
    }

    /// Die Symbolliste des Docks (Rolle `AXList`).
    static func dockList(_ dockPID: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        return elements(app, .children).first { string($0, .role) == "AXList" }
    }

    /// Symbol unter dem Zeiger: Programm-URL (nur `.app`-Pakete) und Lage in AX-Koordinaten.
    /// nil = nichts ausgewählt oder kein App-Symbol (Ordner, Papierkorb, Trenner).
    static func dockHoveredApp(in list: AXUIElement) -> (url: URL, frame: CGRect)? {
        guard let item = elements(list, .selectedChildren).first,
              string(item, .subrole) == "AXApplicationDockItem",
              let raw = copy(item, .url), CFGetTypeID(raw) == CFURLGetTypeID() else { return nil }
        let url = (raw as! URL)                                           // swiftlint:disable:this force_cast
        guard url.isFileURL, url.pathExtension == "app",
              let p = point(item, .position), let s = size(item, .size) else { return nil }
        return (url, CGRect(origin: p, size: s))
    }

    /// E21f: App nach vorn holen, wenn macOS `activate()` abgelehnt hat (Seam ist nicht aktiv).
    /// Einziges neue Schreib-Attribut, nur am App-Element, nur auf die Geste im Umschalter/Dock.
    static func setFrontmost(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        AXUIElementSetAttributeValue(app, "AXFrontmost" as CFString, kCFBooleanTrue)
    }

    /// Alle Fenster einer App (auch minimierte), um ein gewähltes Fenster wiederzufinden (E21f).
    static func allWindows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        return elements(app, .windows).map(AXWindow.init)
    }

    /// Das verwaltbare Fenster einer App, das an `bounds` liegt (aus der Fensterliste des Systems).
    /// Erst die Lage vergleichen, dann nur den Treffer auf „verwaltbar“ prüfen. Code-Audit 09.10.:
    /// vorher wurde jedes Fenster der App zuerst voll geprüft (4 AX-Aufrufe je Fenster, bei jedem Klick).
    /// Wie `window(of:matching:)`, aber ohne `excluded`: Zwei gleich große Fenster derselben App
    /// (z. B. zwei maximierte) — der erste Treffer wäre oft das bewegte Fenster selbst (Code-Audit 18.11.).
    static func window(of pid: pid_t, matching bounds: CGRect, excluding excluded: AXWindow) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        for el in elements(app, .windows) {
            let w = AXWindow(el)
            guard w != excluded, let f = w.frame, Geometry.close(f, bounds) else { continue }
            return w.isManageable ? w : nil
        }
        return nil
    }

    static func window(of pid: pid_t, matching bounds: CGRect) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        for el in elements(app, .windows) {
            let w = AXWindow(el)
            guard let f = w.frame, Geometry.close(f, bounds) else { continue }
            return w.isManageable ? w : nil
        }
        return nil
    }
}

// MARK: - Menüleiste der Vorder-App (E24b) — nur lesend

/// **E24b: eigene, kleine Positivliste für das Kürzel-Blatt.** Fenster bleiben bei `AXAttribute` ohne
/// Titel (E3). `AXTitle` gibt es nur hier, nur an Menüleisten-Einträgen und an Menüpunkten, die ein
/// Kürzel haben. `AXAllowlistTests` hält die Liste fest; die Lint-Regel `ax_nur_ueber_allowlist`
/// verbietet das Lesen außerhalb dieser Datei.
enum AXMenuAttribute: String, CaseIterable {
    case menuBar = "AXMenuBar"
    case children = "AXChildren"
    case role = "AXRole"
    case title = "AXTitle"
    case cmdChar = "AXMenuItemCmdChar"
    case cmdModifiers = "AXMenuItemCmdModifiers"
    case cmdVirtualKey = "AXMenuItemCmdVirtualKey"
}

/// Ergebnis eines Lesevorgangs: nur Speicher, nie auf Platte oder ins Protokoll (E24b/E24e).
struct MenuRead: Sendable {
    var sections: [MenuSection]
    /// Lage des Fokusfensters der App (AX-Koordinaten), um den Bildschirm fürs Blatt zu wählen.
    var focusFrame: CGRect?
    /// Zeit- oder Mengengrenze erreicht, es fehlt etwas.
    var truncated: Bool
}

extension AXAccess {

    /// Gesamtfrist je Lesevorgang (E24b); Zeitlimit je Aufruf ist `AXWindow.timeout`.
    static let menuBudget: TimeInterval = 1.5
    fileprivate static let menuMaxDepth = 4
    fileprivate static let menuMaxVisited = 3000

    /// Menüs der App mit ihren Punkten mit Kürzel, gefiltert nach E24b. Blockiert bis zur Frist, gehört
    /// deshalb nie auf den Hauptthread. Der Titel eines Punkts wird nur gelesen, wenn er ein Kürzel hat.
    static func menuShortcuts(pid: pid_t, budget: TimeInterval = menuBudget) -> MenuRead? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        guard let bar = menuElement(app, .menuBar) else { return nil }
        var reader = MenuReader(deadline: Date().addingTimeInterval(budget))
        var sections: [MenuSection] = []
        var total = 0
        for (index, top) in menuElements(bar, .children).enumerated() {
            if reader.expired || total >= MenuShortcuts.maxItems { reader.truncated = true; break }
            let name = menuString(top, .title) ?? ""
            if MenuShortcuts.isAppleMenu(index: index, name: name) { continue }
            var raws: [RawMenuItem] = []
            reader.collect(top, depth: 0, into: &raws)
            if let section = MenuShortcuts.section(name: name, items: raws, limit: MenuShortcuts.maxItems - total) {
                sections.append(section)
                total += section.items.count
            }
        }
        return MenuRead(sections: sections, focusFrame: focusedWindow(of: pid)?.frame, truncated: reader.truncated)
    }

    fileprivate static func menuCopy(_ e: AXUIElement, _ a: AXMenuAttribute) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, a.rawValue as CFString, &v) == .success else { return nil }
        return v
    }

    fileprivate static func menuString(_ e: AXUIElement, _ a: AXMenuAttribute) -> String? { menuCopy(e, a) as? String }
    fileprivate static func menuInt(_ e: AXUIElement, _ a: AXMenuAttribute) -> Int? { (menuCopy(e, a) as? NSNumber)?.intValue }
    fileprivate static func menuElements(_ e: AXUIElement, _ a: AXMenuAttribute) -> [AXUIElement] {
        (menuCopy(e, a) as? [AXUIElement]) ?? []
    }

    fileprivate static func menuElement(_ e: AXUIElement, _ a: AXMenuAttribute) -> AXUIElement? {
        guard let v = menuCopy(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)                                        // swiftlint:disable:this force_cast
    }
}

/// Läuft den Menübaum ab (Tiefe 4, Frist, Höchstzahl) und sammelt nur Punkte mit Kürzel.
private struct MenuReader {
    let deadline: Date
    var truncated = false
    private var visited = 0

    init(deadline: Date) { self.deadline = deadline }

    var expired: Bool { Date() > deadline }

    mutating func collect(_ element: AXUIElement, depth: Int, into out: inout [RawMenuItem]) {
        for child in AXAccess.menuElements(element, .children) {
            if expired || visited >= AXAccess.menuMaxVisited || out.count >= MenuShortcuts.maxItems {
                truncated = true
                return
            }
            visited += 1
            switch AXAccess.menuString(child, .role) {
            case "AXMenu":
                if depth < AXAccess.menuMaxDepth { collect(child, depth: depth + 1, into: &out) }
            case "AXMenuItem":
                let char = AXAccess.menuString(child, .cmdChar)
                let key = AXAccess.menuInt(child, .cmdVirtualKey)
                if char?.isEmpty == false || key != nil {
                    var item = RawMenuItem(title: nil, cmdChar: char,
                                           modifiers: AXAccess.menuInt(child, .cmdModifiers), virtualKey: key)
                    // E24b Punkte 1 und 2: Titel erst lesen, wenn ein anzeigbares Kürzel feststeht. ⌘ + Ziffer
                    // (Fensterlisten) wird gar nicht erst nach dem Titel gefragt.
                    if MenuShortcuts.keys(for: item) != nil, !MenuShortcuts.isCommandDigit(item) {
                        item.title = AXAccess.menuString(child, .title)
                        out.append(item)
                    }
                }
                if depth < AXAccess.menuMaxDepth { collect(child, depth: depth + 1, into: &out) }
            default:
                break
            }
        }
    }
}
