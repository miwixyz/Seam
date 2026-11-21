import XCTest
@testable import Seam

/// E23: Regeln des Root-Helfers SeamWake (Abschaltung, pmset-Auswertung) und Seams Hinweistexte.
final class LidWakeTests: XCTestCase {

    func testNormalStateMayStayOn() {
        XCTAssertNil(WakeGuard.offReason(onBattery: true, percent: 80, thermal: 0))
        XCTAssertNil(WakeGuard.offReason(onBattery: true, percent: 21, thermal: 1))
    }

    func testLowBatteryOnlyCountsWithoutCharger() {
        XCTAssertEqual(WakeGuard.offReason(onBattery: true, percent: 20, thermal: 0), .battery)
        XCTAssertEqual(WakeGuard.offReason(onBattery: true, percent: 3, thermal: 0), .battery)
        XCTAssertNil(WakeGuard.offReason(onBattery: false, percent: 5, thermal: 0))
    }

    func testNoBatteryInfoIsNotABatteryReason() {
        XCTAssertNil(WakeGuard.offReason(onBattery: true, percent: nil, thermal: 0))   // Mac mini
    }

    func testHeatWinsFromSerious() {
        XCTAssertEqual(WakeGuard.offReason(onBattery: false, percent: nil, thermal: 2), .heat)
        XCTAssertEqual(WakeGuard.offReason(onBattery: true, percent: 90, thermal: 3), .heat)
    }

    /// Ausgabe wie gemessen am MacBook (macOS 27.2, 20.11.).
    func testReadsSleepDisabledFromPmset() {
        let off = " SleepDisabled\t\t0\n networkoversleep     0\n sleep                1 (sleep prevented by Claude)\n"
        let on = off.replacingOccurrences(of: "SleepDisabled\t\t0", with: "SleepDisabled\t\t1")
        XCTAssertEqual(WakeGuard.sleepDisabled(inPmsetOutput: off), false)
        XCTAssertEqual(WakeGuard.sleepDisabled(inPmsetOutput: on), true)
        XCTAssertNil(WakeGuard.sleepDisabled(inPmsetOutput: " sleep 1\n"))
    }

    func testUserTurnOffShowsNoNotice() {
        XCTAssertNil(LidWake.text(for: .off))
        XCTAssertNil(LidWake.text(for: .ok))
        XCTAssertNotNil(LidWake.text(for: .battery))
        XCTAssertNotNil(LidWake.text(for: .heat))
    }

    /// Fester Vertrag mit dem Helfer: Rohwerte gehen über XPC.
    func testReasonRawValuesAreStable() {
        XCTAssertEqual(WakeReason.battery.rawValue, "akku")
        XCTAssertEqual(WakeReason.clientGone.rawValue, "seam-weg")
        XCTAssertEqual(WakeXPC.machService, "dev.mwlr.seam.wake")
    }

    /// Alter Helfer nach einem Update: eigener Hinweis mit Abhilfe statt „antwortet nicht“.
    func testSigningFailureNamesRestart() {
        XCTAssertTrue(LidWake.failureText(code: NSXPCConnectionCodeSigningRequirementFailure).contains("neu starten"))
        XCTAssertEqual(LidWake.failureText(code: NSXPCConnectionInterrupted), "Helfer antwortet nicht")
    }
}
