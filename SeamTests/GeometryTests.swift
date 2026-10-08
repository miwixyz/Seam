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

    /// Mittlere zwei Drittel: Tastencode 16 wie in Magnet. Die Beschriftung folgt der
    /// Belegung (deutsch „Z“, US „Y“), nicht einer festen US-Tabelle (08.10.: Menü zeigte Y).
    func testLabelFollowsKeyboardLayout() throws {
        let key = try XCTUnwrap(Layout.spec(.centerTwoThirds, .landscape)?.key)
        XCTAssertEqual(key.keyCode, 16)
        let letter = try XCTUnwrap(KeyboardLayout.character(for: 16))
        XCTAssertEqual(key.label, "⌃⌘" + letter)
        if letter == "Z" { XCTAssertEqual(KeyboardLayout.character(for: 6), "Y") }
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

    // MARK: Gepackte Kante (macOS zieht ungepackte Kanten an den Bildschirmrand)

    func testGrabInGapBetweenWindowsMeansLeftEdgeOfRightWindow() {
        // Klick bei x 1720, rechtes Fenster beginnt bei 1723
        let r = CGRect(x: 1723, y: 35, width: 1712, height: 1345)
        XCTAssertEqual(Geometry.grabbedEdges(at: CGPoint(x: 1720, y: 700), frame: r, radius: 8), [.left])
    }

    func testGrabCornerMeansTwoEdges() {
        let r = CGRect(x: 100, y: 100, width: 500, height: 400)
        XCTAssertEqual(Set(Geometry.grabbedEdges(at: CGPoint(x: 601, y: 501), frame: r, radius: 8)), [.right, .bottom])
    }

    func testGrabInsideIsNoEdge() {
        let r = CGRect(x: 100, y: 100, width: 500, height: 400)
        XCTAssertTrue(Geometry.grabbedEdges(at: CGPoint(x: 300, y: 300), frame: r, radius: 8).isEmpty)
    }

    func testUngrabbedRightEdgeSnappedByMacOSIsRestored() {
        // Gemessen: linke Kante 300 nach links gezogen, macOS setzt rechts 3435 → 3440
        let start = CGRect(x: 1723, y: 35, width: 1712, height: 1345)
        let now = CGRect(x: 1423, y: 35, width: 2017, height: 1345)
        XCTAssertEqual(Geometry.keepUngrabbedEdges(now: now, start: start, grabbed: [.left], slack: 10),
                       CGRect(x: 1423, y: 35, width: 2012, height: 1345))
    }

    func testGrabbedEdgeIsNeverReset() {
        let start = CGRect(x: 1723, y: 35, width: 1712, height: 1345)
        let now = CGRect(x: 1718, y: 35, width: 1717, height: 1345)   // nur 5 px gezogen
        XCTAssertEqual(Geometry.keepUngrabbedEdges(now: now, start: start, grabbed: [.left], slack: 10), now)
    }

    // MARK: Nur sichtbare Nachbarn (gemessen 08.10.: Gmail-Fenster hinter TextEdit zog mit)

    func testNeighborHiddenBehindAnotherWindowIsHidden() {
        let leading = CGRect(x: 0, y: 30, width: 1713, height: 1345)
        let textEdit = CGRect(x: 1723, y: 35, width: 1712, height: 1345)        // vorn
        let gmail = CGRect(x: 1724, y: 39, width: 1707, height: 1339)           // dahinter
        let strip = Geometry.contactStrip(of: gmail, to: leading, gap: 5)
        XCTAssertTrue(Geometry.isHidden(strip, by: [textEdit]))
        XCTAssertFalse(Geometry.isHidden(Geometry.contactStrip(of: textEdit, to: leading, gap: 5), by: []))
    }

    func testPartlyVisibleNeighborCounts() {
        let leading = CGRect(x: 0, y: 30, width: 1713, height: 1345)
        let neighbor = CGRect(x: 1723, y: 30, width: 1712, height: 1345)
        let smallInFront = CGRect(x: 1700, y: 200, width: 400, height: 300)    // deckt nur einen Teil
        XCTAssertFalse(Geometry.isHidden(Geometry.contactStrip(of: neighbor, to: leading, gap: 5), by: [smallInFront]))
    }

    func testContactStripIsTheEdgeFacingTheLeadingWindow() {
        let leading = CGRect(x: 0, y: 30, width: 1713, height: 1345)
        let right = CGRect(x: 1718, y: 30, width: 1722, height: 1345)
        XCTAssertEqual(Geometry.contactStrip(of: right, to: leading, gap: 5), CGRect(x: 1718, y: 30, width: 20, height: 1345))
    }

    // MARK: Kürzel setzen den Nachbarn mit (gemessen 08.10.: Outlook/Edge nicht bündig)

    private let v = CGRect(x: 0, y: 30, width: 3440, height: 1355)
    private let leftHalf = CGRect(x: 5, y: 35, width: 1713, height: 1345)

    func testInnerEdgesOfLeftHalf() {
        XCTAssertEqual(Geometry.innerEdges(of: leftHalf, in: v, gap: 5), [.right])
    }

    func testOverlappingEdgeIsPushedToSeam() {
        // gemessen: Edge bei x 1455 (263 px Überlappung)
        let edge = CGRect(x: 1455, y: 35, width: 1980, height: 1337)
        XCTAssertEqual(Geometry.complement(of: edge, target: leftHalf, edge: .right, gap: 5),
                       CGRect(x: 1723, y: 35, width: 1712, height: 1337))
    }

    func testGapIsClosed() {
        // gemessen: Lücke 156 px (Outlook bis 1448, Edge ab 1604)
        let edge = CGRect(x: 1604, y: 35, width: 1836, height: 1345)
        XCTAssertEqual(Geometry.complement(of: edge, target: leftHalf, edge: .right, gap: 5)?.minX, 1723)
    }

    func testFarAwayOrSameSideWindowIsLeftAlone() {
        let far = CGRect(x: 2600, y: 35, width: 800, height: 600)      // 877 px weg
        XCTAssertNil(Geometry.complement(of: far, target: leftHalf, edge: .right, gap: 5))
        let sameSide = CGRect(x: 100, y: 100, width: 900, height: 700)  // Mitte links der Naht
        XCTAssertNil(Geometry.complement(of: sameSide, target: leftHalf, edge: .right, gap: 5))
    }

    func testSmallWindowBesideOnlyPartlyIsLeftAlone() {
        let small = CGRect(x: 1700, y: 1100, width: 600, height: 250)  // deckt < 50 % der Höhe
        XCTAssertNil(Geometry.complement(of: small, target: leftHalf, edge: .right, gap: 5))
    }

    func testPartnerGetsFullHeightBesideAHalf() {
        // gemessen: Edge blieb bei y 290 / Höhe 991
        let edge = CGRect(x: 1455, y: 290, width: 1980, height: 991)
        XCTAssertEqual(Geometry.complement(of: edge, target: leftHalf, edge: .right, gap: 5, visible: v),
                       CGRect(x: 1723, y: 35, width: 1712, height: 1345))
    }

    func testPartnerKeepsHeightBesideAQuarter() {
        let topLeft = CGRect(x: 5, y: 35, width: 1713, height: 670)
        let rightHalf = CGRect(x: 1723, y: 35, width: 1712, height: 1345)
        // Neben einem Viertel bleibt eine rechte Hälfte eine Hälfte
        XCTAssertEqual(Geometry.complement(of: rightHalf, target: topLeft, edge: .right, gap: 5, visible: v)?.height, 1345)
    }

    // MARK: Geteilter Bildschirm, Naht in Stufen

    func testSeamStopsStepThroughFixedPositions() {
        XCTAssertEqual(Geometry.nextSeamStop(current: 12, direction: 1), 15)     // ½ → ⅝
        XCTAssertEqual(Geometry.nextSeamStop(current: 12, direction: -1), 9)     // ½ → ⅜
        XCTAssertEqual(Geometry.nextSeamStop(current: 16, direction: 1), nil)    // ⅔ ist Ende
        XCTAssertEqual(Geometry.nextSeamStop(current: 8, direction: -1), nil)    // ⅓ ist Ende
        XCTAssertEqual(Geometry.nextSeamStop(current: 10.7, direction: 1), 12)   // von Hand gezogen
    }

    func testSplitKeepsSides() {
        // gemessen 08.10.: Outlook stand rechts und war aktiv, sprang beim Teilen nach links
        let outlookRight = CGRect(x: 1723, y: 35, width: 1712, height: 1345)
        let edgeLeft = CGRect(x: 5, y: 35, width: 1713, height: 1345)
        XCTAssertFalse(Geometry.comesFirst(outlookRight, before: edgeLeft, .landscape))
        XCTAssertTrue(Geometry.comesFirst(edgeLeft, before: outlookRight, .landscape))
        // Überlappend: entscheidet die Mitte
        XCTAssertTrue(Geometry.comesFirst(CGRect(x: 0, y: 0, width: 2000, height: 900),
                                          before: CGRect(x: 1500, y: 0, width: 1900, height: 900), .landscape))
    }

    func testSplitFramesHalfAndTwoThirds() {
        let (l, r) = Geometry.splitFrames(at: 12, in: v, .landscape, gap: 5)
        XCTAssertEqual(l, CGRect(x: 5, y: 35, width: 1713, height: 1345))
        XCTAssertEqual(r.minX - l.maxX, 5)
        let (l2, r2) = Geometry.splitFrames(at: 16, in: v, .landscape, gap: 5)
        XCTAssertEqual(l2.maxX, 2291)                    // ⅔ von 3440 = 2293,3 − 2,5
        XCTAssertEqual(r2.maxX, 3435)
    }

    // MARK: Mindestgröße des Nachbarn (gemessen an Outlook, 08.10.)

    func testOutlookMinimumWidthStopsSeamOnTheLeft() {
        // Edge (rechts, führend) zog seine linke Kante bis 1180; Outlook links sollte
        // 1175 breit werden, blieb aber 1415.
        let edge = CGRect(x: 1180, y: 35, width: 2255, height: 1345)
        let wanted = CGRect(x: 5, y: 35, width: 1170, height: 1345)
        let actual = CGRect(x: 5, y: 35, width: 1415, height: 1345)
        let r = Geometry.resolveMinimum(leading: edge, wanted: wanted, actual: actual)
        XCTAssertEqual(r?.neighbor, CGRect(x: 5, y: 35, width: 1415, height: 1345))
        // Kante bei 1420 + Abstand 5, rechter Rand von Edge bleibt 3435
        XCTAssertEqual(r?.leading, CGRect(x: 1425, y: 35, width: 2010, height: 1345))
    }

    func testMinimumWidthOnTheRightKeepsFarEdge() {
        let leading = CGRect(x: 5, y: 35, width: 2600, height: 1345)          // rechte Kante bis 2605
        let wanted = CGRect(x: 2610, y: 35, width: 825, height: 1345)        // rechter Rand 3435
        let actual = CGRect(x: 2610, y: 35, width: 1000, height: 1345)       // Mindestbreite 1000
        let r = Geometry.resolveMinimum(leading: leading, wanted: wanted, actual: actual)
        XCTAssertEqual(r?.neighbor, CGRect(x: 2435, y: 35, width: 1000, height: 1345))
        XCTAssertEqual(r?.leading, CGRect(x: 5, y: 35, width: 2425, height: 1345))
    }

    func testNothingToResolveWhenNeighborObeyed() {
        let w = CGRect(x: 1425, y: 35, width: 2010, height: 1345)
        XCTAssertNil(Geometry.resolveMinimum(leading: CGRect(x: 5, y: 35, width: 1415, height: 1345), wanted: w, actual: w))
    }

    func testMinimumHeightBelow() {
        let top = CGRect(x: 5, y: 35, width: 1713, height: 1100)
        let wanted = CGRect(x: 5, y: 1140, width: 1713, height: 240)
        let actual = CGRect(x: 5, y: 1140, width: 1713, height: 400)
        let r = Geometry.resolveMinimum(leading: top, wanted: wanted, actual: actual)
        XCTAssertEqual(r?.neighbor, CGRect(x: 5, y: 980, width: 1713, height: 400))
        XCTAssertEqual(r?.leading, CGRect(x: 5, y: 35, width: 1713, height: 940))
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
