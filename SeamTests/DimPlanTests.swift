import CoreGraphics
import XCTest
@testable import Seam

/// E13: Unter welches Fenster gehört die Abdunklung?
final class DimPlanTests: XCTestCase {

    private let a = StackWindow(number: 10, pid: 1, bounds: CGRect(x: 0, y: 25, width: 957, height: 1000))
    private let b = StackWindow(number: 20, pid: 2, bounds: CGRect(x: 962, y: 25, width: 958, height: 1000))
    private let c = StackWindow(number: 30, pid: 3, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
    private let a2 = StackWindow(number: 11, pid: 1, bounds: CGRect(x: 50, y: 50, width: 500, height: 400))

    func testFrontWindowOfFrontApp() {
        XCTAssertEqual(DimPlan.target(stack: [a, c, b], frontPID: 1, partner: nil, exclude: []), 10)
    }

    func testOtherWindowsOfSameAppAreDimmed() {
        // Nur das oberste Fenster der vorderen App bleibt hell (Michael, 09.10.).
        XCTAssertEqual(DimPlan.target(stack: [a, a2, c], frontPID: 1, partner: nil, exclude: []), 10)
    }

    func testPairBothStayBright() {
        XCTAssertEqual(DimPlan.target(stack: [a, b, c], frontPID: 1, partner: (2, b.bounds), exclude: []), 20)
    }

    func testPartnerAboveFrontKeepsFrontAsTarget() {
        // Partner liegt (noch) über dem vorderen Fenster: Ziel bleibt das vordere, nie höher.
        XCTAssertEqual(DimPlan.target(stack: [b, a, c], frontPID: 1, partner: (2, b.bounds), exclude: []), 10)
    }

    func testPartnerNotFoundFallsBackToFront() {
        let moved = CGRect(x: 1300, y: 300, width: 500, height: 400)
        XCTAssertEqual(DimPlan.target(stack: [a, b, c], frontPID: 1, partner: (2, moved), exclude: []), 10)
    }

    func testOwnOverlaysAreIgnored() {
        let overlay = StackWindow(number: 99, pid: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // Überlagerung des eigenen Prozesses vorn (z. B. Seams Hilfe vorn) zählt nicht als Fenster.
        XCTAssertEqual(DimPlan.target(stack: [overlay, a, c], frontPID: 1, partner: nil, exclude: [99]), 10)
    }

    func testNoWindowOfFrontAppMeansNoDimming() {
        XCTAssertNil(DimPlan.target(stack: [b, c], frontPID: 1, partner: nil, exclude: []))
    }

    func testInPlaceOnlyWhenOverlayDirectlyBelowTarget() {
        let o1 = StackWindow(number: 90, pid: 9, bounds: .zero)
        let o2 = StackWindow(number: 91, pid: 9, bounds: .zero)
        XCTAssertTrue(DimPlan.isInPlace(stack: [a, o1, o2, c], target: 10, overlays: [90, 91]))
        XCTAssertFalse(DimPlan.isInPlace(stack: [a, c, o1, o2], target: 10, overlays: [90, 91]))
        XCTAssertFalse(DimPlan.isInPlace(stack: [a], target: 10, overlays: [90]))
    }

    @MainActor
    func testDimDefaultsOffAndMedium() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        let p = Preferences(defaults: d)
        XCTAssertFalse(p.dimEnabled)
        XCTAssertEqual(p.dimStrength, 35)
    }

    @MainActor
    func testInvalidStrengthFallsBack() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        d.set(99, forKey: "dimStrength")
        XCTAssertEqual(Preferences(defaults: d).dimStrength, 35)
    }
}
