import CoreGraphics
import XCTest
@testable import Seam

/// E18: Wo liegt der Hintergrund auf jedem Bildschirm? Werte gemessen am Mac mini, 10.11.
final class WallpaperPlanTests: XCTestCase {

    private let pa34 = WallpaperScreen(id: "PA34", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                       millimeters: CGSize(width: 801.61, height: 338.67))
    private let mb169 = WallpaperScreen(id: "MB169", frame: CGRect(x: 3440, y: -1075, width: 1080, height: 1920),
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
