import CoreGraphics
import XCTest
@testable import Seam

/// E12: Paar-Buchführung und „stehen noch nebeneinander“.
final class PairBookTests: XCTestCase {

    func testPartnerBothWays() {
        var b = PairBook<Int>()
        b.add(1, 2)
        XCTAssertEqual(b.partner(of: 1), 2)
        XCTAssertEqual(b.partner(of: 2), 1)
        XCTAssertNil(b.partner(of: 3))
    }

    func testWindowBelongsToAtMostOnePair() {
        var b = PairBook<Int>()
        b.add(1, 2)
        b.add(3, 4)
        b.add(2, 3)          // neues ⌃⌥S erfasst 2 und 3 → beide alten Paare weg
        XCTAssertEqual(b.pairs.count, 1)
        XCTAssertEqual(b.partner(of: 2), 3)
        XCTAssertNil(b.partner(of: 1))
        XCTAssertNil(b.partner(of: 4))
    }

    func testNoPairWithItself() {
        var b = PairBook<Int>()
        b.add(1, 1)
        XCTAssertTrue(b.isEmpty)
    }

    func testRemoveReturnsPartner() {
        var b = PairBook<Int>()
        b.add(1, 2)
        XCTAssertEqual(b.remove(containing: 2), 1)
        XCTAssertTrue(b.isEmpty)
        XCTAssertNil(b.remove(containing: 2))
    }

    func testRemoveAllWhere() {
        var b = PairBook<Int>()
        b.add(1, 2)
        b.add(3, 4)
        b.removeAll { $0 == 4 }   // z. B. App von Fenster 4 beendet
        XCTAssertEqual(b.pairs.count, 1)
        XCTAssertEqual(b.partner(of: 1), 2)
    }

    // MARK: - Nebeneinander

    func testSplitHalvesAreSideBySide() {
        let l = CGRect(x: 0, y: 25, width: 957, height: 1000)
        let r = CGRect(x: 962, y: 25, width: 958, height: 1000)   // Abstand 5
        XCTAssertTrue(Geometry.stillSideBySide(l, r, gap: 5))
        XCTAssertTrue(Geometry.stillSideBySide(r, l, gap: 5))
    }

    func testStackedHalvesAreSideBySide() {
        let top = CGRect(x: 0, y: 0, width: 1080, height: 955)
        let bottom = CGRect(x: 0, y: 960, width: 1080, height: 955)
        XCTAssertTrue(Geometry.stillSideBySide(top, bottom, gap: 5))
    }

    func testMovedAwayIsNoLongerAPair() {
        let l = CGRect(x: 0, y: 25, width: 957, height: 1000)
        let away = CGRect(x: 1300, y: 200, width: 600, height: 500)
        XCTAssertFalse(Geometry.stillSideBySide(l, away, gap: 5))
    }

    func testOverlappingIsNoLongerAPair() {
        let l = CGRect(x: 0, y: 25, width: 957, height: 1000)
        let max = CGRect(x: 0, y: 25, width: 1920, height: 1000)   // Partner per ⌃⌘↩ maximiert
        XCTAssertFalse(Geometry.stillSideBySide(l, max, gap: 5))
    }

    @MainActor
    func testKeepPairsDefaultsOn() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        XCTAssertTrue(Preferences(defaults: d).keepPairs)
    }
}
