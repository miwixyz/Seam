import ServiceManagement
import XCTest
@testable import Seam

/// Gemessen 10.10.2026 (macOS 27, signierte App in /Applications): Vor der allerersten
/// Registrierung meldet `SMAppService.mainApp.status` `.notFound`, `register()` gelingt
/// trotzdem, danach heißt es `.notRegistered`. `.notFound` darf den Schalter also nicht sperren —
/// sonst kann Seam sich nie zum ersten Mal anmelden.
@MainActor
final class LoginItemTests: XCTestCase {

    func testNeverRegisteredAppCanBeSwitchedOn() {
        XCTAssertEqual(LoginItem.state(for: .notFound), .off)
    }

    func testOtherStatusesMapUnchanged() {
        XCTAssertEqual(LoginItem.state(for: .enabled), .on)
        XCTAssertEqual(LoginItem.state(for: .notRegistered), .off)
        XCTAssertEqual(LoginItem.state(for: .requiresApproval), .needsApproval)
    }
}
