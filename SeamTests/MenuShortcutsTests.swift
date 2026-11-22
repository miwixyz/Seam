import XCTest
@testable import Seam

/// E24b: Filter für das Kürzel-Blatt. Titel und Kürzel sind erfunden, keine echten Menüs.
final class MenuShortcutsTests: XCTestCase {

    private func raw(_ title: String?, _ char: String?, mods: Int? = 0, key: Int? = nil) -> RawMenuItem {
        RawMenuItem(title: title, cmdChar: char, modifiers: mods, virtualKey: key)
    }

    // MARK: Kürzel als Text

    func testKeysFollowMenuOrderControlOptionShiftCommand() {
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "n")), "⌘N")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "s", mods: 1)), "⇧⌘S")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "q", mods: 4)), "⌃⌘Q")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "z", mods: 1 | 2 | 4)), "⌃⌥⇧⌘Z")
    }

    func testBitEightMeansWithoutCommand() {
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "h", mods: 8)), "H")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", nil, mods: 8, key: 122)), "F1")
    }

    func testVirtualKeysAndSpace() {
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", nil, key: 123)), "⌘←")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "", mods: 2, key: 36)), "⌥⌘↩")
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", " ", mods: 4)), "⌃⌘␣")
    }

    func testNoUsableKeyMeansNoShortcut() {
        XCTAssertNil(MenuShortcuts.keys(for: raw("x", nil, key: nil)))
        XCTAssertNil(MenuShortcuts.keys(for: raw("x", "", key: nil)))
        XCTAssertNil(MenuShortcuts.keys(for: raw("x", "\u{1B}", key: nil)), "Steuerzeichen allein ist kein Kürzel")
        XCTAssertNil(MenuShortcuts.keys(for: raw("x", nil, key: 0)), "unbekannte Tastennummer wird nicht erfunden")
    }

    func testModifiersMissingMeansCommandOnly() {
        XCTAssertEqual(MenuShortcuts.keys(for: raw("x", "p", mods: nil)), "⌘P")
    }

    // MARK: Titel säubern

    func testSanitizeRemovesControlAndDirectionOverrides() {
        XCTAssertEqual(MenuShortcuts.sanitize("Neu\u{0A}es\tFenster"), "Neu es Fenster")
        XCTAssertEqual(MenuShortcuts.sanitize("a\u{202E}b\u{2066}c"), "a b c")
        XCTAssertEqual(MenuShortcuts.sanitize("a\u{200E}b\u{200B}c\u{FEFF}d"), "a b c d", "Richtungsmarke, Nullbreite, BOM")
        XCTAssertNil(MenuShortcuts.sanitize("\u{200B}\u{202E}"), "nur Unsichtbares ergibt keinen Titel")
        XCTAssertNil(MenuShortcuts.sanitize("  \u{0A}\t "))
        XCTAssertNil(MenuShortcuts.sanitize(""))
    }

    func testSanitizeCapsLength() {
        let long = String(repeating: "ä", count: 200)
        let out = MenuShortcuts.sanitize(long) ?? ""
        XCTAssertEqual(out.count, MenuShortcuts.maxTitle)
        XCTAssertTrue(out.hasSuffix("…"))
        XCTAssertEqual(MenuShortcuts.sanitize(String(repeating: "a", count: 80)), String(repeating: "a", count: 80))
    }

    // MARK: Filter (E24b Punkte 1 bis 4)

    func testItemsWithoutShortcutOrTitleAreDropped() {
        let s = MenuShortcuts.section(name: "Ablage", items: [
            raw("Neu", "n"),
            raw("Ohne Kürzel", nil),            // Punkt 1
            raw(nil, "w"),                      // Titel fehlt
            raw("   ", "k"),                    // Titel leer nach dem Säubern
        ])
        XCTAssertEqual(s?.items, [MenuShortcut(title: "Neu", keys: "⌘N")])
    }

    func testCommandDigitIsDropped() {
        let s = MenuShortcuts.section(name: "Fenster", items: [
            raw("Terminal — Konto A", "1"),     // Punkt 2: Fensterliste
            raw("Terminal — Konto B", "2"),
            raw("Zeige Posteingang", "1", mods: 1),   // mit ⇧ bleibt es
            raw("Zoom", "0", mods: 2),                // mit ⌥ bleibt es
            raw("Neu", "n"),
        ])
        XCTAssertEqual(s?.items.map(\.title), ["Zeige Posteingang", "Zoom", "Neu"])
        XCTAssertTrue(MenuShortcuts.isCommandDigit(raw("x", "7")))
        XCTAssertFalse(MenuShortcuts.isCommandDigit(raw("x", "7", mods: 8)), "Ziffer ohne ⌘ ist keine Fensterliste")
        XCTAssertFalse(MenuShortcuts.isCommandDigit(raw("x", "a")))
        XCTAssertFalse(MenuShortcuts.isCommandDigit(raw("x", "١")), "nur ASCII-Ziffern")
    }

    func testEmptyResultsReturnNil() {
        XCTAssertNil(MenuShortcuts.section(name: "Hilfe", items: [raw("Suchen", nil)]))
        XCTAssertNil(MenuShortcuts.section(name: "", items: [raw("Neu", "n")]), "Menü ohne Namen wird nicht gezeigt")
    }

    func testLimitApplies() {
        let items = (0..<50).map { raw("Punkt \($0)", "a") }
        XCTAssertEqual(MenuShortcuts.section(name: "M", items: items, limit: 10)?.items.count, 10)
        XCTAssertEqual(MenuShortcuts.maxItems, 400)
    }

    func testAppleMenuOnlyAtIndexZeroWithThatTitle() {
        XCTAssertTrue(MenuShortcuts.isAppleMenu(index: 0, name: "Apple"))
        XCTAssertFalse(MenuShortcuts.isAppleMenu(index: 0, name: "Datei"), "andere Menüleiste: nichts überspringen")
        XCTAssertFalse(MenuShortcuts.isAppleMenu(index: 1, name: "Apple"))
    }

    // MARK: Spalten

    private func section(_ name: String, _ count: Int) -> MenuSection {
        MenuSection(name: name, items: (0..<count).map { MenuShortcut(title: "\(name) \($0)", keys: "⌘A") })
    }

    func testSmallSectionsShareAColumn() {
        let r = ShortcutSheetLayout.columns([section("A", 2), section("B", 2)], rowsPerColumn: 10, maxColumns: 5)
        XCTAssertEqual(r.columns.count, 1)
        XCTAssertEqual(r.columns[0].count, 6)
        XCTAssertFalse(r.truncated)
    }

    func testSectionMovesToNextColumnWhenItFitsThereAsAWhole() {
        let r = ShortcutSheetLayout.columns([section("A", 5), section("B", 4)], rowsPerColumn: 8, maxColumns: 5)
        XCTAssertEqual(r.columns.map(\.count), [6, 5])
        XCTAssertEqual(r.columns[1].first, .header("B"))
    }

    func testBigSectionContinuesWithRepeatedHeader() {
        let r = ShortcutSheetLayout.columns([section("A", 12)], rowsPerColumn: 6, maxColumns: 5)
        XCTAssertEqual(r.columns.count, 3)
        XCTAssertTrue(r.columns.allSatisfy { $0.count <= 6 })
        XCTAssertTrue(r.columns.allSatisfy { if case .header("A") = $0[0] { return true } else { return false } })
        let items = r.columns.flatMap { $0 }.filter { if case .item = $0 { return true } else { return false } }
        XCTAssertEqual(items.count, 12, "kein Punkt geht verloren")
    }

    func testTooManyColumnsAreCutAndFlagged() {
        let r = ShortcutSheetLayout.columns([section("A", 30)], rowsPerColumn: 6, maxColumns: 2)
        XCTAssertEqual(r.columns.count, 2)
        XCTAssertTrue(r.truncated)
    }

    func testLayoutHandlesNoSectionsAndTinyHeight() {
        XCTAssertTrue(ShortcutSheetLayout.columns([], rowsPerColumn: 10, maxColumns: 3).columns.isEmpty)
        let r = ShortcutSheetLayout.columns([section("A", 3)], rowsPerColumn: 0, maxColumns: 0)
        XCTAssertFalse(r.columns.isEmpty, "mindestens eine Spalte, auch bei unsinnigen Maßen")
    }
}
