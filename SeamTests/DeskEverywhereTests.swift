import XCTest
@testable import Seam

/// Fenster „auf allen Schreibtischen“ eines Bildschirms (06.11.). Nachgestellt nach der Messung:
/// Beim Aufwachen meldete sich der Hauptbildschirm kurz ab, macOS schob ein Finder-Fenster von allen
/// Schreibtischen des kleinen Bildschirms auf alle Schreibtische des Hauptbildschirms und verkleinerte
/// es (1344×474 → 1080×427). Apps erfunden.
final class DeskEverywhereTests: XCTestCase {

    private let main = "HAUPT", small = "KLEIN"
    private let screens = DeskScreens(frames: ["HAUPT": CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                               "KLEIN": CGRect(x: 1136, y: 1440, width: 1344, height: 504)],
                                      primary: "HAUPT")
    private var spaces: [SpaceInfo] {
        [SpaceInfo(key: "A", number: 1, display: main, isFullScreen: false, isCurrent: true, managedID: 1),
         SpaceInfo(key: "B", number: 2, display: main, isFullScreen: false, isCurrent: false, managedID: 6),
         SpaceInfo(key: "K1", number: 1, display: small, isFullScreen: false, isCurrent: false, managedID: 15),
         SpaceInfo(key: "K2", number: 2, display: small, isFullScreen: false, isCurrent: true, managedID: 1141)]
    }
    private let onSmall = CGRect(x: 1136, y: 1470, width: 1344, height: 474)
    private let files = "com.example.files"

    private func capture(_ windows: [LiveWindow]) -> DeskLayout {
        DeskLayouts.capture(windows: windows, spaces: spaces, names: [:], screens: screens, ownBundleID: nil)
    }

    func testWindowOnAllDesksOfOneScreenIsCaptured() {
        let layout = capture([LiveWindow(bundleID: files, spaceIDs: [1141, 15], frame: onSmall, windowID: 7)])
        XCTAssertTrue(layout.entries.isEmpty, "gehört auf keinen einzelnen Schreibtisch")
        XCTAssertEqual(layout.everywhere, [DeskEverywhereEntry(bundleID: files, display: small,
                                                               frames: [DeskFrame(CGRect(x: 0, y: 30, width: 1344, height: 474))])])
    }

    func testWindowOnDesksOfTwoScreensOrUnknownDesksIsNotCaptured() {
        let layout = capture([LiveWindow(bundleID: files, spaceIDs: [1, 15], frame: onSmall, windowID: 7),
                              LiveWindow(bundleID: "com.example.other", spaceIDs: [1, 999], frame: onSmall, windowID: 8)])
        XCTAssertTrue(layout.isEmpty)
    }

    func testSameAppCanHaveOneDeskAndWindowsEverywhere() {
        let layout = capture([LiveWindow(bundleID: files, spaceIDs: [6], frame: CGRect(x: 100, y: 100, width: 800, height: 600), windowID: 1),
                              LiveWindow(bundleID: files, spaceIDs: [1141, 15], frame: onSmall, windowID: 2)])
        XCTAssertEqual(layout.entries.map(\.bundleID), [files])
        XCTAssertEqual(layout.everywhere.map(\.display), [small])
    }

    func testMovedBackFromTheMainScreenByFrameOnly() {
        let layout = capture([LiveWindow(bundleID: files, spaceIDs: [1141, 15], frame: onSmall, windowID: 7)])
        // Nach dem Aufwachen: auf allen Schreibtischen des Hauptbildschirms, kleiner.
        let moved = LiveWindow(bundleID: files, spaceIDs: [1, 6], frame: CGRect(x: 0, y: 958, width: 1080, height: 427), windowID: 7)
        let plan = DeskPlanner.plan(layout: layout, spaces: spaces, names: [:], windows: [moved], screens: screens)
        XCTAssertEqual(plan.moves.count, 1)
        XCTAssertEqual(plan.moves.first?.frame, onSmall)
        XCTAssertEqual(plan.moves.first?.changesSpace, false, "kein Space-Wechsel, keine Taste")
        XCTAssertEqual(plan.moves.first?.target.display, small)
        XCTAssertTrue(plan.deviates)
    }

    func testWindowInPlaceNeedsNothing() {
        let w = LiveWindow(bundleID: files, spaceIDs: [1141, 15], frame: onSmall, windowID: 7)
        let plan = DeskPlanner.plan(layout: capture([w]), spaces: spaces, names: [:], windows: [w], screens: screens)
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertFalse(plan.deviates)
    }

    func testNotRunningAndScreenMissing() {
        let layout = capture([LiveWindow(bundleID: files, spaceIDs: [1141, 15], frame: onSmall, windowID: 7)])
        XCTAssertEqual(DeskPlanner.plan(layout: layout, spaces: spaces, names: [:], windows: [], screens: screens).skipped,
                       [DeskSkip(bundleID: files, reason: .notRunning)])
        let onlyMain = spaces.filter { $0.display == main }
        let moved = LiveWindow(bundleID: files, spaceIDs: [1, 6], frame: onSmall, windowID: 7)
        let plan = DeskPlanner.plan(layout: layout, spaces: onlyMain, names: [:], windows: [moved],
                                    screens: DeskScreens(frames: ["HAUPT": screens.frames["HAUPT"]!], primary: "HAUPT"))
        XCTAssertEqual(plan.skipped, [DeskSkip(bundleID: files, reason: .deskUnavailable)])
        XCTAssertTrue(plan.moves.isEmpty)
    }

    // MARK: Laden (E17c)

    func testOldLayoutWithoutEverywhereStillLoads() throws {
        let old = #"{"K":{"entries":[{"bundleID":"com.example.mail","desk":{"display":"HAUPT","number":1},"#
            + #""frames":[{"x":1,"y":2,"width":300,"height":200}]}]}}"#
        let loaded = DeskLayouts.decode(Data(old.utf8))
        XCTAssertEqual(loaded["K"]?.entries.count, 1)
        XCTAssertEqual(loaded["K"]?.everywhere, [])
    }

    func testEverywhereIsCheckedOnLoad() {
        let bad = DeskFrame(CGRect(x: 40_000, y: 0, width: 500, height: 300))   // kein echter Bildschirm
        let good = DeskFrame(CGRect(x: 0, y: 0, width: 500, height: 300))
        let layout = DeskLayout(entries: [], everywhere: [
            DeskEverywhereEntry(bundleID: files, display: small, frames: [good]),
            DeskEverywhereEntry(bundleID: files, display: small, frames: [good]),        // doppelt
            DeskEverywhereEntry(bundleID: "kein bundle", display: small, frames: [good]),
            DeskEverywhereEntry(bundleID: "com.example.bad", display: small, frames: [bad]),
            DeskEverywhereEntry(bundleID: "com.example.other", display: "", frames: [good]),
        ])
        let loaded = DeskLayouts.decode(DeskLayouts.encode(["K": layout]))
        XCTAssertEqual(loaded["K"]?.everywhere, [DeskEverywhereEntry(bundleID: files, display: small, frames: [good])])
    }
}
