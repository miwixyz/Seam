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

    /// 28.11.: alte SeamKeys-Kopie in /Applications hatte die Freigabe, der Helfer im Paket nicht.
    func testForeignCopiesOnlyInAppFolders() {
        let own = URL(fileURLWithPath: "/Applications/Seam.app/Contents/Helpers/SeamKeys.app")
        let folders = ["/Applications", "/Users/x/Applications"]
        let found = KeyHelper.foreignCopies(candidates: [
            own,                                                                              // eigener Helfer
            URL(fileURLWithPath: "/Applications/SeamKeys.app"),                               // lose Kopie
            URL(fileURLWithPath: "/Users/x/Applications/Alt.app/Contents/Helpers/SeamKeys.app"), // in anderer App
            URL(fileURLWithPath: "/Users/x/Applications/Alt.app/Contents/Helpers/SeamKeys.app"), // doppelt gemeldet
            URL(fileURLWithPath: "/Users/x/Coding/Seam/build/Debug/SeamKeys.app"),            // Bauordner
            URL(fileURLWithPath: "/ApplicationsX/SeamKeys.app"),                              // nur Namensanfang
        ], own: own, appFolders: folders)
        XCTAssertEqual(found.map(\.path), ["/Applications/SeamKeys.app", "/Users/x/Applications/Alt.app"])
    }

    /// 28.11.: Beenden eines Testbaus stoppte den Helfer der installierten Seam mit.
    func testOnlyOwnHelperCounts() {
        let own = URL(fileURLWithPath: "/Applications/Seam.app/Contents/Helpers/SeamKeys.app")
        XCTAssertTrue(KeyHelper.isOwn(URL(fileURLWithPath: "/Applications/Seam.app/Contents/Helpers/SeamKeys.app/"), own: own))
        XCTAssertTrue(KeyHelper.isOwn(URL(fileURLWithPath: "/Applications/Seam.app/Contents/Helpers/../Helpers/SeamKeys.app"), own: own))
        XCTAssertFalse(KeyHelper.isOwn(URL(fileURLWithPath: "/Users/x/Coding/Seam/build/Debug/Seam.app/Contents/Helpers/SeamKeys.app"), own: own))
        XCTAssertFalse(KeyHelper.isOwn(nil, own: own))
    }

    func testNoForeignCopies() {
        let own = URL(fileURLWithPath: "/Applications/Seam.app/Contents/Helpers/SeamKeys.app")
        XCTAssertTrue(KeyHelper.foreignCopies(candidates: [own], own: own, appFolders: ["/Applications"]).isEmpty)
    }
}
