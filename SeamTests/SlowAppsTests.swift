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
        for v in [0.2, 0.2, 0.2, 0.01, 0.01, 0.01, 0.01, 0.01] { apps.record(42, seconds: v) }
        XCTAssertFalse(apps.isSlow(42))   // App ist schneller geworden
    }
}
