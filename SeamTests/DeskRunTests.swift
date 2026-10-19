import XCTest
@testable import Seam

/// Schritt 5 / E17b: Wann ein Lauf startet, wie weit ein Fenster fährt, welches Fenster gemeint ist.
final class DeskRunTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRunsWhenEverythingIsFine() {
        XCTAssertNil(DeskRun.blocker(.init(), automatic: true, lastAutomatic: nil, now: now))
    }

    func testBlockersInOrderOfWhatToFixFirst() {
        var c = DeskRun.Conditions(hasLayout: false, trusted: false, switchKeys: false, locked: true, fullScreen: true)
        XCTAssertEqual(DeskRun.blocker(c, automatic: false, lastAutomatic: nil, now: now), .noLayout)
        c.hasLayout = true
        XCTAssertEqual(DeskRun.blocker(c, automatic: false, lastAutomatic: nil, now: now), .noAccessibility)
        c.trusted = true
        XCTAssertEqual(DeskRun.blocker(c, automatic: false, lastAutomatic: nil, now: now), .screenLocked)
        c.locked = false
        XCTAssertEqual(DeskRun.blocker(c, automatic: false, lastAutomatic: nil, now: now), .switchKeysOff)
        c.switchKeys = true
        XCTAssertEqual(DeskRun.blocker(c, automatic: false, lastAutomatic: nil, now: now), .fullScreenActive)
    }

    func testNeverTwoRunsAtOnce() {
        XCTAssertEqual(DeskRun.blocker(.init(running: true), automatic: false, lastAutomatic: nil, now: now), .alreadyRunning)
    }

    func testAutomaticRunsAtMostEveryTwoMinutes() {
        let recent = now.addingTimeInterval(-60), old = now.addingTimeInterval(-121)
        XCTAssertEqual(DeskRun.blocker(.init(), automatic: true, lastAutomatic: recent, now: now), .cooldown)
        XCTAssertNil(DeskRun.blocker(.init(), automatic: true, lastAutomatic: old, now: now))
        XCTAssertNil(DeskRun.blocker(.init(), automatic: false, lastAutomatic: recent, now: now),
                     "von Hand ausgelöst gilt die Sperre nicht")
    }

    private func desk(_ n: Int, _ d: String, full: Bool = false) -> SpaceInfo {
        SpaceInfo(key: "\(d)\(n)", number: full ? 0 : n, display: d, isFullScreen: full, isCurrent: false, managedID: n)
    }

    func testStepsOnSameDisplay() {
        XCTAssertEqual(DeskRun.steps(from: desk(3, "A"), to: desk(5, "A")), 2)
        XCTAssertEqual(DeskRun.steps(from: desk(5, "A"), to: desk(1, "A")), -4)
        XCTAssertEqual(DeskRun.steps(from: desk(2, "A"), to: desk(2, "A")), 0)
    }

    func testNoStepsAcrossDisplaysOrFullScreen() {
        XCTAssertNil(DeskRun.steps(from: desk(1, "A"), to: desk(2, "B")))
        XCTAssertNil(DeskRun.steps(from: desk(1, "A", full: true), to: desk(2, "A")))
    }

    func testOnlyAnUnambiguousWindowIsUsed() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(DeskRun.uniqueMatch([nil, CGRect(x: 0, y: 0, width: 10, height: 10), target.offsetBy(dx: 1, dy: 1)], for: target), 2)
        XCTAssertNil(DeskRun.uniqueMatch([target, target], for: target), "zwei gleich große Fenster übereinander → auslassen")
        XCTAssertNil(DeskRun.uniqueMatch([CGRect(x: 0, y: 0, width: 10, height: 10)], for: target))
    }

    func testUnreadableSpacesAreReportedNotTreatedAsMissing() {
        XCTAssertEqual(DeskRun.blocker(.init(spacesReadable: false), automatic: false, lastAutomatic: nil, now: now), .spacesUnavailable)
    }
}
