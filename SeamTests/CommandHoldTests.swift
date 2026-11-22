import AppKit
import XCTest
@testable import Seam

/// E24a/E24d: Entscheidungen des Kürzel-Blatts (ohne echte Ereignisse) und Standardwerte.
final class CommandHoldTests: XCTestCase {

    func testCommandAloneIgnoresCapsLockFnAndNumericPad() {
        XCTAssertTrue(CommandHold.isCommandAlone([.command]))
        XCTAssertTrue(CommandHold.isCommandAlone([.command, .capsLock]))
        XCTAssertTrue(CommandHold.isCommandAlone([.command, .function, .numericPad]))
    }

    func testAnyOtherModifierMeansNotAlone() {
        XCTAssertFalse(CommandHold.isCommandAlone([]))
        XCTAssertFalse(CommandHold.isCommandAlone([.shift]))
        XCTAssertFalse(CommandHold.isCommandAlone([.command, .shift]))
        XCTAssertFalse(CommandHold.isCommandAlone([.command, .option]))
        XCTAssertFalse(CommandHold.isCommandAlone([.command, .control]))
        XCTAssertFalse(CommandHold.isCommandAlone([.capsLock]))
    }

    func testReadStartsEarlyButNeverBeforeGrace() {
        XCTAssertEqual(CommandHold.readLead(delay: 0.6), 0.2, accuracy: 0.0001)     // Standard
        XCTAssertEqual(CommandHold.readLead(delay: 0.3), 0.2, accuracy: 0.0001)     // nie vor 0,2 s
        XCTAssertEqual(CommandHold.readLead(delay: 1.5), 1.1, accuracy: 0.0001)
    }

    func testNotShownInSeamLoginWindowOrSecurityDialog() {
        XCTAssertTrue(CommandHold.mayShow(bundleID: "com.apple.finder", own: "dev.mwlr.seam"))
        XCTAssertFalse(CommandHold.mayShow(bundleID: "dev.mwlr.seam", own: "dev.mwlr.seam"))
        XCTAssertFalse(CommandHold.mayShow(bundleID: "com.apple.loginwindow", own: "dev.mwlr.seam"))
        XCTAssertFalse(CommandHold.mayShow(bundleID: "com.apple.SecurityAgent", own: "dev.mwlr.seam"))
        XCTAssertFalse(CommandHold.mayShow(bundleID: nil, own: "dev.mwlr.seam"))
    }

    // MARK: Einstellungen (E24d)

    @MainActor
    func testDefaultsAreOffAndSixHundred() {
        let p = Preferences(defaults: freshDefaults())
        XCTAssertFalse(p.commandSheetEnabled, "Standard aus (Michael, 22.11.)")
        XCTAssertEqual(p.commandSheetDelay, 600)
    }

    @MainActor
    func testValuesSurviveReloadAndInvalidDelayFallsBack() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        p.commandSheetEnabled = true
        p.commandSheetDelay = 900
        XCTAssertTrue(Preferences(defaults: d).commandSheetEnabled)
        XCTAssertEqual(Preferences(defaults: d).commandSheetDelay, 900)

        d.set(7, forKey: "commandSheetDelay")                       // von außen verändert (STRIDE T)
        XCTAssertEqual(Preferences(defaults: d).commandSheetDelay, 600)
        d.set("ja", forKey: "commandSheetEnabled")                  // falscher Typ
        XCTAssertFalse(Preferences(defaults: d).commandSheetEnabled)
    }

    @MainActor
    func testDelayChoicesIncludeTheDefaultAndStayInRange() {
        XCTAssertTrue(Preferences.commandSheetDelayChoices.contains(Preferences.defaultCommandSheetDelay))
        XCTAssertEqual(Preferences.commandSheetDelayChoices.min(), 300)
        XCTAssertEqual(Preferences.commandSheetDelayChoices.max(), 1500)
    }
}
