import CoreGraphics
import XCTest
@testable import Seam

/// E13: Unter welches Fenster gehört die Abdunklung?
final class DimPlanTests: XCTestCase {

    private let a = StackWindow(number: 10, pid: 1, bounds: CGRect(x: 0, y: 25, width: 957, height: 1000))
    private let b = StackWindow(number: 20, pid: 2, bounds: CGRect(x: 962, y: 25, width: 958, height: 1000))
    private let c = StackWindow(number: 30, pid: 3, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
    private let a2 = StackWindow(number: 11, pid: 1, bounds: CGRect(x: 50, y: 50, width: 500, height: 400))

    func testFrontWindowOfFrontApp() {
        XCTAssertEqual(DimPlan.target(stack: [a, c, b], frontPID: 1, partner: nil, exclude: []), 10)
    }

    func testOtherWindowsOfSameAppAreDimmed() {
        // Nur das oberste Fenster der vorderen App bleibt hell (Michael, 09.10.).
        XCTAssertEqual(DimPlan.target(stack: [a, a2, c], frontPID: 1, partner: nil, exclude: []), 10)
    }

    func testPairBothStayBright() {
        XCTAssertEqual(DimPlan.target(stack: [a, b, c], frontPID: 1, partner: (2, b.bounds), exclude: []), 20)
    }

    func testPartnerAboveFrontKeepsFrontAsTarget() {
        // Partner liegt (noch) über dem vorderen Fenster: Ziel bleibt das vordere, nie höher.
        XCTAssertEqual(DimPlan.target(stack: [b, a, c], frontPID: 1, partner: (2, b.bounds), exclude: []), 10)
    }

    func testPartnerNotFoundFallsBackToFront() {
        let moved = CGRect(x: 1300, y: 300, width: 500, height: 400)
        XCTAssertEqual(DimPlan.target(stack: [a, b, c], frontPID: 1, partner: (2, moved), exclude: []), 10)
    }

    func testOwnOverlaysAreIgnored() {
        let overlay = StackWindow(number: 99, pid: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // Überlagerung des eigenen Prozesses vorn (z. B. Seams Hilfe vorn) zählt nicht als Fenster.
        XCTAssertEqual(DimPlan.target(stack: [overlay, a, c], frontPID: 1, partner: nil, exclude: [99]), 10)
    }

    // Blitzen 16.10. (Video Michael, Helium): Die Linkanzeige unten im Browser (212 × 43 pt) wurde
    // Ziel, verschwand im selben Moment, die Abdunklung ging aus bzw. landete ganz unten.
    func testTinyWindowOfFrontAppIsNeverTarget() {
        let statusBubble = StackWindow(number: 77, pid: 1, bounds: CGRect(x: 803, y: 1339, width: 212, height: 43))
        XCTAssertEqual(DimPlan.target(stack: [statusBubble, a, c], frontPID: 1, partner: nil, exclude: []), 10)
    }

    // Messung 16.10., 17:12:51: Zusatzfenster der vorderen App über dem Hauptfenster (Download-Hinweis,
    // Dialog im Ausblenden) darf nicht Ziel werden, wenn das Hauptfenster den Fokus hat.
    func testFocusedWindowIsTargetNotTopmostExtraWindow() {
        let toast = StackWindow(number: 79, pid: 1, bounds: CGRect(x: 2504, y: 61, width: 320, height: 68))
        XCTAssertEqual(DimPlan.target(stack: [toast, a, c], frontPID: 1, partner: nil, exclude: [], focused: a.bounds), 10)
        // Ohne Fokusangabe wie bisher das oberste Fenster der App.
        XCTAssertEqual(DimPlan.target(stack: [toast, a, c], frontPID: 1, partner: nil, exclude: []), 79)
    }

    func testFocusNotFoundFallsBackToTopmost() {
        let elsewhere = CGRect(x: 5000, y: 5000, width: 300, height: 300)
        XCTAssertEqual(DimPlan.target(stack: [a, a2, c], frontPID: 1, partner: nil, exclude: [], focused: elsewhere), 10)
    }

    func testPairStillWorksWithFocus() {
        XCTAssertEqual(DimPlan.target(stack: [a, b, c], frontPID: 1, partner: (2, b.bounds), exclude: [],
                                      focused: a.bounds), 20)
    }

    func testOnlyTinyWindowCountsAsNoWindow() {
        let tooltip = StackWindow(number: 78, pid: 1, bounds: CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertNil(DimPlan.target(stack: [tooltip, c], frontPID: 1, partner: nil, exclude: []))
    }

    func testNoWindowOfFrontAppMeansNoDimming() {
        XCTAssertNil(DimPlan.target(stack: [b, c], frontPID: 1, partner: nil, exclude: []))
    }

    // Flackern (Michael, 12.10., Variante a): Kommt eine App ohne Fenster nach vorn (Menüleisten-App,
    // Starter, Passwort-Manager), bleibt die Abdunklung stehen statt aus- und wieder anzugehen.
    func testWindowlessFrontAppKeepsDimming() {
        let o = StackWindow(number: 90, pid: 9, bounds: .zero)
        XCTAssertTrue(DimPlan.keepWithoutTarget(isDesktop: false, stack: [a, o, c], lastTargets: [10], overlays: [90]))
    }

    func testDesktopStillLiftsDimming() {
        let o = StackWindow(number: 90, pid: 9, bounds: .zero)
        XCTAssertFalse(DimPlan.keepWithoutTarget(isDesktop: true, stack: [a, o, c], lastTargets: [10], overlays: [90]))
    }

    func testVanishedTargetLiftsDimming() {
        // Altes Ziel geschlossen: Abdunklung läge sonst über allem.
        let o = StackWindow(number: 90, pid: 9, bounds: .zero)
        XCTAssertFalse(DimPlan.keepWithoutTarget(isDesktop: false, stack: [o, c], lastTargets: [10], overlays: [90]))
        XCTAssertFalse(DimPlan.keepWithoutTarget(isDesktop: false, stack: [a, o, c], lastTargets: [], overlays: [90]))
    }

    // Blitzen beim App-Wechsel (Michael, 12.10., Video 15:57): Bei neuem Ziel wurde die schon
    // sichtbare Abdunklung auf 0 gesetzt und neu eingeblendet — ganzer Hintergrund ~0,3 s hell.
    func testAlreadyShownDimmingIsNotFadedAgainOnTargetChange() {
        XCTAssertFalse(DimPlan.fadesIn(targetChanged: true, alreadyShown: true))
    }

    func testDimmingFadesInWhenComingFromHidden() {
        XCTAssertTrue(DimPlan.fadesIn(targetChanged: true, alreadyShown: false))
        XCTAssertFalse(DimPlan.fadesIn(targetChanged: false, alreadyShown: false))
    }

    func testInPlaceOnlyWhenOverlayDirectlyBelowTarget() {
        let o1 = StackWindow(number: 90, pid: 9, bounds: .zero)
        let o2 = StackWindow(number: 91, pid: 9, bounds: .zero)
        XCTAssertTrue(DimPlan.isInPlace(stack: [a, o1, o2, c], target: 10, overlays: [90, 91]))
        XCTAssertFalse(DimPlan.isInPlace(stack: [a, c, o1, o2], target: 10, overlays: [90, 91]))
        XCTAssertFalse(DimPlan.isInPlace(stack: [a], target: 10, overlays: [90]))
    }

    func testKeepWithoutTargetNeedsEveryScreenTargetInPlace() {
        // Je Bildschirm (0.6): zwei Ziele, eines ist weg → aufheben, sonst läge eine Abdunklung über allem.
        let o1 = StackWindow(number: 90, pid: 9, bounds: .zero)
        let o2 = StackWindow(number: 91, pid: 9, bounds: .zero)
        XCTAssertTrue(DimPlan.keepWithoutTarget(isDesktop: false, stack: [a, o1, c, o2], lastTargets: [10, 30],
                                                overlays: [90, 91]))
        XCTAssertFalse(DimPlan.keepWithoutTarget(isDesktop: false, stack: [a, o1, o2], lastTargets: [10, 30],
                                                 overlays: [90, 91]))
    }

    // Je Bildschirm (Michael, 16.10.: „auf jedem Monitor ein aktives Fenster“, „für einzelne Monitore abschalten“).
    private let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    private let onRight = StackWindow(number: 40, pid: 4, bounds: CGRect(x: 2000, y: 100, width: 800, height: 600))
    private let onRight2 = StackWindow(number: 41, pid: 5, bounds: CGRect(x: 2100, y: 200, width: 800, height: 600))

    private func targets(_ stack: [StackWindow], front: Int, screens: [CGRect]? = nil,
                         modes: [DimScreenMode] = [.topBright, .topBright], exclude: Set<Int> = [],
                         eligible: @escaping (StackWindow) -> Bool = { _ in true }) -> [Int?] {
        let frames = screens ?? [left, right]
        let setup = frames.indices.map { DimScreen(frame: frames[$0], mode: $0 < modes.count ? modes[$0] : .dim) }
        return DimPlan.screenTargets(stack: stack, screens: setup, front: front, exclude: exclude, eligible: eligible)
    }

    func testDimModeKeepsWholeOtherScreenDark() {
        XCTAssertEqual(targets([a, c, onRight], front: 10, modes: [.dim, .dim]), [10, 10])
    }

    func testOffScreenHasNoOverlay() {
        XCTAssertEqual(targets([a, c, onRight], front: 10, modes: [.dim, .off]), [10, nil])
        // Auch der Bildschirm mit dem aktiven Fenster lässt sich ausschalten.
        XCTAssertEqual(targets([a, c, onRight], front: 10, modes: [.off, .dim]), [nil, 10])
    }

    // Löcher (Apps nie abdunkeln, alle Fenster der aktiven App): Maler-Verfahren.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testNoBrightWindowNoPaints() {
        XCTAssertEqual(DimPlan.paints(stack: [a, c, b], below: 10, screen: screen, exclude: []) { _ in false }, [])
    }

    func testBrightWindowBelowBecomesHole() {
        let p = DimPlan.paints(stack: [a, c, b], below: 10, screen: screen, exclude: []) { $0.number == 30 }
        XCTAssertEqual(p, [DimPaint(rect: c.bounds, bright: true)])
    }

    func testWindowAboveHoleIsDarkAgain() {
        // b liegt über dem hellen Fenster d und überschneidet es: dort wieder dunkel.
        let d = StackWindow(number: 60, pid: 6, bounds: CGRect(x: 900, y: 100, width: 400, height: 400))
        let p = DimPlan.paints(stack: [a, b, d], below: 10, screen: screen, exclude: []) { $0.number == 60 }
        XCTAssertEqual(p, [DimPaint(rect: d.bounds, bright: true),
                           DimPaint(rect: b.bounds.intersection(screen), bright: false)])
    }

    func testDarkWindowBehindHoleIsSkipped() {
        // c liegt UNTER dem hellen Fenster: zählt nicht (ist ohnehin dunkel).
        let d = StackWindow(number: 60, pid: 6, bounds: CGRect(x: 150, y: 150, width: 300, height: 300))
        let p = DimPlan.paints(stack: [a, d, c], below: 10, screen: screen, exclude: []) { $0.number == 60 }
        XCTAssertEqual(p, [DimPaint(rect: d.bounds, bright: true)])
    }

    func testPaintsOnlyBelowTargetAndOnScreen() {
        // Fenster über dem Ziel (a) und auf anderem Bildschirm zählen nicht; Überlagerungen auch nicht.
        let overlay = StackWindow(number: 99, pid: 9, bounds: screen)
        let p = DimPlan.paints(stack: [a, overlay, c, onRight], below: 10, screen: screen, exclude: [99]) { _ in true }
        XCTAssertEqual(p, [DimPaint(rect: c.bounds, bright: true)])
        XCTAssertEqual(DimPlan.paints(stack: [c, a], below: 10, screen: screen, exclude: []) { _ in true }, [])
    }

    func testSpaceOffOnlyForCurrentSpaceOfThatScreen() {
        let spaces = [SpaceInfo(key: "A", number: 1, display: "D1", isFullScreen: false, isCurrent: true),
                      SpaceInfo(key: "B", number: 2, display: "D1", isFullScreen: false, isCurrent: false),
                      SpaceInfo(key: "C", number: 1, display: "D2", isFullScreen: false, isCurrent: true)]
        XCTAssertTrue(DimPlan.spaceOff(spaces, display: "D1", offKeys: ["A"]))
        XCTAssertFalse(DimPlan.spaceOff(spaces, display: "D2", offKeys: ["A"]))
        XCTAssertFalse(DimPlan.spaceOff(spaces, display: "D1", offKeys: ["B"]))
        XCTAssertFalse(DimPlan.spaceOff(spaces, display: "D1", offKeys: []))
    }

    @MainActor
    func testScreenSettingsDefaultsAndFallback() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.dimMode(for: "X"), .dim)
        XCTAssertEqual(p.dimMode(for: nil), .dim)
        XCTAssertEqual(p.dimStrength(for: "X"), 35)
        XCTAssertFalse(p.dimActiveAppAll)
        p.setDimMode(.off, for: "X")
        p.setDimStrength(20, for: "X")
        p.setDimStrength(99, for: "X")
        XCTAssertEqual(p.dimMode(for: "X"), .off)
        XCTAssertEqual(p.dimStrength(for: "X"), 20)
        let reloaded = Preferences(defaults: d)
        XCTAssertEqual(reloaded.dimMode(for: "X"), .off)
        XCTAssertEqual(reloaded.dimStrength(for: "X"), 20)
    }

    @MainActor
    func testTamperedDimSettingsAreDropped() {
        // STRIDE T (E13, 0.6): von außen veränderte Werte fallen beim Laden weg.
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        d.set(["ok": "off", "bad": "boom", String(repeating: "x", count: 81): "off"], forKey: "dimScreenModes")
        d.set(["ok": 50, "bad": 77], forKey: "dimScreenStrengths")
        d.set(["com.microsoft.teams2", "com.microsoft.teams2", "kein bundle/id", ""], forKey: "dimNeverApps")
        d.set(["S1", "", "S1"], forKey: "dimOffSpaces")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.dimScreenModes, ["ok": "off"])
        XCTAssertEqual(p.dimScreenStrengths, ["ok": 50])
        XCTAssertEqual(p.dimNeverApps, ["com.microsoft.teams2"])
        XCTAssertEqual(p.dimOffSpaces, ["S1"])
    }

    @MainActor
    func testDimSettingsCappedOnLoadAndWrite() {
        // Rafter-Review 16.10.: Obergrenzen beim Laden UND Schreiben, Bytes statt Zeichen, keine Steuerzeichen.
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        d.set((0..<500).map { "com.test.app\($0)" }, forKey: "dimNeverApps")
        d.set(["a\u{7}b", "e" + String(repeating: "\u{301}", count: 60)], forKey: "dimOffSpaces")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.dimNeverApps.count, Preferences.maxDimApps)
        XCTAssertEqual(p.dimNeverApps.first, "com.test.app0")
        XCTAssertEqual(p.dimOffSpaces, [])
        for i in 0..<(Preferences.maxDimScreens + 5) { p.setDimMode(.off, for: "S\(i)") }
        XCTAssertEqual(p.dimScreenModes.count, Preferences.maxDimScreens)
        p.setDimMode(.topBright, for: "S0")
        XCTAssertEqual(p.dimMode(for: "S0"), .topBright)
    }

    @MainActor
    func testNeverAppsAndSpacesSetters() {
        let p = Preferences(defaults: UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!)
        p.addDimNeverApp("com.spotify.client")
        p.addDimNeverApp("com.spotify.client")
        p.addDimNeverApp("nicht gültig")
        XCTAssertEqual(p.dimNeverApps, ["com.spotify.client"])
        p.setSpaceDimmed(false, key: "S1")
        p.setSpaceDimmed(false, key: "S1")
        XCTAssertEqual(p.dimOffSpaces, ["S1"])
        p.setSpaceDimmed(true, key: "S1")
        XCTAssertEqual(p.dimOffSpaces, [])
    }

    func testEachScreenKeepsItsTopWindow() {
        XCTAssertEqual(targets([a, c, onRight, onRight2], front: 10), [10, 40])
    }

    func testFrontWindowOnSecondScreen() {
        XCTAssertEqual(targets([onRight, a, c], front: 40), [10, 40])
    }

    func testScreenWithoutWindowFollowsFront() {
        // Kein Fenster auf dem zweiten Bildschirm: ganz abdunkeln wie bisher.
        XCTAssertEqual(targets([a, c], front: 10), [10, 10])
    }

    func testIneligibleAndOwnWindowsAreSkipped() {
        let overlay = StackWindow(number: 99, pid: 9, bounds: right)
        XCTAssertEqual(targets([a, overlay, onRight, onRight2], front: 10, exclude: [99],
                               eligible: { $0.number != 40 }), [10, 41])
    }

    func testWindowCountsForScreenWithMostOfIt() {
        // Liegt überwiegend links, ragt nur etwas nach rechts: zählt nicht für den rechten.
        let spanning = StackWindow(number: 50, pid: 6, bounds: CGRect(x: 1500, y: 0, width: 600, height: 500))
        XCTAssertEqual(targets([a, spanning, onRight], front: 10), [10, 40])
    }

    func testSingleScreenOnlyFront() {
        XCTAssertEqual(targets([a, c], front: 10, screens: [left], modes: [.topBright]), [10])
    }

    @MainActor
    func testDimDefaultsOffAndMedium() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        let p = Preferences(defaults: d)
        XCTAssertFalse(p.dimEnabled)
        XCTAssertEqual(p.dimStrength, 35)
    }

    @MainActor
    func testInvalidStrengthFallsBack() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        d.set(99, forKey: "dimStrength")
        XCTAssertEqual(Preferences(defaults: d).dimStrength, 35)
    }
}
