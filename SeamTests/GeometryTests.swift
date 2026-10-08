import CoreGraphics
import XCTest
@testable import Seam

/// Reine Rechenlogik. Erwartungswerte sind von Hand aus Magnets Raster
/// (24 × 12 quer, 12 × 24 hochkant) gerechnet, nicht aus dem Code abgeleitet.
final class GeometryTests: XCTestCase {

    // Michaels Hauptbildschirm: 3440 × 1440, sichtbarer Bereich unter der Menüleiste.
    private let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let visible = CGRect(x: 0, y: 40, width: 3440, height: 1400)

    // MARK: Raster

    func testLeftHalfWithGapFive() {
        let r = Geometry.rect(for: Cells(0, 0, 12, 12), in: visible, .landscape, gap: 5)
        // links voller Abstand 5, rechts zur Mitte nur 2,5 (zusammen mit dem Nachbarn 5)
        // Kanten: 0 + 5 = 5 und 1720 − 2,5 = 1717,5 → 1718, also 1713 breit
        XCTAssertEqual(r, CGRect(x: 5, y: 45, width: 1713, height: 1390))
    }

    func testRightHalfMeetsLeftHalfWithExactlyOneGap() {
        let l = Geometry.rect(for: Cells(0, 0, 12, 12), in: visible, .landscape, gap: 5)
        let r = Geometry.rect(for: Cells(12, 0, 12, 12), in: visible, .landscape, gap: 5)
        XCTAssertEqual(r.minX - l.maxX, 5)
        XCTAssertEqual(r.maxX, 3435)
    }

    func testThirdsWithoutGapTileExactly() {
        let a = Geometry.rect(for: Cells(0, 0, 8, 12), in: visible, .landscape, gap: 0)
        let b = Geometry.rect(for: Cells(8, 0, 8, 12), in: visible, .landscape, gap: 0)
        let c = Geometry.rect(for: Cells(16, 0, 8, 12), in: visible, .landscape, gap: 0)
        XCTAssertEqual(a.width + b.width + c.width, 3440, accuracy: 1)
        XCTAssertEqual(b.minX, a.maxX, accuracy: 1)
        XCTAssertEqual(c.maxX, 3440, accuracy: 1)
    }

    func testPortraitTopThird() {
        let v = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        XCTAssertEqual(Orientation.of(v), .portrait)
        let r = Geometry.rect(for: Layout.spec(.firstThird, .portrait)!.target!, in: v, .portrait, gap: 0)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1080, height: 640))
    }

    // MARK: Kürzel (Michaels Magnet-Belegung)

    func testMichaelsShortcutsLandscape() {
        XCTAssertEqual(Layout.spec(.left, .landscape)?.key.label, "⌃⌥←")
        XCTAssertEqual(Layout.spec(.topLeft, .landscape)?.key.label, "⌃⌥U")
        XCTAssertEqual(Layout.spec(.firstThird, .landscape)?.key.label, "⌃⌘L")
        XCTAssertEqual(Layout.spec(.maximize, .landscape)?.key.label, "⌃⌘↩")
        XCTAssertEqual(Layout.spec(.nextDisplay, .landscape)?.key.label, "⌃⌥⌘→")
        XCTAssertEqual(Layout.spec(.restore, .landscape)?.key.label, "⌃⌥⌫")
    }

    func testSameKeyMeansDifferentCommandPerOrientation() {
        let e = KeyCombo(keyCode: 14, modifiers: KeyCombo.ctrlOpt)
        XCTAssertEqual(Layout.command(for: e, .landscape), .firstTwoThirds)   // links zwei Drittel
        XCTAssertEqual(Layout.command(for: e, .portrait), .firstTwoThirds)    // oben zwei Drittel
        XCTAssertEqual(Layout.spec(.firstTwoThirds, .portrait)?.target, Cells(0, 0, 12, 16))
    }

    func testNoDuplicateShortcutWithinOneOrientation() {
        for o in [Orientation.landscape, .portrait] {
            let keys = Layout.specs(o).map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "doppeltes Kürzel in \(o)")
        }
    }

    // MARK: Andocken per Ziehen

    func testLeftEdgeMiddleSnapsLeftHalf() {
        let p = CGPoint(x: 0, y: 720)
        XCTAssertEqual(Geometry.activeCommand(at: p, screen: screen, .landscape, engaged: false), .left)
    }

    func testTopLeftCornerSnapsQuarter() {
        XCTAssertEqual(Geometry.activeCommand(at: CGPoint(x: 1, y: 1), screen: screen, .landscape, engaged: false), .topLeft)
    }

    func testTopEdgeMaximizes() {
        XCTAssertEqual(Geometry.activeCommand(at: CGPoint(x: 1720, y: 0), screen: screen, .landscape, engaged: false), .maximize)
    }

    func testBottomEdgeThirds() {
        // Spalte = x / (3440/24 ≈ 143,3): 300 → Spalte 2 (linkes Drittel), 1720 → 12 (mittleres)
        XCTAssertEqual(Geometry.activeCommand(at: CGPoint(x: 300, y: 1439), screen: screen, .landscape, engaged: false), .firstThird)
        XCTAssertEqual(Geometry.activeCommand(at: CGPoint(x: 1720, y: 1439), screen: screen, .landscape, engaged: false), .centerThird)
        XCTAssertEqual(Geometry.activeCommand(at: CGPoint(x: 1100, y: 1439), screen: screen, .landscape, engaged: false), .firstTwoThirds)
    }

    func testInteriorZoneOnlyWhenEngaged() {
        // Zeile 10 (y 1200..1320), Spalte 11–12: mittlere zwei Drittel — nicht am Rand.
        let p = CGPoint(x: 1720, y: 1250)
        XCTAssertNil(Geometry.activeCommand(at: p, screen: screen, .landscape, engaged: false))
        XCTAssertEqual(Geometry.activeCommand(at: p, screen: screen, .landscape, engaged: true), .centerTwoThirds)
    }

    func testMiddleOfScreenNeverSnaps() {
        XCTAssertNil(Geometry.activeCommand(at: CGPoint(x: 1720, y: 720), screen: screen, .landscape, engaged: true))
    }

    // MARK: Mitziehen

    private let leftWin = CGRect(x: 0, y: 40, width: 1720, height: 1400)
    private let rightWin = CGRect(x: 1725, y: 40, width: 1715, height: 1400)

    func testDraggingRightEdgeLeftWidensRightWindow() {
        let now = CGRect(x: 0, y: 40, width: 1420, height: 1400)    // 300 px schmaler
        let out = Geometry.linkedFrames(start: leftWin, now: now,
                                        neighbors: [.init(id: 1, frame: rightWin)], gap: 5)
        // Abstand 5 bleibt, rechter Rand 3440 bleibt
        XCTAssertEqual(out[1], CGRect(x: 1425, y: 40, width: 2015, height: 1400))
    }

    func testDraggingLeftEdgeOfRightWindowShrinksLeftWindow() {
        let now = CGRect(x: 1925, y: 40, width: 1515, height: 1400)  // linke Kante 200 nach rechts
        let out = Geometry.linkedFrames(start: rightWin, now: now,
                                        neighbors: [.init(id: 0, frame: leftWin)], gap: 5)
        XCTAssertEqual(out[0], CGRect(x: 0, y: 40, width: 1920, height: 1400))
    }

    func testMovingWindowDoesNotDragNeighbors() {
        let moved = leftWin.offsetBy(dx: -100, dy: 0)
        XCTAssertTrue(Geometry.linkedFrames(start: leftWin, now: moved,
                                            neighbors: [.init(id: 1, frame: rightWin)], gap: 5).isEmpty)
    }

    func testUnrelatedWindowStays() {
        let far = CGRect(x: 2600, y: 40, width: 800, height: 600)   // berührt die Kante nicht
        let now = CGRect(x: 0, y: 40, width: 1420, height: 1400)
        XCTAssertNil(Geometry.linkedFrames(start: leftWin, now: now,
                                           neighbors: [.init(id: 2, frame: far)], gap: 5)[2])
    }

    func testStackedWindowOnSameSideFollowsSeam() {
        // Links zwei Fenster übereinander (Viertel), rechts eine Hälfte.
        let topLeft = CGRect(x: 0, y: 40, width: 1720, height: 697)
        let bottomLeft = CGRect(x: 0, y: 742, width: 1720, height: 698)
        let now = CGRect(x: 0, y: 40, width: 1520, height: 697)       // Naht 200 nach links
        let out = Geometry.linkedFrames(start: topLeft, now: now, neighbors: [
            .init(id: 1, frame: rightWin), .init(id: 2, frame: bottomLeft),
        ], gap: 5)
        XCTAssertEqual(out[1]?.minX, 1525)                             // rechte Hälfte folgt
        XCTAssertEqual(out[2], CGRect(x: 0, y: 742, width: 1520, height: 698))  // untere linke ebenso
    }

    func testVerticalSeam() {
        let top = CGRect(x: 0, y: 40, width: 1720, height: 700)
        let bottom = CGRect(x: 0, y: 745, width: 1720, height: 695)
        let now = CGRect(x: 0, y: 40, width: 1720, height: 900)        // untere Kante 200 runter
        let out = Geometry.linkedFrames(start: top, now: now, neighbors: [.init(id: 1, frame: bottom)], gap: 5)
        XCTAssertEqual(out[1], CGRect(x: 0, y: 945, width: 1720, height: 495))
    }

    func testLinkCandidates() {
        XCTAssertTrue(Geometry.isLinkCandidate(rightWin, to: leftWin, gap: 5))
        XCTAssertFalse(Geometry.isLinkCandidate(CGRect(x: 2600, y: 40, width: 800, height: 600), to: leftWin, gap: 5))
    }

    // MARK: Koordinaten und Grenzen

    func testAppKitToAXOnPrimary() {
        // AppKit: sichtbarer Bereich beginnt unten bei 0, 1400 hoch (Menüleiste oben 40)
        XCTAssertEqual(Geometry.toAX(CGRect(x: 0, y: 0, width: 3440, height: 1400), primaryHeight: 1440),
                       CGRect(x: 0, y: 40, width: 3440, height: 1400))
    }

    func testClampKeepsWindowOnScreen() {
        let r = Geometry.clamp(CGRect(x: 3300, y: -50, width: 400, height: 300), to: visible)
        XCTAssertEqual(r, CGRect(x: 3040, y: 40, width: 400, height: 300))
    }

    func testTransferBetweenScreensKeepsProportion() {
        let to = CGRect(x: 846, y: 1440, width: 1920, height: 1080)
        let r = Geometry.transfer(CGRect(x: 0, y: 40, width: 1720, height: 1400), from: visible, to: to)
        XCTAssertEqual(r.width, 960, accuracy: 1)
        XCTAssertEqual(r.minX, 846, accuracy: 1)
    }
}
