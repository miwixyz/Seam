import AppKit

/// Ein Space (Schreibtisch) laut macOS. Nur Kennungen, keine Inhalte (docs/SECURE-DESIGN.md E14).
struct SpaceInfo: Equatable, Identifiable {
    /// Schlüssel für den Namen: UUID des Space, beim ursprünglichen Schreibtisch `haupt:<Bildschirm>`.
    let key: String
    /// Position unter den normalen Schreibtischen dieses Bildschirms (1 …), wie in Mission Control.
    /// 0 bei Vollbild-Apps.
    let number: Int
    let display: String
    let isFullScreen: Bool
    let isCurrent: Bool
    var id: String { key }
}

// Nicht dokumentierte CGS-Funktionen (E14), nur lesend, nur in dieser Datei.
@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func cgsCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

/// Einziger Zugang zur nicht dokumentierten Spaces-Schnittstelle (E14). Nur lesend.
/// Die Lint-Regel `private_schnittstelle_nur_spacereader` erlaubt `@_silgen_name` nur hier.
enum SpaceReader {

    /// nil = Schnittstelle liefert nichts (Funktion ausblenden).
    static func read() -> [SpaceInfo]? {
        guard let raw = cgsCopyManagedDisplaySpaces(cgsMainConnectionID()) as? [[String: Any]] else { return nil }
        let spaces = parse(raw)
        return spaces.isEmpty ? nil : spaces
    }

    /// Reine Auswertung der Rohdaten, getestet mit dem am 09.10. gemessenen Aufbau:
    /// je Bildschirm `Display Identifier`, `Current Space.ManagedSpaceID`,
    /// `Spaces[]` mit `ManagedSpaceID`, `type` (0 = Schreibtisch, 4 = Vollbild-App), `uuid`.
    static func parse(_ displays: [[String: Any]]) -> [SpaceInfo] {
        var out: [SpaceInfo] = []
        for d in displays {
            let display = d["Display Identifier"] as? String ?? "Main"
            let current = ((d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.intValue
            var desk = 0
            for s in (d["Spaces"] as? [[String: Any]]) ?? [] {
                let sid = (s["ManagedSpaceID"] as? NSNumber)?.intValue
                let full = (s["type"] as? NSNumber)?.intValue == 4
                if !full { desk += 1 }
                let uuid = (s["uuid"] as? String) ?? ""
                out.append(SpaceInfo(key: uuid.isEmpty ? "haupt:\(display)" : uuid,
                                     number: full ? 0 : desk, display: display,
                                     isFullScreen: full, isCurrent: sid != nil && sid == current))
            }
        }
        return out
    }

    /// Kennung des Bildschirms mit dem aktiven Fenster, wie sie in `Display Identifier` steht.
    static func displayIdentifier(of screen: NSScreen?) -> String? {
        guard let screen,
              let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Namen für Spaces: Eingaben des Nutzers (E14).
enum SpaceNames {

    static let maxLength = 40

    /// Leerraum außen weg, Steuerzeichen raus, höchstens 40 Zeichen.
    static func sanitize(_ s: String) -> String {
        let cleaned = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxLength))
    }

    /// Eigener Name oder der Standard wie in Mission Control.
    static func title(_ s: SpaceInfo, _ names: [String: String]) -> String {
        if let n = names[s.key], !n.isEmpty { return n }
        return s.isFullScreen ? "Vollbild-App" : "Schreibtisch \(s.number)"
    }

    /// Aktueller Space für die Menüleiste: auf dem Bildschirm des aktiven Fensters, sonst der
    /// einzige / erste Bildschirm. Gibt es nur eine Liste („Main“, Bildschirme teilen sich die
    /// Spaces), gilt sie.
    static func current(_ spaces: [SpaceInfo], display: String?) -> SpaceInfo? {
        let currents = spaces.filter(\.isCurrent)
        if let display, let hit = currents.first(where: { $0.display == display }) { return hit }
        return currents.first
    }
}
