import CoreGraphics
import XCTest
@testable import Seam

/// C2 (Code-Audit 09.10.): Verschieben vs. Größe ändern an der ROHEN Größe entscheiden.
final class GestureModeTests: XCTestCase {

    private let start = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testTitleBarDragNearTopEdgeIsAMove() {
        // Das Audit-Szenario: Klick ~7 px unter der Oberkante, erste Meldung „verschoben um 3/2 px“.
        // Vorher wurde daraus ein Größeziehen (kein Andocken, Fenster beim Loslassen niedriger).
        XCTAssertEqual(Geometry.gestureMode(start: start, raw: start.offsetBy(dx: 3, dy: 2)), .moving)
    }

    func testTopEdgeResizeIsAResize() {
        let raw = CGRect(x: 100, y: 80, width: 800, height: 620)   // Oberkante hochgezogen
        XCTAssertEqual(Geometry.gestureMode(start: start, raw: raw), .resizing)
    }

    func testSideResizeIsAResize() {
        XCTAssertEqual(Geometry.gestureMode(start: start, raw: CGRect(x: 100, y: 100, width: 760, height: 600)), .resizing)
    }

    func testNoChangeIsUndecided() {
        XCTAssertNil(Geometry.gestureMode(start: start, raw: start))
        XCTAssertNil(Geometry.gestureMode(start: start, raw: start.offsetBy(dx: 0.3, dy: 0)))
    }

    func testCloseToleranceIsTwoPoints() {
        XCTAssertTrue(Geometry.close(start, start.offsetBy(dx: 2, dy: -2)))
        XCTAssertFalse(Geometry.close(start, start.offsetBy(dx: 3, dy: 0)))
        XCTAssertFalse(Geometry.close(start, CGRect(x: 100, y: 100, width: 803, height: 600)))
    }
}
