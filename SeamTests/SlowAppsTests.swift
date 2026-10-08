import XCTest
@testable import Seam

/// Werte aus den Messungen vom 08.10. (Sekunden je Größenänderung).
final class SlowAppsTests: XCTestCase {

    func testOutlookIsSlow() {
        XCTAssertTrue(SlowApps.isSlow([0.125, 0.448, 0.090, 0.110]))
    }

    func testEdgeWithOneSpikeIsNotSlow() {
        XCTAssertFalse(SlowApps.isSlow([0.011, 0.017, 0.162, 0.014, 0.012]))
    }

    func testTooFewSamplesNeverSlow() {
        XCTAssertFalse(SlowApps.isSlow([0.448, 0.400]))
    }

    func testOnlyLastFiveCount() {
        let apps = SlowApps()
        for v in [0.2, 0.2, 0.2, 0.01, 0.01, 0.01, 0.01, 0.01] { apps.record(42, 7, seconds: v) }
        XCTAssertFalse(apps.isSlow(42, 7))   // Paar ist schneller geworden
    }

    func testPairsAreIndependent() {
        // Edge (1) mit Outlook (2) langsam, Edge mit Obsidian (3) schnell
        let apps = SlowApps()
        for v in [0.159, 0.081, 0.12] { apps.record(1, 2, seconds: v) }
        for v in [0.012, 0.009, 0.015] { apps.record(1, 3, seconds: v) }
        XCTAssertTrue(apps.isSlow(1, 2))
        XCTAssertFalse(apps.isSlow(1, 3))
    }
}
