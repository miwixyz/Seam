import XCTest
@testable import Seam

/// E14: Auswertung der Spaces-Rohdaten (Aufbau gemessen am 09.10. unter macOS 27) und Namen.
final class SpaceReaderTests: XCTestCase {

    private func space(_ id: Int, _ uuid: String, type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": NSNumber(value: id), "id64": NSNumber(value: id), "type": NSNumber(value: type), "uuid": uuid]
    }

    /// Wie auf dem MacBook gemessen: 4 Spaces, der dritte ist der ursprüngliche (leere UUID), aktiv ist Nr. 2.
    private var measured: [[String: Any]] {
        [["Display Identifier": "37D8832A", "Current Space": ["ManagedSpaceID": NSNumber(value: 4)],
          "Spaces": [space(5, "FC2D"), space(4, "0BB8"), space(1, ""), space(9, "0BCB")]]]
    }

    func testParseMeasuredLayout() {
        let s = SpaceReader.parse(measured)
        XCTAssertEqual(s.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(s.map(\.key), ["FC2D", "0BB8", "haupt:37D8832A", "0BCB"])
        XCTAssertEqual(s.filter(\.isCurrent).map(\.number), [2])
    }

    func testFullScreenAppIsNotCountedAsDesktop() {
        let raw: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["ManagedSpaceID": NSNumber(value: 7)],
                                     "Spaces": [space(1, ""), space(7, "VOLL", type: 4), space(3, "B")]]]
        let s = SpaceReader.parse(raw)
        XCTAssertEqual(s.map(\.number), [1, 0, 2])
        XCTAssertTrue(s[1].isFullScreen && s[1].isCurrent)
    }

    func testGarbageYieldsNothing() {
        XCTAssertEqual(SpaceReader.parse([["Unbekannt": 1]]), [])
    }

    func testTitleCustomOrDefault() {
        let s = SpaceReader.parse(measured)
        XCTAssertEqual(SpaceNames.title(s[0], ["FC2D": "Arbeit"]), "Arbeit")
        XCTAssertEqual(SpaceNames.title(s[2], [:]), "Schreibtisch 3")
    }

    func testNameSurvivesReorder() {
        // macOS ordnet Spaces um („automatisch neu anordnen“): Der Name hängt an der UUID, nicht an der Position.
        var raw = measured
        raw[0]["Spaces"] = [space(4, "0BB8"), space(5, "FC2D"), space(1, ""), space(9, "0BCB")]
        let s = SpaceReader.parse(raw)
        XCTAssertEqual(SpaceNames.title(s[1], ["FC2D": "Arbeit"]), "Arbeit")
        XCTAssertEqual(s[1].number, 2)
    }

    func testCurrentPrefersDisplayOfActiveWindow() {
        let raw: [[String: Any]] = [
            ["Display Identifier": "A", "Current Space": ["ManagedSpaceID": NSNumber(value: 1)], "Spaces": [space(1, "a1")]],
            ["Display Identifier": "B", "Current Space": ["ManagedSpaceID": NSNumber(value: 2)], "Spaces": [space(2, "b1")]],
        ]
        let s = SpaceReader.parse(raw)
        XCTAssertEqual(SpaceNames.current(s, display: "B")?.key, "b1")
        XCTAssertEqual(SpaceNames.current(s, display: nil)?.key, "a1")
        XCTAssertEqual(SpaceNames.current(s, display: "unbekannt")?.key, "a1")
    }

    func testSanitize() {
        XCTAssertEqual(SpaceNames.sanitize("  Arbeit \n"), "Arbeit")
        XCTAssertEqual(SpaceNames.sanitize("Ar\u{0007}beit"), "Arbeit")
        XCTAssertEqual(SpaceNames.sanitize(String(repeating: "x", count: 60)).count, 40)
    }

    @MainActor
    func testStoredNamesAreCleanedOnLoad() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        d.set(["A": "  Privat ", "B": "   ", "C": String(repeating: "y", count: 99)], forKey: "spaceNames")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.spaceNames["A"], "Privat")
        XCTAssertNil(p.spaceNames["B"])
        XCTAssertEqual(p.spaceNames["C"]?.count, 40)
        p.setSpaceName("", for: "A")
        XCTAssertNil(p.spaceNames["A"])
        XCTAssertTrue(p.showSpaceName)
    }
}

/// Michael, 09.10.: Symbol ausblendbar, wenn ein Space-Name steht.
final class MenuBarIconTests: XCTestCase {
    func testIconHiddenOnlyWithNameOptionAndTrust() {
        XCTAssertFalse(SpaceWatcher.showsIcon(title: "Arbeit", hideWhenNamed: true, trusted: true))
    }
    func testIconStaysWithoutName() {
        // Ohne Namen wäre Seam sonst unsichtbar.
        XCTAssertTrue(SpaceWatcher.showsIcon(title: nil, hideWhenNamed: true, trusted: true))
    }
    func testIconStaysWhenOptionOff() {
        XCTAssertTrue(SpaceWatcher.showsIcon(title: "Arbeit", hideWhenNamed: false, trusted: true))
    }
    func testIconStaysWithoutAccessibility() {
        // Durchgestrichenes Symbol = Freigabe fehlt; die Warnung darf nicht verschwinden.
        XCTAssertTrue(SpaceWatcher.showsIcon(title: "Arbeit", hideWhenNamed: true, trusted: false))
    }
    @MainActor
    func testDefaultOff() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        XCTAssertFalse(Preferences(defaults: d).hideIconWithSpaceName)
    }
}
