import CoreGraphics

// Magnets Rastermodell, übernommen aus Michaels Magnet-Einstellungen
// (`com.crowdcafe.windowmagnet`, gelesen am 2026-10-08):
//
// - Querformat: Raster 24 × 12, Hochkant: 12 × 24.
// - Jedes Kommando hat eine ZIELFLÄCHE (Rasterzellen, die das Fenster danach
//   belegt) und AUSLÖSEFLÄCHEN (Rasterzellen, in denen der Mauszeiger beim
//   Ziehen landen muss).
// - Die Kürzel sind exakt Michaels Belegung, nicht Magnets Werkseinstellung:
//   Drittel, Maximieren, Zentrieren liegen im Querformat auf ⌃⌘.
//
// Alle Rechtecke hier in Bildschirmkoordinaten der Bedienungshilfen:
// Ursprung oben links auf dem Hauptbildschirm, y wächst nach unten.

/// Rasterzellen: Spalte, Zeile, Breite, Höhe.
struct Cells: Equatable, Sendable {
    let x: Int, y: Int, w: Int, h: Int
    init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }

    func contains(col: Int, row: Int) -> Bool {
        col >= x && col < x + w && row >= y && row < y + h
    }
}

enum Orientation: Sendable {
    case landscape   // 24 × 12
    case portrait    // 12 × 24

    var columns: Int { self == .landscape ? 24 : 12 }
    var rows: Int { self == .landscape ? 12 : 24 }

    static func of(_ visible: CGRect) -> Orientation {
        visible.height > visible.width ? .portrait : .landscape
    }
}

/// Tastenkürzel als Carbon-Werte (wie Magnet sie speichert).
struct KeyCombo: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32   // Carbon: cmd 256, shift 512, option 2048, control 4096

    static let ctrlOpt: UInt32 = 4096 | 2048
    static let ctrlCmd: UInt32 = 4096 | 256
    static let ctrlOptCmd: UInt32 = 4096 | 2048 | 256
    static let ctrlOptShift: UInt32 = 4096 | 2048 | 512

    /// Lesbar für Menü und Hilfe, z. B. „⌃⌥←“.
    var label: String {
        var s = ""
        if modifiers & 4096 != 0 { s += "⌃" }
        if modifiers & 2048 != 0 { s += "⌥" }
        if modifiers & 512 != 0 { s += "⇧" }
        if modifiers & 256 != 0 { s += "⌘" }
        if let name = Self.specialNames[keyCode] { return s + name }
        // Buchstaben nach der eingestellten Tastaturbelegung beschriften: Tastencodes sind
        // Positionen, keine Buchstaben. Code 16 ist auf US-Tastaturen „Y“, auf deutschen
        // „Z“ (Michael, 08.10.: Menü zeigte ⌃⌘Y, die Taste war aber ⌃⌘Z).
        return s + (KeyboardLayout.character(for: keyCode) ?? Self.usNames[keyCode] ?? "#\(keyCode)")
    }

    private static let specialNames: [UInt32: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 51: "⌫", 115: "↖",
    ]

    /// Rückfall, falls die Belegung nicht lesbar ist (US-Beschriftung).
    private static let usNames: [UInt32: String] = [
        1: "S", 2: "D", 3: "F", 5: "G", 8: "C", 14: "E", 15: "R", 16: "Y", 17: "T",
        32: "U", 34: "I", 37: "L", 38: "J", 40: "K",
    ]
}

enum Command: String, CaseIterable, Sendable {
    case left, right, up, down
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird            // quer: links/Mitte/rechts, hochkant: oben/Mitte/unten
    case firstTwoThirds, centerTwoThirds, lastTwoThirds
    case nextDisplay, previousDisplay
    case maximize, center, restore
    /// Geteilter Bildschirm (Michael, 08.10.): zwei Fenster teilen, Naht verschieben.
    case split, seamLeft, seamRight

    /// Deutscher Name fürs Menü, abhängig von der Ausrichtung.
    func title(_ o: Orientation) -> String {
        switch (self, o) {
        case (.left, _): "Linke Hälfte"
        case (.right, _): "Rechte Hälfte"
        case (.up, _): "Obere Hälfte"
        case (.down, _): "Untere Hälfte"
        case (.topLeft, _): "Oben links"
        case (.topRight, _): "Oben rechts"
        case (.bottomLeft, _): "Unten links"
        case (.bottomRight, _): "Unten rechts"
        case (.firstThird, .landscape): "Linkes Drittel"
        case (.firstThird, .portrait): "Oberes Drittel"
        case (.centerThird, _): "Mittleres Drittel"
        case (.lastThird, .landscape): "Rechtes Drittel"
        case (.lastThird, .portrait): "Unteres Drittel"
        case (.firstTwoThirds, .landscape): "Linke zwei Drittel"
        case (.firstTwoThirds, .portrait): "Obere zwei Drittel"
        case (.centerTwoThirds, _): "Mittlere zwei Drittel"
        case (.lastTwoThirds, .landscape): "Rechte zwei Drittel"
        case (.lastTwoThirds, .portrait): "Untere zwei Drittel"
        case (.nextDisplay, _): "Nächster Bildschirm"
        case (.previousDisplay, _): "Vorheriger Bildschirm"
        case (.maximize, _): "Maximieren"
        case (.center, _): "Zentrieren"
        case (.restore, _): "Ursprüngliche Größe"
        case (.split, _): "Zwei Fenster teilen"
        case (.seamLeft, .landscape): "Naht nach links"
        case (.seamLeft, .portrait): "Naht nach oben"
        case (.seamRight, .landscape): "Naht nach rechts"
        case (.seamRight, .portrait): "Naht nach unten"
        }
    }
}

struct CommandSpec: Sendable {
    let command: Command
    let key: KeyCombo
    /// nil bei Kommandos ohne feste Fläche (Bildschirm wechseln, Zentrieren, Wiederherstellen).
    let target: Cells?
    let activation: [Cells]
}

enum Layout {

    static func specs(_ o: Orientation) -> [CommandSpec] {
        o == .landscape ? landscape : portrait
    }

    static func spec(_ c: Command, _ o: Orientation) -> CommandSpec? {
        specs(o).first { $0.command == c }
    }

    private static func k(_ code: UInt32, _ mods: UInt32 = KeyCombo.ctrlOpt) -> KeyCombo {
        KeyCombo(keyCode: code, modifiers: mods)
    }

    // swiftlint:disable comma
    static let landscape: [CommandSpec] = [
        .init(command: .left,            key: k(123), target: Cells(0, 0, 12, 12), activation: [Cells(0, 3, 1, 6)]),
        .init(command: .right,           key: k(124), target: Cells(12, 0, 12, 12), activation: [Cells(23, 3, 1, 6)]),
        .init(command: .up,              key: k(126), target: Cells(0, 0, 24, 6),  activation: [Cells(0, 1, 1, 2), Cells(23, 1, 1, 2)]),
        .init(command: .down,            key: k(125), target: Cells(0, 6, 24, 6),  activation: [Cells(0, 9, 1, 2), Cells(23, 9, 1, 2)]),
        .init(command: .topLeft,         key: k(32),  target: Cells(0, 0, 12, 6),  activation: [Cells(0, 0, 1, 1)]),
        .init(command: .topRight,        key: k(34),  target: Cells(12, 0, 12, 6), activation: [Cells(23, 0, 1, 1)]),
        .init(command: .bottomLeft,      key: k(38),  target: Cells(0, 6, 12, 6),  activation: [Cells(0, 11, 1, 1)]),
        .init(command: .bottomRight,     key: k(40),  target: Cells(12, 6, 12, 6), activation: [Cells(23, 11, 1, 1)]),
        .init(command: .firstThird,      key: k(37, KeyCombo.ctrlCmd), target: Cells(0, 0, 8, 12),  activation: [Cells(1, 11, 6, 1)]),
        .init(command: .centerThird,     key: k(8,  KeyCombo.ctrlCmd), target: Cells(8, 0, 8, 12),  activation: [Cells(9, 11, 6, 1)]),
        .init(command: .lastThird,       key: k(15, KeyCombo.ctrlCmd), target: Cells(16, 0, 8, 12), activation: [Cells(17, 11, 6, 1)]),
        .init(command: .firstTwoThirds,  key: k(14), target: Cells(0, 0, 16, 12), activation: [Cells(7, 11, 2, 1)]),
        .init(command: .centerTwoThirds, key: k(16, KeyCombo.ctrlCmd), target: Cells(4, 0, 16, 12), activation: [Cells(11, 10, 2, 1)]),
        .init(command: .lastTwoThirds,   key: k(17), target: Cells(8, 0, 16, 12), activation: [Cells(15, 11, 2, 1)]),
        .init(command: .nextDisplay,     key: k(124, KeyCombo.ctrlOptCmd), target: nil, activation: []),
        .init(command: .previousDisplay, key: k(123, KeyCombo.ctrlOptCmd), target: nil, activation: []),
        .init(command: .maximize,        key: k(36,  KeyCombo.ctrlCmd), target: Cells(0, 0, 24, 12), activation: [Cells(1, 0, 22, 1)]),
        .init(command: .center,          key: k(115, KeyCombo.ctrlCmd), target: nil, activation: []),
        .init(command: .restore,         key: k(51), target: nil, activation: []),
        .init(command: .split,           key: k(1), target: nil, activation: []),
        .init(command: .seamLeft,        key: k(123, KeyCombo.ctrlOptShift), target: nil, activation: []),
        .init(command: .seamRight,       key: k(124, KeyCombo.ctrlOptShift), target: nil, activation: []),
    ]

    static let portrait: [CommandSpec] = [
        .init(command: .left,            key: k(123), target: Cells(0, 0, 6, 24),  activation: [Cells(1, 23, 5, 1)]),
        .init(command: .right,           key: k(124), target: Cells(6, 0, 6, 24),  activation: [Cells(6, 23, 5, 1)]),
        .init(command: .up,              key: k(126), target: Cells(0, 0, 12, 12), activation: [Cells(0, 1, 1, 4), Cells(11, 1, 1, 4)]),
        .init(command: .down,            key: k(125), target: Cells(0, 12, 12, 12), activation: [Cells(0, 19, 1, 4), Cells(11, 19, 1, 4)]),
        .init(command: .topLeft,         key: k(32),  target: Cells(0, 0, 6, 12),  activation: [Cells(0, 0, 1, 1)]),
        .init(command: .topRight,        key: k(34),  target: Cells(6, 0, 6, 12),  activation: [Cells(11, 0, 1, 1)]),
        .init(command: .bottomLeft,      key: k(38),  target: Cells(0, 12, 6, 12), activation: [Cells(0, 23, 1, 1)]),
        .init(command: .bottomRight,     key: k(40),  target: Cells(6, 12, 6, 12), activation: [Cells(11, 23, 1, 1)]),
        .init(command: .firstThird,      key: k(2),   target: Cells(0, 0, 12, 8),  activation: [Cells(0, 5, 1, 3), Cells(11, 5, 1, 3)]),
        .init(command: .centerThird,     key: k(3),   target: Cells(0, 8, 12, 8),  activation: [Cells(0, 10, 1, 4), Cells(11, 10, 1, 4)]),
        .init(command: .lastThird,       key: k(5),   target: Cells(0, 16, 12, 8), activation: [Cells(0, 16, 1, 3), Cells(11, 16, 1, 3)]),
        .init(command: .firstTwoThirds,  key: k(14),  target: Cells(0, 0, 12, 16), activation: [Cells(0, 8, 1, 2), Cells(11, 8, 1, 2)]),
        .init(command: .centerTwoThirds, key: k(15),  target: Cells(0, 4, 12, 16), activation: [Cells(1, 11, 1, 2), Cells(10, 11, 1, 2)]),
        .init(command: .lastTwoThirds,   key: k(17),  target: Cells(0, 8, 12, 16), activation: [Cells(0, 14, 1, 2), Cells(11, 14, 1, 2)]),
        .init(command: .nextDisplay,     key: k(124, KeyCombo.ctrlOptCmd), target: nil, activation: []),
        .init(command: .previousDisplay, key: k(123, KeyCombo.ctrlOptCmd), target: nil, activation: []),
        .init(command: .maximize,        key: k(36),  target: Cells(0, 0, 12, 24), activation: [Cells(1, 0, 10, 1)]),
        .init(command: .center,          key: k(8),   target: nil, activation: []),
        .init(command: .restore,         key: k(51),  target: nil, activation: []),
        .init(command: .split,           key: k(1),   target: nil, activation: []),
        .init(command: .seamLeft,        key: k(123, KeyCombo.ctrlOptShift), target: nil, activation: []),
        .init(command: .seamRight,       key: k(124, KeyCombo.ctrlOptShift), target: nil, activation: []),
    ]
    // swiftlint:enable comma

    /// Alle Kürzel, die registriert werden: Vereinigung beider Ausrichtungen.
    /// Dasselbe Kürzel kann je Ausrichtung ein anderes Kommando sein (⌃⌥E =
    /// linke bzw. obere zwei Drittel); welches gilt, entscheidet der Bildschirm
    /// des Fensters zum Zeitpunkt des Drückens.
    static var allKeys: Set<KeyCombo> {
        Set((landscape + portrait).map(\.key))
    }

    static func command(for key: KeyCombo, _ o: Orientation) -> Command? {
        specs(o).first { $0.key == key }?.command
    }
}
