import CoreGraphics
import XCTest
@testable import Seam

/// E18: Wo liegt der Hintergrund auf jedem Bildschirm? Werte gemessen am Mac mini, 10.11.
final class WallpaperPlanTests: XCTestCase {

    private let pa34 = WallpaperScreen(id: "PA34", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                       millimeters: CGSize(width: 801.61, height: 338.67))
    private let mb169 = WallpaperScreen(id: "MB169", frame: CGRect(x: 3440, y: -1053, width: 1080, height: 1920),
                                        millimeters: CGSize(width: 190.5, height: 341.03))
    private let z12 = WallpaperScreen(id: "Z1-2", frame: CGRect(x: 1136, y: -504, width: 1344, height: 504),
                                      millimeters: CGSize(width: 289.3, height: 110.36))

    private func assertClose(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 0.05, msg, file: file, line: line)
    }

    func testTouchingScreensTouchInMillimeters() {
        let p = WallpaperPlan.physical([pa34, mb169, z12])
        assertClose(p[0].minX, 0)
        assertClose(p[0].width, 801.61)
        // MB169 rechts daneben: linke Kante = rechte Kante des PA34, Größe aus der eigenen Dichte.
        assertClose(p[1].minX, p[0].maxX)
        assertClose(p[1].width, 190.5)
        // Z1-2 darunter: obere Kante = untere Kante des PA34.
        assertClose(p[2].maxY, p[0].minY)
    }

    func testAlignsTopEdgeNotCenter() {
        // Michaels Foto 10.11.: Oberkante MB169 auf dem Tisch 131 mm unter der des PA34.
        // Anordnung: 1440 − 867 = 573 pt bei 4,29 pt/mm = 133,5 mm. Mitte ergab 191 mm (Fehler 0.9.0).
        let p = WallpaperPlan.physical([pa34, mb169, z12])
        XCTAssertEqual(p[0].maxY - p[1].maxY, 133.5, accuracy: 1)
        // Z1-2: linke Kante 1136 pt = 264,7 mm (Tisch 268 mm).
        XCTAssertEqual(p[2].minX - p[0].minX, 264.7, accuracy: 1)
    }

    func testOffsetMovesOnlyThatScreen() {
        var raised = mb169
        raised.offsetY = 4
        var lowered = z12
        lowered.offsetY = -130
        let base = WallpaperPlan.physical([pa34, mb169, z12])
        let p = WallpaperPlan.physical([pa34, raised, lowered])
        assertClose(p[0].maxY, base[0].maxY)
        assertClose(p[1].maxY - base[1].maxY, 4)
        assertClose(p[2].maxY - base[2].maxY, -130)
        assertClose(p[1].minX, base[1].minX)
    }

    func testSpanIsOneImageInMillimeters() {
        // Kern der Funktion: Das Bild liegt auf allen Bildschirmen an DERSELBEN Stelle in Millimetern —
        // eine Linie läuft über die Kante gerade weiter, obwohl die Dichten verschieden sind.
        let screens = [pa34, mb169, z12]
        let rects = WallpaperPlan.mediaRects(media: CGSize(width: 7680, height: 4320), screens: screens, layout: .span)
        let phys = WallpaperPlan.physical(screens)
        let inMM = screens.indices.map { i -> CGRect in
            let d = WallpaperPlan.density(screens[i])!
            return CGRect(x: rects[i].minX / d + phys[i].minX, y: rects[i].minY / d + phys[i].minY,
                          width: rects[i].width / d, height: rects[i].height / d)
        }
        for r in inMM.dropFirst() {
            assertClose(r.minX, inMM[0].minX)
            assertClose(r.minY, inMM[0].minY)
            assertClose(r.width, inMM[0].width)
        }
    }

    func testSpanCoversEveryScreen() {
        let screens = [pa34, mb169, z12]
        let rects = WallpaperPlan.mediaRects(media: CGSize(width: 1920, height: 1080), screens: screens, layout: .span)
        for (s, r) in zip(screens, rects) {
            XCTAssertTrue(r.contains(CGRect(origin: .zero, size: s.frame.size).insetBy(dx: 0.5, dy: 0.5)), s.id)
        }
    }

    func testEachFillsScreenKeepingAspect() {
        let r = WallpaperPlan.mediaRects(media: CGSize(width: 1920, height: 1080), screens: [mb169], layout: .each)[0]
        // Hochkant-Bildschirm, Querformat-Video: Höhe füllt, Breite steht über, mittig.
        assertClose(r.height, 1920)
        assertClose(r.width, 1920 * 16 / 9)
        assertClose(r.midX, 540)
    }

    func testUnknownSizeUsesMainDensity() {
        let blind = WallpaperScreen(id: "X", frame: CGRect(x: 3440, y: 0, width: 1000, height: 1000), millimeters: .zero)
        let p = WallpaperPlan.physical([pa34, blind])
        assertClose(p[1].width, 1000 / (3440 / 801.61))
        assertClose(p[1].minX, p[0].maxX)
    }

    func testNothingToPlan() {
        XCTAssertEqual(WallpaperPlan.mediaRects(media: .zero, screens: [pa34], layout: .span), [])
        XCTAssertEqual(WallpaperPlan.mediaRects(media: CGSize(width: 1, height: 1), screens: [], layout: .span), [])
    }
}

/// Hell/Dunkel (Michael, 10.11.): welche Datei gilt?
final class WallpaperAppearanceTests: XCTestCase {
    func testDarkUsesDarkFile() {
        XCTAssertEqual(Preferences.wallpaperPath(light: "/a.mp4", dark: "/b.mp4", isDark: true), "/b.mp4")
        XCTAssertEqual(Preferences.wallpaperPath(light: "/a.mp4", dark: "/b.mp4", isDark: false), "/a.mp4")
    }

    func testMissingDarkFallsBackToLight() {
        XCTAssertEqual(Preferences.wallpaperPath(light: "/a.mp4", dark: nil, isDark: true), "/a.mp4")
    }

    func testOnlyDarkChosenAlsoServesLight() {
        XCTAssertEqual(Preferences.wallpaperPath(light: nil, dark: "/b.mp4", isDark: false), "/b.mp4")
        XCTAssertNil(Preferences.wallpaperPath(light: nil, dark: nil, isDark: false))
    }
}

/// Michael 18.11.: Hintergrund nur auf einem Space; soll auf allen gelten oder je Space ein eigenes Bild.
final class WallpaperSpaceTests: XCTestCase {
    private let a = WallpaperScreen(id: "PA34", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                    millimeters: CGSize(width: 800, height: 335))
    private let b = WallpaperScreen(id: "MB169", frame: CGRect(x: 3440, y: 0, width: 1080, height: 1920),
                                    millimeters: CGSize(width: 190, height: 338))
    private let src = WallpaperPlan.SourceStamp(path: "/Bilder/berg.jpg", modified: 1000, bytes: 4_000_000)

    private func name(_ s: WallpaperPlan.SourceStamp? = nil, layout: WallpaperLayout = .span,
                      screens: [WallpaperScreen]? = nil, scale: CGFloat = 2) -> String {
        WallpaperPlan.pieceName(screen: "PA34", source: s ?? src, layout: layout, screens: screens ?? [a, b],
                                scale: scale)
    }

    func testPieceNameIsStableAndFollowsEveryInput() {
        XCTAssertEqual(name(), name())
        XCTAssertTrue(name().hasPrefix("seam-PA34-"))
        XCTAssertTrue(name().hasSuffix(".png"))
        XCTAssertNotEqual(name(), name(WallpaperPlan.SourceStamp(path: src.path, modified: 1001, bytes: src.bytes)))
        XCTAssertNotEqual(name(), name(WallpaperPlan.SourceStamp(path: "/Bilder/see.jpg", modified: 1000, bytes: src.bytes)))
        XCTAssertNotEqual(name(), name(layout: .each))
        XCTAssertNotEqual(name(), name(scale: 1))
        var lifted = b
        lifted.offsetY = 4
        XCTAssertNotEqual(name(), name(screens: [a, lifted]))       // Gesamtbild: Nachbar verändert den Zuschnitt
    }

    func testSpacePathPrefersOwnEntryOnlyWhenPerSpace() {
        let per = ["PA34#2": "/Bilder/see.jpg"]
        XCTAssertEqual(WallpaperPlan.spacePath(slot: "PA34#2", perSpace: true, spacePaths: per, main: "/m.jpg"), "/Bilder/see.jpg")
        XCTAssertEqual(WallpaperPlan.spacePath(slot: "PA34#2", perSpace: false, spacePaths: per, main: "/m.jpg"), "/m.jpg")
        XCTAssertEqual(WallpaperPlan.spacePath(slot: "PA34#1", perSpace: true, spacePaths: per, main: "/m.jpg"), "/m.jpg")
        XCTAssertEqual(WallpaperPlan.spacePath(slot: nil, perSpace: true, spacePaths: per, main: "/m.jpg"), "/m.jpg")
    }

    /// Von außen veränderte Werte fallen weg (STRIDE T), wie bei den übrigen Hintergrund-Werten.
    @MainActor
    func testSpacePathsValidatedOnLoad() {
        let suite = "dev.mwlr.seam.tests.spacepaths"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(["PA34#2": "/Bilder/see.jpg", "PA34#3": "relativ.jpg", "": "/x.jpg"], forKey: "wallpaperSpacePaths")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.wallpaperSpacePaths, ["PA34#2": "/Bilder/see.jpg"])
        XCTAssertFalse(p.wallpaperPerSpace)
        p.setWallpaperSpacePath(nil, slot: "PA34#2")
        XCTAssertEqual(Preferences(defaults: d).wallpaperSpacePaths, [:])
        d.removePersistentDomain(forName: suite)
    }
}
