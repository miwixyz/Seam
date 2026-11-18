import CoreGraphics
import XCTest

/// E22: Entscheidungen der Supertaste (SeamKeys/HyperLogic.swift, ins Testziel mit eingebunden).
final class HyperKeyTests: XCTestCase {

    private let f18 = TapState.f18
    private let letterA: Int64 = 0

    func testHoldAddsFlagsAndSwallowsF18() {
        var s = TapState(flags: [.maskCommand, .maskShift], escapeOnTap: true)
        XCTAssertEqual(s.handle(type: .keyDown, keyCode: f18), .swallow)
        XCTAssertEqual(s.handle(type: .keyDown, keyCode: f18), .swallow)        // Wiederholung beim Halten
        XCTAssertEqual(s.handle(type: .keyDown, keyCode: letterA), .addFlags)
        XCTAssertEqual(s.handle(type: .keyUp, keyCode: letterA), .addFlags)
        // Mit einer anderen Taste benutzt → beim Loslassen kein Escape.
        XCTAssertEqual(s.handle(type: .keyUp, keyCode: f18), .swallow)
        XCTAssertEqual(s.handle(type: .keyDown, keyCode: letterA), .pass)       // danach wieder normal
    }

    func testShortPressGivesEscapeOnlyWhenChosen() {
        var on = TapState(flags: [.maskCommand], escapeOnTap: true)
        _ = on.handle(type: .keyDown, keyCode: f18)
        XCTAssertEqual(on.handle(type: .keyUp, keyCode: f18), .swallowAndEscape)

        var off = TapState(flags: [.maskCommand], escapeOnTap: false)
        _ = off.handle(type: .keyDown, keyCode: f18)
        XCTAssertEqual(off.handle(type: .keyUp, keyCode: f18), .swallow)
    }

    func testWithoutHoldEverythingPasses() {
        var s = TapState(flags: [.maskCommand], escapeOnTap: true)
        XCTAssertEqual(s.handle(type: .keyDown, keyCode: letterA), .pass)
        XCTAssertEqual(s.handle(type: .flagsChanged, keyCode: 56), .pass)
    }

    /// Ungültige Werte aus der Domain → alle vier Sondertasten (STRIDE T).
    func testFlagMask() {
        XCTAssertEqual(HyperSettings.flags(15), [.maskShift, .maskControl, .maskAlternate, .maskCommand])
        XCTAssertEqual(HyperSettings.flags(8), [.maskCommand])
        XCTAssertEqual(HyperSettings.flags(5), [.maskShift, .maskAlternate])
        XCTAssertEqual(HyperSettings.flags(0), HyperSettings.flags(15))
        XCTAssertEqual(HyperSettings.flags(99), HyperSettings.flags(15))
    }

    /// Audit 18.11.: Der Helfer startete auch bei ausgeschalteter Supertaste (z. B. von Hand geöffnet).
    func testHelperRunsOnlyWhenEnabledInSeam() {
        let suite = "dev.mwlr.seam.tests.hyperenabled"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertFalse(HyperSettings.isEnabled(suite: suite))
        d.set(true, forKey: "hyperKeyEnabled")
        XCTAssertTrue(HyperSettings.isEnabled(suite: suite))
        d.set(false, forKey: "hyperKeyEnabled")
        XCTAssertFalse(HyperSettings.isEnabled(suite: suite))
        d.removePersistentDomain(forName: suite)
    }
}
