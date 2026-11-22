import Foundation

/// Kürzel-Blatt (docs/SECURE-DESIGN.md E24b/E24c): reines Datenmodell, Filter und Spaltenaufteilung.
/// Kein Zugriff auf Bedienungshilfen, kein Speichern, kein Protokoll: Menütitel fremder Apps leben
/// nur im Speicher, solange das Blatt sichtbar ist.

/// Ein Menüpunkt mit Kürzel, fertig zum Anzeigen.
struct MenuShortcut: Equatable, Sendable {
    let title: String
    let keys: String
}

/// Ein Menü der Menüleiste („Ablage“, „Bearbeiten“ …) mit seinen Punkten mit Kürzel.
struct MenuSection: Equatable, Sendable {
    let name: String
    let items: [MenuShortcut]
}

/// Ein Menüpunkt, wie ihn die Bedienungshilfen liefern, VOR dem Filter. Der Titel wird nur gelesen,
/// wenn ein Kürzel da ist (E24b Punkt 1), sonst bleibt er `nil`.
struct RawMenuItem: Equatable, Sendable {
    var title: String?
    var cmdChar: String?
    /// `AXMenuItemCmdModifiers`: Bit 0 = ⇧, Bit 1 = ⌥, Bit 2 = ⌃, Bit 3 = OHNE ⌘. `nil` = nur ⌘.
    var modifiers: Int?
    var virtualKey: Int?
}

enum MenuShortcuts {

    static let maxTitle = 80
    /// Höchstzahl der Punkte mit Kürzel je Blatt (E24b Punkt 4).
    static let maxItems = 400

    // MARK: Kürzel als Text

    /// Tastennummer → Symbol, nur für Tasten ohne Zeichen im Menü (Pfeile, Löschen …).
    private static let virtualKeys: [Int: String] = [
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 71: "⌧", 76: "⌤",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// Kürzel als Text in der Reihenfolge ⌃⌥⇧⌘ (wie in macOS-Menüs). `nil`: kein (lesbares) Kürzel.
    static func keys(for item: RawMenuItem) -> String? {
        let mods = item.modifiers ?? 0
        let key: String
        if let c = item.cmdChar, let first = c.first, !first.unicodeScalars.contains(where: isControl) {
            key = first == " " ? "␣" : String(first).uppercased()
        } else if let vk = item.virtualKey, let symbol = virtualKeys[vk] {
            key = symbol
        } else {
            return nil
        }
        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }
        return s + key
    }

    /// ⌘ + Ziffer (ohne weitere Sondertaste): Fensterlisten in Terminal und Browsern, E24b Punkt 2.
    static func isCommandDigit(_ item: RawMenuItem) -> Bool {
        guard (item.modifiers ?? 0) == 0, let c = item.cmdChar, c.count == 1, let ch = c.first else { return false }
        return ch.isASCII && ch.isNumber
    }

    // MARK: Titel säubern

    /// Steuerzeichen und Umlenkzeichen (Textrichtung) entfernen, Leerraum verdichten, auf `maxTitle` kürzen.
    /// Leer danach → `nil` (Punkt wird verworfen).
    static func sanitize(_ title: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for u in title.unicodeScalars {
            if isControl(u) || isInvisibleFormat(u) { scalars.append(" ") } else { scalars.append(u) }
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxTitle else { return collapsed }
        return String(collapsed.prefix(maxTitle - 1)) + "…"
    }

    private static func isControl(_ u: Unicode.Scalar) -> Bool { CharacterSet.controlCharacters.contains(u) }

    /// Unsichtbare Formatzeichen (Unicode-Kategorie Cf): Textrichtungs-Umlenkung (U+202A…202E, U+2066…2069,
    /// U+200E/F), Nullbreiten-Zeichen, Byte-Order-Marke. Damit ließe sich Text umdrehen oder täuschen.
    private static func isInvisibleFormat(_ u: Unicode.Scalar) -> Bool {
        u.properties.generalCategory == .format
    }

    // MARK: Filter

    /// Aus den rohen Punkten eines Menüs die anzeigbaren (E24b, Punkte 1, 2, 4). `nil`, wenn nichts übrig bleibt.
    static func section(name: String, items: [RawMenuItem], limit: Int = maxItems) -> MenuSection? {
        guard let menuName = sanitize(name) else { return nil }
        var out: [MenuShortcut] = []
        for item in items where out.count < limit {
            guard !isCommandDigit(item), let keys = keys(for: item),
                  let title = item.title.flatMap(sanitize) else { continue }
            out.append(MenuShortcut(title: title, keys: keys))
        }
        return out.isEmpty ? nil : MenuSection(name: menuName, items: out)
    }

    /// Das erste Menüleisten-Element ist das Apple-Menü und wird übersprungen — aber nur mit dem
    /// Titel „Apple“ (E24b Punkt 3, gemessen 22.11. in 11 von 11 Apps).
    static func isAppleMenu(index: Int, name: String) -> Bool { index == 0 && name == "Apple" }
}

// MARK: - Spalten für das Blatt

enum SheetRow: Equatable, Sendable {
    case header(String)
    case item(MenuShortcut)
}

enum ShortcutSheetLayout {

    struct Result: Equatable {
        var columns: [[SheetRow]]
        /// Mehr Menüpunkte, als in `maxColumns` Spalten passen.
        var truncated: Bool
    }

    /// Verteilt die Menüs der Reihe nach auf Spalten mit höchstens `rowsPerColumn` Zeilen. Ein Menü
    /// bleibt zusammen, wenn es in eine leere Spalte passt; sonst läuft es mit wiederholter Überschrift weiter.
    static func columns(_ sections: [MenuSection], rowsPerColumn: Int, maxColumns: Int) -> Result {
        let rows = max(rowsPerColumn, 3)
        var columns: [[SheetRow]] = []
        var current: [SheetRow] = []
        for section in sections {
            let needed = 1 + section.items.count
            // Passt das Menü ganz in eine leere Spalte, aber nicht mehr in den Rest dieser: neue Spalte.
            if !current.isEmpty, current.count + needed > rows, needed <= rows {
                columns.append(current)
                current = []
            }
            // Mindestens Überschrift + ein Punkt müssen noch Platz haben.
            if current.count + 2 > rows {
                columns.append(current)
                current = []
            }
            current.append(.header(section.name))
            for item in section.items {
                if current.count >= rows {
                    columns.append(current)
                    current = [.header(section.name)]
                }
                current.append(.item(item))
            }
        }
        if !current.isEmpty { columns.append(current) }
        guard columns.count > maxColumns else { return Result(columns: columns, truncated: false) }
        return Result(columns: Array(columns.prefix(max(maxColumns, 1))), truncated: true)
    }
}
