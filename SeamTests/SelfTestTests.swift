import XCTest
@testable import Seam

/// Selbsttest der Testkopie (2026-11-16): Ein gescheiterter Schritt muss das Gesamtergebnis kippen,
/// sonst meldet `scripts/selftest.sh` Exit 0 trotz FAIL. Die Schritte selbst laufen nur in der Testkopie.
@MainActor
final class SelfTestTests: XCTestCase {
    func testAllStepsPassingGivesPassed() {
        XCTAssertTrue(SelfTest.passed([.init(name: "a", ok: true, detail: "x"), .init(name: "b", ok: true, detail: "y")]))
    }

    func testOneFailingStepFailsTheWhole() {
        XCTAssertFalse(SelfTest.passed([.init(name: "a", ok: true, detail: "x"), .init(name: "b", ok: false, detail: "y")]))
    }

    func testNoStepsIsNotAPass() {
        XCTAssertFalse(SelfTest.passed([]))
    }

    func testRequestedOnlyWithFlag() {
        // Im Testlauf steht `--selftest` nicht in den Argumenten – sonst bräche der Start den Testlauf ab.
        XCTAssertFalse(SelfTest.isRequested)
    }
}
