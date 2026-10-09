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

    /// Das verwaltbare Fenster einer App, das an `bounds` liegt (aus der Fensterliste des Systems).
    /// Erst die Lage vergleichen, dann nur den Treffer auf „verwaltbar“ prüfen. Code-Audit 09.10.:
    /// vorher wurde jedes Fenster der App zuerst voll geprüft (4 AX-Aufrufe je Fenster, bei jedem Klick).
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
