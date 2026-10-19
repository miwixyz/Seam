import XCTest
@testable import Seam

/// E17d: Namen überleben, wenn macOS Spaces beim Neustart neu anlegt.
/// Abläufe nachgebaut nach den Messungen vom 19.10. (zwei Bildschirme, der zweite per USB-C);
/// Namen und Kennungen erfunden.
final class SpaceSlotTests: XCTestCase {

    private let main = "HAUPT-BILDSCHIRM", side = "NEBEN-BILDSCHIRM"

    private func desk(_ key: String, _ number: Int, _ display: String) -> SpaceInfo {
        SpaceInfo(key: key, number: number, display: display, isFullScreen: false, isCurrent: false)
    }

    /// Vor dem Neustart: 5 Spaces auf dem Hauptbildschirm, 3 auf dem Nebenbildschirm.
    private var before: [SpaceInfo] {
        [desk("haupt:\(main)", 1, main), desk("P", 2, main), desk("C", 3, main), desk("S", 4, main), desk("G", 5, main),
         desk("T", 1, side), desk("R", 2, side), desk("X", 3, side)]
    }
    private let names = ["haupt:HAUPT-BILDSCHIRM": "Eins", "P": "Zwei", "C": "Drei", "S": "Vier", "G": "Fuenf",
                         "T": "Sechs", "R": "Sieben", "X": "Acht"]

    func testSlotsRememberWhereEachNameStood() {
        let slots = SpaceNames.slots(before, names: names)
        XCTAssertEqual(slots["\(side)#1"], "Sechs")
        XCTAssertEqual(slots["\(main)#5"], "Fuenf")
        XCTAssertEqual(slots.count, 8)
    }

    /// Neustart 1 (gemessen 11:24): Space 1 des Nebenbildschirms gelöscht und neu angelegt,
    /// Space 2 und 3 wandern MIT Kennung ans Ende des Hauptbildschirms.
    func testNewSpaceInheritsNameOfItsSlot() {
        let after = [desk("haupt:\(main)", 1, main), desk("P", 2, main), desk("C", 3, main), desk("S", 4, main),
                     desk("G", 5, main), desk("R", 6, main), desk("X", 7, main), desk("NEU", 1, side)]
        let out = SpaceNames.adopt(after, names: names, slots: SpaceNames.slots(before, names: names))
        XCTAssertEqual(out["NEU"], "Sechs", "neuer Space am alten Platz erbt den Namen")
        XCTAssertEqual(out["R"], "Sieben", "gewanderter Space behält seinen Namen")
        XCTAssertEqual(out["X"], "Acht")
    }

    /// Neustart 2 (gemessen 12:21): ein Space des Hauptbildschirms landet auf dem Nebenbildschirm.
    /// Er hat einen Namen und behält ihn; niemand bekommt einen Namen doppelt.
    func testKnownSpaceOnForeignSlotKeepsItsName() {
        let after = [desk("haupt:\(main)", 1, main), desk("P", 2, main), desk("C", 3, main), desk("S", 4, main),
                     desk("R", 5, main), desk("X", 6, main), desk("G", 1, side)]
        let out = SpaceNames.adopt(after, names: names, slots: SpaceNames.slots(before, names: names))
        XCTAssertEqual(out, names, "alle lebenden Spaces haben schon Namen, nichts wird geerbt")
    }

    func testNoDuplicateWhenNameStillAlive() {
        // Der alte „Sechs“-Space lebt noch (auf den Hauptbildschirm gewandert); ein neuer Space an
        // seinem alten Platz darf den Namen nicht zusätzlich bekommen.
        let after = [desk("haupt:\(main)", 1, main), desk("T", 2, main), desk("NEU", 1, side)]
        let out = SpaceNames.adopt(after, names: names, slots: ["\(side)#1": "Sechs"])
        XCTAssertNil(out["NEU"])
        XCTAssertEqual(out["T"], "Sechs")
    }

    func testFullScreenSpacesNeverInherit() {
        let voll = SpaceInfo(key: "VOLL", number: 0, display: side, isFullScreen: true, isCurrent: true)
        XCTAssertNil(voll.slot)
        XCTAssertNil(SpaceNames.adopt([voll], names: [:], slots: ["\(side)#0": "Sechs"])["VOLL"])
    }

    func testTwoNewSpacesDoNotGetTheSameName() {
        let after = [desk("NEU1", 1, side), desk("NEU2", 2, side)]
        let out = SpaceNames.adopt(after, names: [:], slots: ["\(side)#1": "Sechs", "\(side)#2": "Sechs"])
        XCTAssertEqual(out.values.filter { $0 == "Sechs" }.count, 1)
    }

    // MARK: Einstellungen

    @MainActor
    func testNamingRecordsSlotAndClearingRemovesIt() {
        let p = Preferences(defaults: freshDefaults())
        let space = desk("T", 1, side)
        p.setSpaceName(" Sechs ", for: space)
        XCTAssertEqual(p.spaceNames["T"], "Sechs")
        XCTAssertEqual(p.spaceSlotNames["\(side)#1"], "Sechs")
        p.setSpaceName("", for: space)
        XCTAssertNil(p.spaceNames["T"])
        XCTAssertNil(p.spaceSlotNames["\(side)#1"])
    }

    @MainActor
    func testUpgradeTakesCurrentArrangementThenAdopts() {
        let d = freshDefaults()
        d.set(names, forKey: "spaceNames")          // Stand 0.6: nur Namen je Kennung, keine Plätze
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.adoptSpaceNames(before), 0, "Umstieg: Plätze gemerkt, nichts geerbt")
        XCTAssertEqual(p.spaceSlotNames.count, 8)
        let after = [desk("haupt:\(main)", 1, main), desk("R", 6, main), desk("NEU", 1, side)]
        XCTAssertEqual(p.adoptSpaceNames(after), 1)
        XCTAssertEqual(p.spaceNames["NEU"], "Sechs")
        XCTAssertEqual(Preferences(defaults: d).spaceNames["NEU"], "Sechs", "gespeichert")
    }

    @MainActor
    func testStoredSlotNamesAreCleanedOnLoad() {
        let d = freshDefaults()
        var raw: [String: String] = ["\(side)#1": "  Sechs ", "leer#1": "   ", "steuer\u{7}#1": "x",
                                     String(repeating: "k", count: 99): "zu lang"]
        for i in 0..<150 { raw["S\(i)#1"] = "n\(i)" }
        d.set(raw, forKey: "spaceSlotNames")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.spaceSlotNames["\(side)#1"], "Sechs")
        XCTAssertNil(p.spaceSlotNames["leer#1"])
        XCTAssertNil(p.spaceSlotNames["steuer\u{7}#1"])
        XCTAssertLessThanOrEqual(p.spaceSlotNames.count, Preferences.maxSlotNames)
    }

    // MARK: code-audit 19.10.: nur neu aufgetauchte Spaces erben

    /// Nutzer löscht „Sechs“ (Nebenbildschirm Platz 1); der bisherige Platz 2 rückt nach, ist aber
    /// nicht neu und darf „Sechs“ nicht erben.
    func testShiftedSpaceAfterDeletionDoesNotInherit() {
        let slots = ["\(side)#1": "Sechs"]
        let after = [desk("ALT2", 1, side)]
        XCTAssertNil(SpaceNames.adopt(after, names: [:], slots: slots, fresh: [])["ALT2"])
        XCTAssertEqual(SpaceNames.adopt(after, names: [:], slots: slots, fresh: ["ALT2"])["ALT2"], "Sechs")
    }

    @MainActor
    func testOnlyFirstAdoptTreatsEverythingAsNew() {
        let p = Preferences(defaults: freshDefaults())
        p.setSpaceName("Sechs", for: desk("T", 1, side))
        // Erster Abgleich: T lebt, ALT2 unbenannt an Platz 2.
        XCTAssertEqual(p.adoptSpaceNames([desk("T", 1, side), desk("ALT2", 2, side)]), 0)
        // Nutzer löscht T, ALT2 rückt auf Platz 1 nach → kein Erbe.
        XCTAssertEqual(p.adoptSpaceNames([desk("ALT2", 1, side)]), 0)
        XCTAssertNil(p.spaceNames["ALT2"])
        // Ein wirklich neuer Space an Platz 1 erbt.
        XCTAssertEqual(p.adoptSpaceNames([desk("NEU", 1, side), desk("ALT2", 2, side)]), 1)
        XCTAssertEqual(p.spaceNames["NEU"], "Sechs")
    }
}
