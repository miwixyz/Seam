import XCTest
@testable import Seam

/// E22c: Verwaiste Belegung (Helfer ohne Aufräumen beendet) nur abräumen, wenn sie genau Seams
/// eigene ist. Eigene `hidutil`-Belegungen des Nutzers bleiben stehen.
@MainActor
final class KeyHelperTests: XCTestCase {

    private let ours = """
    RegistryID  Key                   Value
    1000008dd   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771181;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    1000007ee   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771181;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    10000066f   UserKeyMapping   (null)
    """

    func testOnlyOurMappingIsOrphan() {
        XCTAssertTrue(KeyHelper.isOnlyOurMapping(ours))
    }

    func testForeignMappingIsKept() {
        let mixed = ours + """

        100001267   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771300;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        XCTAssertFalse(KeyHelper.isOnlyOurMapping(mixed))
    }

    func testNoMappingNeedsNothing() {
        XCTAssertFalse(KeyHelper.isOnlyOurMapping("RegistryID  Key  Value\n1000008dd   UserKeyMapping   (null)\n"))
        XCTAssertFalse(KeyHelper.isOnlyOurMapping(""))
    }

    /// Audit 18.11. (Mittel): „SeamKeys läuft“ stand schon da, wenn der Prozess lief, der Tap aber
    /// mangels Freigabe nicht aktiv war. Der Status hängt jetzt an der vom Helfer gemeldeten Tap-PID.
    func testStatusNeedsActiveTapOfRunningHelper() {
        XCTAssertEqual(KeyHelper.status(running: [], tapPID: 0), .off)
        XCTAssertEqual(KeyHelper.status(running: [], tapPID: 812), .off)            // alter Eintrag, Helfer weg
        XCTAssertEqual(KeyHelper.status(running: [812], tapPID: 0), .waitingForAccess)
        XCTAssertEqual(KeyHelper.status(running: [900], tapPID: 812), .waitingForAccess) // Eintrag vom Vorgänger
        XCTAssertEqual(KeyHelper.status(running: [812], tapPID: 812), .active)
        XCTAssertEqual(KeyHelper.tapPIDKey, HyperSettings.tapPIDKey)                // Helfer und Seam: derselbe Schlüssel
    }
}
