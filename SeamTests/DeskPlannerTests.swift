import XCTest
@testable import Seam

/// Schritt 3: Soll gegen Ist. Abläufe nach den Messungen vom 19.10.; Apps und Namen erfunden.
final class DeskPlannerTests: XCTestCase {

    private let main = "HAUPT", side = "NEBEN"
    private let screens = DeskScreens(frames: ["HAUPT": CGRect(x: 0, y: 0, width: 3000, height: 1400),
                                               "NEBEN": CGRect(x: 800, y: 1400, width: 1900, height: 1000)],
                                      primary: "HAUPT")

    private func desk(_ key: String, _ number: Int, _ display: String, id: Int) -> SpaceInfo {
        SpaceInfo(key: key, number: number, display: display, isFullScreen: false, isCurrent: false, managedID: id)
    }
    private func entry(_ bundle: String, _ name: String?, _ display: String, _ number: Int, _ r: CGRect) -> DeskLayoutEntry {
        DeskLayoutEntry(bundleID: bundle, desk: DeskRef(name: name, display: display, number: number), frames: [DeskFrame(r)])
    }
    private func win(_ bundle: String, _ space: Int, _ r: CGRect, id: Int) -> LiveWindow {
        LiveWindow(bundleID: bundle, spaceIDs: [space], frame: r, windowID: id)
    }

    /// Sollzustand: 5 Spaces Hauptbildschirm, 3 Nebenbildschirm.
    private var spaces: [SpaceInfo] {
        [desk("haupt:HAUPT", 1, main, id: 1), desk("P", 2, main, id: 5), desk("C", 3, main, id: 6),
         desk("S", 4, main, id: 7), desk("G", 5, main, id: 8),
         desk("T", 1, side, id: 11), desk("R", 2, side, id: 12), desk("X", 3, side, id: 13)]
    }
    private var names: [String: String] {
        ["haupt:HAUPT": "Arbeit", "P": "Privat", "C": "Code", "S": "Sozial", "G": "Grafik",
         "T": "Team", "R": "Prod", "X": "Term"]
    }
    private let mailRel = CGRect(x: 10, y: 10, width: 800, height: 600)
    private let chatRel = CGRect(x: 5, y: 40, width: 950, height: 900)
    private var layout: DeskLayout {
        DeskLayout(entries: [entry("com.example.mail", "Privat", main, 2, mailRel),
                             entry("com.example.chat", "Team", side, 1, chatRel),
                             entry("com.example.notes", "Prod", side, 2, CGRect(x: 0, y: 0, width: 900, height: 900)),
                             entry("com.example.term", "Term", side, 3, CGRect(x: 300, y: 100, width: 1300, height: 800)),
                             entry("com.example.photo", "Grafik", main, 5, CGRect(x: 500, y: 40, width: 2500, height: 1300))])
    }
    /// Alles am Platz (Rahmen global = relativ + Bildschirm-Ursprung).
    private var placed: [LiveWindow] {
        [win("com.example.mail", 5, mailRel, id: 100),
         win("com.example.chat", 11, chatRel.offsetBy(dx: 800, dy: 1400), id: 101),
         win("com.example.notes", 12, CGRect(x: 800, y: 1400, width: 900, height: 900), id: 102),
         win("com.example.term", 13, CGRect(x: 1100, y: 1500, width: 1300, height: 800), id: 103),
         win("com.example.photo", 8, CGRect(x: 500, y: 40, width: 2500, height: 1300), id: 104)]
    }

    private func plan(_ s: [SpaceInfo], _ n: [String: String], _ w: [LiveWindow], _ l: DeskLayout? = nil) -> DeskPlan {
        DeskPlanner.plan(layout: l ?? layout, spaces: s, names: n, windows: w, screens: screens)
    }

    func testEverythingInPlaceMeansNothingToDo() {
        let p = plan(spaces, names, placed)
        XCTAssertEqual(p, DeskPlan())
        XCTAssertFalse(p.deviates)
    }

    func testSmallDeviationWithinToleranceIsIgnored() {
        var w = placed
        w[0] = win("com.example.mail", 5, mailRel.offsetBy(dx: 2, dy: -1), id: 100)
        XCTAssertTrue(plan(spaces, names, w).moves.isEmpty)
    }

    func testWrongFrameOnRightDeskOnlySetsFrame() {
        var w = placed
        w[0] = win("com.example.mail", 5, CGRect(x: 200, y: 200, width: 600, height: 500), id: 100)
        let p = plan(spaces, names, w)
        XCTAssertEqual(p.moves, [DeskMove(windowID: 100, bundleID: "com.example.mail", target: spaces[1],
                                          frame: mailRel, changesSpace: false)])
    }

    func testWrongDeskNeedsSpaceChange() {
        var w = placed
        w[1] = win("com.example.chat", 6, CGRect(x: 100, y: 100, width: 950, height: 900), id: 101)
        let p = plan(spaces, names, w)
        XCTAssertEqual(p.moves.first?.target.key, "T")
        XCTAssertEqual(p.moves.first?.changesSpace, true)
        XCTAssertEqual(p.moves.first?.frame, chatRel.offsetBy(dx: 800, dy: 1400))
    }

    /// Neustart 1 (gemessen 11:24): Space 1 des Nebenbildschirms neu (erbt „Team“, Schritt 1),
    /// Space 2 + 3 MIT Kennung ans Ende des Hauptbildschirms; alle Neben-Fenster auf dem neuen Space.
    func testRestartOneReportsMovedDesksAndStillPlacesWhatItCan() {
        let after = [desk("haupt:HAUPT", 1, main, id: 1), desk("P", 2, main, id: 5), desk("C", 3, main, id: 6),
                     desk("S", 4, main, id: 7), desk("G", 5, main, id: 8), desk("R", 6, main, id: 12),
                     desk("X", 7, main, id: 13), desk("NEU", 1, side, id: 20)]
        var n = names; n["NEU"] = "Team"; n["T"] = nil
        let w = [win("com.example.mail", 5, mailRel, id: 100),
                 win("com.example.chat", 20, chatRel.offsetBy(dx: 800, dy: 1400), id: 101),
                 win("com.example.notes", 20, CGRect(x: 900, y: 1450, width: 900, height: 900), id: 102),
                 win("com.example.term", 20, CGRect(x: 1100, y: 1500, width: 1300, height: 800), id: 103),
                 win("com.example.photo", 6, CGRect(x: 500, y: 40, width: 2500, height: 1300), id: 104)]
        let p = plan(after, n, w)
        XCTAssertEqual(p.issues, [DeskIssue(desk: DeskRef(name: "Prod", display: side, number: 2), kind: .onOtherDisplay(main)),
                                  DeskIssue(desk: DeskRef(name: "Term", display: side, number: 3), kind: .onOtherDisplay(main))])
        XCTAssertEqual(Set(p.skipped.map(\.bundleID)), ["com.example.notes", "com.example.term"])
        XCTAssertTrue(p.skipped.allSatisfy { $0.reason == .deskUnavailable })
        XCTAssertEqual(p.moves.map(\.bundleID), ["com.example.photo"], "Chat sitzt schon, Photo muss zurück auf Grafik")
        XCTAssertEqual(p.moves.first?.changesSpace, true)
        XCTAssertTrue(p.deviates)
    }

    /// Neustart 2 (gemessen 12:21): „Grafik“ landet auf dem Nebenbildschirm, „Team“ ist weg.
    func testRestartTwoReportsAllFourProblems() {
        let after = [desk("haupt:HAUPT", 1, main, id: 1), desk("P", 2, main, id: 5), desk("C", 3, main, id: 6),
                     desk("S", 4, main, id: 7), desk("R", 5, main, id: 12), desk("X", 6, main, id: 13),
                     desk("G", 1, side, id: 8)]
        var n = names; n["T"] = nil
        let p = plan(after, n, placed)
        XCTAssertEqual(Set(p.issues.map(\.desk.name)), ["Team", "Prod", "Term", "Grafik"])
        XCTAssertEqual(p.issues.first { $0.desk.name == "Team" }?.kind, .missing)
        XCTAssertEqual(p.issues.first { $0.desk.name == "Grafik" }?.kind, .onOtherDisplay(side))
    }

    func testAppNotRunningIsSkippedAndDoesNotCountAsDeviation() {
        let p = plan(spaces, names, Array(placed.dropLast()))
        XCTAssertEqual(p.skipped, [DeskSkip(bundleID: "com.example.photo", reason: .notRunning)])
        XCTAssertFalse(p.deviates)
    }

    func testWindowsOnAllSpacesOrMinimizedAreIgnored() {
        let w = placed + [LiveWindow(bundleID: "com.example.mail", spaceIDs: [1, 5, 6], frame: .zero, windowID: 200),
                          LiveWindow(bundleID: "com.example.mail", spaceIDs: [], frame: .zero, windowID: 201)]
        XCTAssertTrue(plan(spaces, names, w).moves.isEmpty)
    }

    func testUnnamedDeskResolvesByPlace() {
        let l = DeskLayout(entries: [entry("com.example.mail", nil, main, 3, mailRel)])
        let p = plan(spaces, [:], [win("com.example.mail", 5, mailRel, id: 100)], l)
        XCTAssertEqual(p.moves.first?.target.key, "C")
    }

    func testSecondWindowWithoutSavedFrameKeepsSizeButMovesDesk() {
        let w = placed + [win("com.example.mail", 6, CGRect(x: 50, y: 50, width: 400, height: 300), id: 300)]
        let p = plan(spaces, names, w)
        XCTAssertEqual(p.moves, [DeskMove(windowID: 300, bundleID: "com.example.mail", target: spaces[1],
                                          frame: nil, changesSpace: true)])
    }

    /// Zwei Fenster einer App tauschen die Stapel-Reihenfolge: Jede Größe bleibt beim ähnlichsten
    /// Fenster, niemand muss umziehen.
    func testFramesFollowMostSimilarWindowNotStackOrder() {
        let a = CGRect(x: 0, y: 0, width: 1000, height: 800), b = CGRect(x: 1500, y: 100, width: 600, height: 500)
        let l = DeskLayout(entries: [DeskLayoutEntry(bundleID: "com.example.web", desk: DeskRef(name: "Arbeit", display: main, number: 1),
                                                     frames: [DeskFrame(a), DeskFrame(b)])])
        let p = plan(spaces, names, [win("com.example.web", 1, b, id: 1), win("com.example.web", 1, a, id: 2)], l)
        XCTAssertTrue(p.moves.isEmpty)
    }

    /// rafter-code-review 19.10., Fund 1 (E5): Ein gespeicherter Rahmen außerhalb des Bildschirms
    /// (veränderte Daten, andere Auflösung) wird auf den Bildschirm geholt.
    func testTargetFrameIsClampedToScreen() {
        let off = CGRect(x: -5000, y: 9000, width: 5000, height: 800)
        let l = DeskLayout(entries: [entry("com.example.mail", "Privat", main, 2, off)])
        let p = plan(spaces, names, [win("com.example.mail", 5, mailRel, id: 100)], l)
        XCTAssertEqual(p.moves.first?.frame, CGRect(x: 0, y: 600, width: 3000, height: 800), "ganz auf dem Hauptbildschirm (3000 × 1400)")
    }

    func testDuplicateNamePrefersSavedPlace() {
        var n = names; n["S"] = "Privat"
        let p = plan(spaces, n, [win("com.example.mail", 7, mailRel, id: 100)],
                     DeskLayout(entries: [entry("com.example.mail", "Privat", main, 2, mailRel)]))
        XCTAssertEqual(p.moves.first?.target.key, "P")
    }

    // MARK: code-audit 19.10.

    func testFullScreenWindowIsNotAMove() {
        let full = SpaceInfo(key: "V", number: 0, display: main, isFullScreen: true, isCurrent: true, managedID: 99)
        let p = plan(spaces + [full], names, Array(placed.dropFirst()) + [win("com.example.mail", 99, mailRel, id: 100)])
        XCTAssertTrue(p.moves.isEmpty)
        XCTAssertEqual(p.skipped, [DeskSkip(bundleID: "com.example.mail", reason: .notRunning)])
    }

    func testTerminalStyleSizeSnappingCountsAsFitting() {
        var w = placed
        w[0] = win("com.example.mail", 5, CGRect(x: 10, y: 10, width: 790, height: 589), id: 100)
        XCTAssertTrue(plan(spaces, names, w).moves.isEmpty, "−10/−11 pt Größe = sitzt")
        w[0] = win("com.example.mail", 5, CGRect(x: 15, y: 10, width: 800, height: 600), id: 100)
        XCTAssertFalse(plan(spaces, names, w).moves.isEmpty, "Lage weiter auf ±2 pt")
    }

    /// Bildschirme teilen sich die Spaces („Main“): ein Fenster auf dem zweiten Bildschirm bleibt dort.
    func testSharedSpacesKeepWindowOnItsScreen() {
        let shared = [SpaceInfo(key: "S", number: 1, display: "Main", isFullScreen: false, isCurrent: true, managedID: 3)]
        let two = DeskScreens(frames: ["HAUPT": CGRect(x: 0, y: 0, width: 3000, height: 1400),
                                       "NEBEN": CGRect(x: 3000, y: 0, width: 1900, height: 1000)], primary: "HAUPT")
        let r = CGRect(x: 3400, y: 100, width: 800, height: 600)
        let l = DeskLayout(entries: [entry("com.example.a", nil, "Main", 1, r)])
        let p = DeskPlanner.plan(layout: l, spaces: shared, names: [:],
                                 windows: [win("com.example.a", 3, CGRect(x: 10, y: 10, width: 800, height: 600), id: 1)], screens: two)
        XCTAssertEqual(p.moves.first?.frame, r)
    }
}
