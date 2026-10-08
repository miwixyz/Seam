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
    /// Elternfenster eines Elements (für „welches Fenster liegt unter der Maus?“).
    case window = "AXWindow"
    case windows = "AXWindows"
    case focusedApplication = "AXFocusedApplication"
    case focusedWindow = "AXFocusedWindow"
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

    /// Während einer Geste: Lage, dann Größe, ohne Zurücklesen (zwei Aufrufe statt
    /// fünf je Mausschritt). So im Prototyp gemessen: 0 px Versatz. Zurückgelesen
    /// wird einmal beim Loslassen über `setFrame`.
    func setFrameLive(_ r: CGRect) {
        var pt = r.origin, sz = r.size
        if let v = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(element, "AXPosition" as CFString, v) }
        if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(element, "AXSize" as CFString, v) }
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

    /// Das gerade fokussierte Fenster (für Tastenkürzel).
    static func focusedWindow() -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, AXWindow.timeout)
        guard let app = element(system, .focusedApplication),
              let win = element(app, .focusedWindow) else { return nil }
        let w = AXWindow(win)
        return w.isManageable ? w : nil
    }

    /// Fenster unter einem Bildschirmpunkt (für Ziehgesten).
    static func window(at p: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, AXWindow.timeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        let win = string(hit, .role) == "AXWindow" ? hit : element(hit, .window)
        guard let win else { return nil }
        let w = AXWindow(win)
        return w.isManageable ? w : nil
    }

    /// Alle verwaltbaren Fenster einer App.
    static func windows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.timeout)
        return elements(app, .windows).map(AXWindow.init).filter(\.isManageable)
    }
}
