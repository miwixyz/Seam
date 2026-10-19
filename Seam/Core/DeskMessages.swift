import Foundation

// Layouts pro Space, Schritt 6: Texte für Hinweisschild und Popover. Jede Meldung sagt, was los ist,
// und darunter `→ ZU TUN …` oder `→ Nichts zu tun` (Vault-Regel 10). Rein, getestet.
// App- und Bildschirmnamen nur hier in der Oberfläche, nie im Systemprotokoll (E17c).
enum DeskMessages {

    /// Name einer App zur Bundle-ID, Name eines Bildschirms zur Kennung — von außen gereicht,
    /// damit die Texte ohne laufendes System testbar sind.
    struct Names {
        var app: (String) -> String
        var display: (String) -> String
    }

    static let shortcut = "⌃⌥⌘L"

    // MARK: Lauf startet nicht

    /// nil = still bleiben (z. B. Sperre nach automatischem Lauf, gesperrter Bildschirm).
    static func blocked(_ b: DeskBlock, automatic: Bool) -> String? {
        switch b {
        case .noLayout:
            return automatic ? nil : "Noch kein Layout gespeichert.\n→ ZU TUN: Fenster anordnen, dann im Seam-Menü „Speichern“."
        case .noAccessibility:
            return "Seam fehlt die Bedienungshilfen-Freigabe.\n→ ZU TUN: "
                + "Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → Seam einschalten."
        case .switchKeysOff:
            return "Aufräumen braucht die Kurzbefehle ⌃← / ⌃→.\n→ ZU TUN: Systemeinstellungen → Tastatur → "
                + "Tastaturkurzbefehle → Mission Control → „Einen Schreibtisch nach links/rechts“ einschalten."
        case .fullScreenActive:
            return automatic ? nil : "Vorne ist eine Vollbild-App.\n→ ZU TUN: Vollbild verlassen, dann erneut \(shortcut)."
        case .spacesUnavailable:
            return automatic ? nil : "macOS liefert gerade keine Liste der Schreibtische.\n→ ZU TUN: in einer Minute erneut \(shortcut); bleibt es so, Seam neu starten."
        case .screenLocked, .cooldown, .alreadyRunning:
            return nil
        }
    }

    // MARK: Schreibtische am falschen Platz

    /// `autoTidy`: Räumt Seam nach dem Zurückziehen selbst auf (Automatik an) oder muss der Nutzer
    /// danach ⌃⌥⌘L drücken?
    static func issues(_ issues: [DeskIssue], names: Names, autoTidy: Bool = true) -> String? {
        guard !issues.isEmpty else { return nil }
        var lines: [String] = []
        let moved = issues.filter { if case .onOtherDisplay = $0.kind { return true } else { return false } }
        for target in orderedUnique(moved.map(\.desk.display)) {
            let here = moved.filter { $0.desk.display == target }
            let list = joined(here.map { label($0.desk) })
            lines.append("\(list) \(here.count == 1 ? "liegt" : "liegen") nicht auf \(names.display(target)).")
        }
        let missing = issues.filter { $0.kind == .missing }
        if !missing.isEmpty {
            lines.append("\(joined(missing.map { label($0.desk) })) \(missing.count == 1 ? "fehlt" : "fehlen").")
        }
        var todo: [String] = []
        if !moved.isEmpty {
            todo.append("Mission Control öffnen "
                + "(F3) und \(moved.count == 1 ? "den Schreibtisch" : "die Schreibtische") auf die Leiste des richtigen Bildschirms ziehen")
        }
        if !missing.isEmpty {
            todo.append("dort mit „+“ \(missing.count == 1 ? "einen Schreibtisch" : "Schreibtische") anlegen")
        }
        let after = autoTidy ? "Seam räumt danach selbst auf." : "Danach \(shortcut) drücken."
        return lines.joined(separator: " ") + "\n→ ZU TUN: " + todo.joined(separator: ", ") + ". " + after
    }

    // MARK: Ergebnis

    static func result(_ r: DeskRunResult, names: Names) -> String {
        if let why = r.aborted {
            switch why {
            case .userInput:
                return "Aufräumen abgebrochen, weil du Maus oder Tastatur benutzt hast (\(r.moved) "
                    + "Fenster schon am Platz).\n→ Weiter mit \(shortcut), wenn du kurz nichts tust."
            case .modifiersStuck:
                return "Aufräumen abgebrochen: Die Taste ⌃ meldet sich als gedrückt.\n→ ZU TUN: einmal ⌃ drücken und loslassen."
            case .timeLimit:
                return "Aufräumen nach 60 Sekunden beendet (\(r.moved) Fenster verschoben).\n→ Rest mit \(shortcut)."
            }
        }
        let failed = r.skipped.filter { [.notReachable, .notGrabbable, .notVerified].contains($0.reason) }
        let refused = r.skipped.filter { $0.reason == .sizeRefused }
        var text = r.moved + r.framed == 0 && failed.isEmpty ? "Alles an seinem Platz." : "Aufgeräumt: \(r.moved) Fenster "
            + "verschoben, \(r.framed) Größen gesetzt."
        if !refused.isEmpty {
            text += " Größe nicht übernommen: \(joined(orderedUnique(refused.map { names.app($0.bundleID) }))) (die App bestimmt sie selbst)."
        }
        if failed.isEmpty {
            return text + "\n→ Nichts zu tun."
        }
        text += " Nicht geschafft: \(joined(orderedUnique(failed.map { names.app($0.bundleID) })))."
        return text + "\n→ ZU TUN: \(failed.count == 1 ? "dieses Fenster" : "diese Fenster") von Hand an den Platz schieben."
    }

    static let running = "Seam räumt die Schreibtische auf …\nMaus und Tastatur bitte kurz nicht benutzen."

    static func saved(apps: Int) -> String {
        apps == 0 ? "Kein Fenster zum Speichern gefunden.\n→ ZU TUN: Apps öffnen und anordnen, dann erneut speichern."
                  : "Layout gespeichert: \(apps) \(apps == 1 ? "App" : "Apps").\n→ Nichts zu tun. Seam räumt nach "
                      + "Anmeldung und Bildschirmwechsel danach auf."
    }

    // MARK: Hilfen

    static func label(_ d: DeskRef) -> String {
        d.name.map { "„\($0)“" } ?? "Schreibtisch \(d.number)"
    }

    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " und " + items.last!
        }
    }

    private static func orderedUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
