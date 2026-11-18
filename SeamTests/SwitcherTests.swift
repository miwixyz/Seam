import XCTest
@testable import Seam

/// E21: reine Rechenlogik von Umschalter und Dock-Vorschau.
final class SwitcherTests: XCTestCase {

    func testWrapGoesAroundBothWays() {
        XCTAssertEqual(Switcher.wrap(1, count: 5), 1)
        XCTAssertEqual(Switcher.wrap(5, count: 5), 0)
        XCTAssertEqual(Switcher.wrap(-1, count: 5), 4)
        XCTAssertEqual(Switcher.wrap(-11, count: 5), 4)
        XCTAssertEqual(Switcher.wrap(3, count: 0), 0)
    }

    func testColumnsFitWidthAndNeverExceedCount() {
        XCTAssertEqual(Switcher.columns(count: 3, tileWidth: 210, maxWidth: 3000), 3)
        let c = Switcher.columns(count: 40, tileWidth: 210, maxWidth: 1400)
        XCTAssertGreaterThanOrEqual(c, 1)
        XCTAssertLessThanOrEqual(CGFloat(c) * (210 + 14 + 6) + 24, 1400)
        XCTAssertEqual(Switcher.columns(count: 5, tileWidth: 370, maxWidth: 100), 1)
    }

    /// Dock unten: Panel darüber, mittig. Dock links/rechts: Panel daneben.
    func testPlacementFollowsDockEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let size = CGSize(width: 400, height: 200)
        let bottomIcon = CGRect(x: 780, y: 940, width: 50, height: 50)
        let above = DockPreview.placement(size: size, icon: bottomIcon, screen: screen)
        XCTAssertEqual(above.maxY, bottomIcon.minY - 8)
        XCTAssertEqual(above.midX, bottomIcon.midX)

        let leftIcon = CGRect(x: 5, y: 400, width: 50, height: 50)
        let right = DockPreview.placement(size: size, icon: leftIcon, screen: screen)
        XCTAssertEqual(right.minX, leftIcon.maxX + 8)

        let rightIcon = CGRect(x: 1545, y: 400, width: 50, height: 50)
        let left = DockPreview.placement(size: size, icon: rightIcon, screen: screen)
        XCTAssertEqual(left.maxX, rightIcon.minX - 8)
    }

    /// E21c: fremde Titel ohne Steuerzeichen, gekürzt.
    func testTitleSanitizing() {
        XCTAssertEqual(WindowCatalog.sanitize("  Bank\u{0}\u{1B}[31m – Login\n "), "Bank[31m – Login")
        XCTAssertEqual(WindowCatalog.sanitize(String(repeating: "x", count: 500)).count, WindowCatalog.maxTitle)
        XCTAssertEqual(WindowCatalog.sanitize(nil), "")
    }

    /// Von außen veränderte Werte fallen auf den Standard (STRIDE T).
    @MainActor
    func testPreviewPreferencesValidated() {
        let suite = "dev.mwlr.seam.tests.preview"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(12345, forKey: "dockPreviewDelay")
        d.set("riesig", forKey: "previewSize")
        d.set("vielleicht", forKey: "spaceOrderPrevious")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.dockPreviewDelay, 200)
        XCTAssertEqual(p.previewSize, .normal)
        XCTAssertNil(p.spaceOrderPreviousValue)
        XCTAssertFalse(p.switcherEnabled)
        XCTAssertFalse(p.dockPreviewEnabled)

        p.rememberSpaceOrderPrevious(nil)
        XCTAssertEqual(Preferences(defaults: d).spaceOrderPreviousValue, .some(nil))
        p.rememberSpaceOrderPrevious(true)
        XCTAssertEqual(Preferences(defaults: d).spaceOrderPreviousValue, .some(true))
        d.removePersistentDomain(forName: suite)
    }
}

/// Reihenfolge nach Nutzung (Fix 18.11.: schnelles ⌘Tab sprang wegen der Systemstapelfolge zu Notizen).
final class SwitcherOrderTests: XCTestCase {

    private func w(_ id: CGWindowID, _ pid: pid_t, on: Bool = true) -> CatalogWindow {
        CatalogWindow(id: id, pid: pid, title: "", frame: .zero, onScreen: on)
    }

    func testAppsFollowUsageNotStack() {
        // Stapel: Notizen (unsichtbar) vor Helium (vorn) vor WhatsApp.
        let notes = w(1, 30, on: false), helium = w(2, 10), whatsapp = w(3, 20)
        let stack: [CGWindowID: Int] = [1: 0, 2: 1, 3: 2]
        let out = WindowCatalog.order([notes, helium, whatsapp], stack: stack, appOrder: [10, 20])
        XCTAssertEqual(out.map(\.id), [2, 3, 1])       // Helium, dann zuletzt genutzte App, unbekannte zuletzt
    }

    /// Kaltstart: Seam kennt nur die vordere App. Ein verdecktes Fenster vorn im Stapel darf nicht Platz 2 sein.
    func testColdStartPrefersVisibleApps() {
        let notes = w(1, 30, on: false), front = w(2, 10), edge = w(3, 20)
        let out = WindowCatalog.order([notes, front, edge], stack: [1: 0, 2: 1, 3: 2], appOrder: [10])
        XCTAssertEqual(out.map(\.id), [2, 3, 1])
    }

    func testVisibleWindowOfAppFirst() {
        let hidden = w(1, 10, on: false), shown = w(2, 10)
        let out = WindowCatalog.order([hidden, shown], stack: [1: 0, 2: 1], appOrder: [10])
        XCTAssertEqual(out.map(\.id), [2, 1])
    }
}
