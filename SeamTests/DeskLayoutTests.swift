import XCTest
@testable import Seam

/// E17c: Layout aufnehmen, speichern, mit Grenzen laden. Apps und Namen erfunden.
final class DeskLayoutTests: XCTestCase {

    private let main = "HAUPT", side = "NEBEN"
    private let screens = DeskScreens(frames: ["HAUPT": CGRect(x: 0, y: 0, width: 3000, height: 1400),
                                               "NEBEN": CGRect(x: 800, y: 1400, width: 1900, height: 1000)],
                                      primary: "HAUPT")

    private func desk(_ key: String, _ number: Int, _ display: String, id: Int, full: Bool = false) -> SpaceInfo {
        SpaceInfo(key: key, number: number, display: display, isFullScreen: full, isCurrent: false, managedID: id)
    }
    private var spaces: [SpaceInfo] {
        [desk("haupt:HAUPT", 1, main, id: 1), desk("B", 2, main, id: 5), desk("V", 0, main, id: 9, full: true),
         desk("T", 1, side, id: 11)]
    }
    private let names = ["haupt:HAUPT": "Arbeit", "T": "Team"]

    private func capture(_ w: [LiveWindow], own: String? = "dev.mwlr.seam") -> DeskLayout {
        DeskLayouts.capture(windows: w, spaces: spaces, names: names, screens: screens, ownBundleID: own)
    }

    func testCaptureMapsAppToDeskWithFrameRelativeToScreen() {
        let l = capture([LiveWindow(bundleID: "com.example.chat", spaceIDs: [11], frame: CGRect(x: 850, y: 1480, width: 950, height: 900))])
        XCTAssertEqual(l.entries.count, 1)
        XCTAssertEqual(l.entries[0].desk, DeskRef(name: "Team", display: side, number: 1))
        XCTAssertEqual(l.entries[0].frames, [DeskFrame(CGRect(x: 50, y: 80, width: 950, height: 900))])
    }

    func testUnnamedDeskHasNoName() {
        let l = capture([LiveWindow(bundleID: "com.example.mail", spaceIDs: [5], frame: CGRect(x: 10, y: 10, width: 500, height: 400))])
        XCTAssertEqual(l.entries[0].desk, DeskRef(name: nil, display: main, number: 2))
    }

    func testSkipsOwnAllSpacesMinimizedFullScreenAndUnknownSpace() {
        let r = CGRect(x: 10, y: 10, width: 500, height: 400)
        let l = capture([LiveWindow(bundleID: "dev.mwlr.seam", spaceIDs: [1], frame: r),
                         LiveWindow(bundleID: "com.example.finder", spaceIDs: [1, 5, 11], frame: r),
                         LiveWindow(bundleID: "com.example.min", spaceIDs: [], frame: r),
                         LiveWindow(bundleID: "com.example.video", spaceIDs: [9], frame: r),
                         LiveWindow(bundleID: "com.example.gone", spaceIDs: [77], frame: r)])
        XCTAssertTrue(l.entries.isEmpty)
    }

    func testOneAppOneDeskFrontmostWins() {
        let l = capture([LiveWindow(bundleID: "com.example.edit", spaceIDs: [5], frame: CGRect(x: 10, y: 10, width: 500, height: 400)),
                         LiveWindow(bundleID: "com.example.edit", spaceIDs: [1], frame: CGRect(x: 20, y: 20, width: 500, height: 400)),
                         LiveWindow(bundleID: "com.example.edit", spaceIDs: [5], frame: CGRect(x: 30, y: 30, width: 600, height: 400))])
        XCTAssertEqual(l.entries.count, 1)
        XCTAssertEqual(l.entries[0].desk.number, 2)
        XCTAssertEqual(l.entries[0].frames.map(\.x), [10, 30], "Fenster auf anderem Space zählt nicht")
    }

    func testSharedSpacesUsePrimaryDisplay() {
        let shared = [SpaceInfo(key: "S", number: 1, display: "Main", isFullScreen: false, isCurrent: true, managedID: 3)]
        let win = LiveWindow(bundleID: "com.example.a", spaceIDs: [3], frame: CGRect(x: 100, y: 100, width: 500, height: 400))
        let l = DeskLayouts.capture(windows: [win], spaces: shared, names: [:], screens: screens, ownBundleID: nil)
        XCTAssertEqual(l.entries.first?.frames.first?.x, 100)
    }

    func testCombinationKeyIgnoresOrderAndDuplicates() {
        XCTAssertEqual(DeskLayouts.combinationKey(["B", "A", "B"]), "A+B")
    }

    // MARK: Laden mit Grenzen

    func testRoundTrip() {
        let l = capture([LiveWindow(bundleID: "com.example.chat", spaceIDs: [11], frame: CGRect(x: 850, y: 1480, width: 950, height: 900))])
        XCTAssertEqual(DeskLayouts.decode(DeskLayouts.encode(["A+B": l])), ["A+B": l])
    }

    func testHostileDataIsDropped() {
        let json = """
        {"A": {"entries": [
          {"bundleID": "com.example.ok", "desk": {"name": "  Team\\u0007 ", "display": "D", "number": 1},
           "frames": [{"x": 1, "y": 2, "width": 300, "height": 200}]},
          {"bundleID": "com.example.ok", "desk": {"display": "D", "number": 2}, "frames": [{"x": 1, "y": 2, "width": 300, "height": 200}]},
          {"bundleID": "../../etc", "desk": {"display": "D", "number": 1}, "frames": [{"x": 1, "y": 2, "width": 300, "height": 200}]},
          {"bundleID": "com.example.weit", "desk": {"display": "D", "number": 1}, "frames": [{"x": 99999, "y": 2, "width": 300, "height": 200}]},
          {"bundleID": "com.example.null", "desk": {"display": "D", "number": 1}, "frames": [{"x": 1, "y": 2, "width": 0, "height": 200}]},
          {"bundleID": "com.example.platz", "desk": {"display": "D", "number": 99}, "frames": [{"x": 1, "y": 2, "width": 300, "height": 200}]}
        ]}}
        """
        let out = DeskLayouts.decode(Data(json.utf8))
        XCTAssertEqual(out["A"]?.entries.map(\.bundleID), ["com.example.ok"], "Doppelte, Pfade, Riesen-/Nullrahmen, Platz 99 verworfen")
        XCTAssertEqual(out["A"]?.entries.first?.desk.name, "Team", "Name bereinigt")
    }

    func testGarbageAndOversizeYieldNothing() {
        XCTAssertEqual(DeskLayouts.decode(Data("kein json".utf8)), [:])
        XCTAssertEqual(DeskLayouts.decode(nil), [:])
        XCTAssertEqual(DeskLayouts.decode(Data(repeating: 0x20, count: 1_000_001)), [:])
    }

    // MARK: Einstellungen

    @MainActor
    func testSaveReloadAndDelete() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        let l = capture([LiveWindow(bundleID: "com.example.chat", spaceIDs: [11], frame: CGRect(x: 850, y: 1480, width: 950, height: 900))])
        XCTAssertTrue(p.saveDeskLayout(l, for: "A+B"))
        XCTAssertEqual(Preferences(defaults: d).deskLayouts["A+B"], l)
        XCTAssertTrue(p.saveDeskLayout(DeskLayout(entries: []), for: "A+B"))
        XCTAssertNil(Preferences(defaults: d).deskLayouts["A+B"])
    }

    @MainActor
    func testCombinationLimit() {
        let p = Preferences(defaults: freshDefaults())
        let l = capture([LiveWindow(bundleID: "com.example.chat", spaceIDs: [11], frame: CGRect(x: 850, y: 1480, width: 950, height: 900))])
        for i in 0..<DeskLayouts.maxCombinations { XCTAssertTrue(p.saveDeskLayout(l, for: "K\(i)")) }
        XCTAssertFalse(p.saveDeskLayout(l, for: "zu-viel"))
        XCTAssertTrue(p.saveDeskLayout(l, for: "K0"), "vorhandene Kombination darf ersetzt werden")
    }
}
