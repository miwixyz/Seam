import CoreGraphics
import XCTest
@testable import Seam

/// Erwartungswerte aus dem gemessenen Fall 10.10. (MacBook 1470 pt, Abstand 10, Seam-Protokoll):
/// Teilen verlangte Edge 10…730 + Outlook 740…1460, Outlook blieb 980 breit, Edge danach 500.
final class MinimumNoticeTests: XCTestCase {

    private let outlookWanted = CGRect(x: 740, y: 43, width: 720, height: 855)
    private let outlookActual = CGRect(x: 740, y: 43, width: 980, height: 855)
    /// `resolveMinimum`: Outlook rechts bündig 480…1460, Edge bis 470 (Abstand 10).
    private let edgeWanted = CGRect(x: 10, y: 43, width: 460, height: 855)

    func testEdgeAndOutlookDoNotFitOnMacBook() {
        let edgeActual = CGRect(x: 10, y: 43, width: 500, height: 855)
        let n = MinimumNotice.evaluate(wanted: outlookWanted, actual: outlookActual,
                                       leadingWanted: edgeWanted, leadingActual: edgeActual)
        XCTAssertEqual(n, .noRoom(minimum: 980, otherMinimum: 500, horizontal: true))
        XCTAssertEqual(n?.text(neighbor: "Outlook", other: "Edge"),
                       "Edge und Outlook passen hier nicht nebeneinander.\n"
                       + "Edge braucht mindestens 500 pt, Outlook 980 pt.\n"
                       + "Tipp: Seitenleiste einer App einklappen.")
    }

    func testSeamHeldWhenOtherWindowFits() {
        let n = MinimumNotice.evaluate(wanted: outlookWanted, actual: outlookActual,
                                       leadingWanted: edgeWanted, leadingActual: edgeWanted)
        XCTAssertEqual(n, .held(minimum: 980, horizontal: true))
        XCTAssertEqual(n?.text(neighbor: "Outlook", other: "Edge"),
                       "Outlook geht nicht schmaler als 980 pt.\nDie Naht steht an dieser Grenze.")
    }

    func testUnreadableOtherWindowOnlyReportsHeld() {
        let n = MinimumNotice.evaluate(wanted: outlookWanted, actual: outlookActual,
                                       leadingWanted: edgeWanted, leadingActual: nil)
        XCTAssertEqual(n, .held(minimum: 980, horizontal: true))
    }

    func testNoNoticeWhenNeighborTookItsFrame() {
        XCTAssertNil(MinimumNotice.evaluate(wanted: outlookWanted, actual: outlookWanted,
                                            leadingWanted: edgeWanted, leadingActual: edgeWanted))
        // 1 pt Rundung ist kein Mindestgrößen-Fall
        let rounded = CGRect(x: 740, y: 43, width: 721, height: 855)
        XCTAssertNil(MinimumNotice.evaluate(wanted: outlookWanted, actual: rounded,
                                            leadingWanted: edgeWanted, leadingActual: edgeWanted))
    }

    func testVerticalNeighborSaysLower() {
        let wanted = CGRect(x: 0, y: 500, width: 800, height: 300)
        let actual = CGRect(x: 0, y: 500, width: 800, height: 420)
        let n = MinimumNotice.evaluate(wanted: wanted, actual: actual,
                                       leadingWanted: CGRect(x: 0, y: 40, width: 800, height: 330),
                                       leadingActual: CGRect(x: 0, y: 40, width: 800, height: 330))
        XCTAssertEqual(n, .held(minimum: 420, horizontal: false))
        XCTAssertEqual(n?.text(neighbor: "Mail", other: "Notizen"),
                       "Mail geht nicht niedriger als 420 pt.\nDie Naht steht an dieser Grenze.")
    }

    func testAnchorSitsOnFacingEdge() {
        let edge = CGRect(x: 10, y: 43, width: 500, height: 855)
        let outlook = CGRect(x: 480, y: 43, width: 980, height: 855)
        XCTAssertEqual(MinimumNotice.anchor(leading: edge, neighbor: outlook, horizontal: true),
                       CGPoint(x: 480, y: 470.5))
        XCTAssertEqual(MinimumNotice.anchor(leading: outlook, neighbor: edge, horizontal: true),
                       CGPoint(x: 510, y: 470.5))
    }
}
