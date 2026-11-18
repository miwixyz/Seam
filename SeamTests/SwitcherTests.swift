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

    /// Michael 18.11.: „die Vorschau stört, wenn ich aus Versehen über das Dock fahre“ — 200 ms Standard
    /// war zu kurz, und 800 ms das Höchste. Standard 500 ms, wählbar bis 2 s.
    @MainActor
    func testDockDelayDefaultAndLongChoices() {
        let suite = "dev.mwlr.seam.tests.dockdelay"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(Preferences(defaults: d).dockPreviewDelay, 500)
        XCTAssertTrue(Preferences.dockDelayChoices.contains(2000))
        d.set(1500, forKey: "dockPreviewDelay")
        XCTAssertEqual(Preferences(defaults: d).dockPreviewDelay, 1500)
        d.removePersistentDomain(forName: suite)
    }

    /// Audit 18.11.: Dock beim Start noch nicht bereit → nach 2, 5 und 15 s erneut versuchen.
    func testDockRetryBacksOff() {
        XCTAssertEqual(DockPreview.retryDelay(after: 0), .seconds(2))
        XCTAssertEqual(DockPreview.retryDelay(after: 1), .seconds(5))
        XCTAssertEqual(DockPreview.retryDelay(after: 2), .seconds(15))
        XCTAssertNil(DockPreview.retryDelay(after: 3))
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
        XCTAssertEqual(p.dockPreviewDelay, 500)
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

    /// Audit 18.11. (Mittel): Kurzes ⌘Tab landete auf dem zweiten Fenster der vorderen App
    /// statt auf der zuletzt benutzten App. ⌘< bleibt innerhalb der App.
    func testShortCmdTabGoesToPreviousAppNotSecondWindow() {
        let list = [w(1, 10), w(2, 10), w(3, 20), w(4, 30)]
        XCTAssertEqual(Switcher.start(steps: 1, list: list, mode: .all), 2)
        XCTAssertEqual(Switcher.start(steps: 2, list: list, mode: .all), 3)
        XCTAssertEqual(Switcher.start(steps: -1, list: list, mode: .all), 3)
        XCTAssertEqual(Switcher.start(steps: 1, list: list, mode: .frontApp), 1)
        XCTAssertEqual(Switcher.start(steps: 1, list: [w(1, 10), w(2, 10)], mode: .all), 1)  // nur eine App
        XCTAssertEqual(Switcher.start(steps: 0, list: list, mode: .all), 0)
        // Code-Audit 18.11. (Prüfer): Vordere App ohne Fenster in der Liste (Finder, Schreibtisch angeklickt) —
        // die erste App der Liste IST dann die zuletzt benutzte.
        XCTAssertEqual(Switcher.start(steps: 1, list: [w(2, 20), w(3, 20), w(4, 30)], mode: .all, front: 10), 0)
        XCTAssertEqual(Switcher.start(steps: 1, list: list, mode: .all, front: 10), 2)
    }

    /// Audit 18.11. (Mittel): Zwei gleich große, gestapelte Fenster — der erste AX-Treffer gewann.
    /// Zuordnung ohne Titel (E3/E21c): minimiert vs. nicht minimiert trennt, sonst bei Mehrdeutigkeit auslassen.
    func testPickTargetWindowWithoutGuessing() {
        let r = CGRect(x: 100, y: 100, width: 800, height: 600)
        // Minimiertes Zwillingsfenster steht in der AX-Liste vorn.
        XCTAssertEqual(WindowCatalog.pick([(r, true), (r, false)], frame: r, minimized: false), 1)
        XCTAssertEqual(WindowCatalog.pick([(r, false), (r, true)], frame: r, minimized: true), 1)
        // Zwei sichtbare Zwillinge: nicht raten.
        XCTAssertNil(WindowCatalog.pick([(r, false), (r, false)], frame: r, minimized: false))
        // Eindeutige Lage bleibt eindeutig, einziges Fenster bleibt Ausweg.
        let other = CGRect(x: 0, y: 0, width: 300, height: 300)
        XCTAssertEqual(WindowCatalog.pick([(other, false), (r, false)], frame: r, minimized: false), 1)
        XCTAssertEqual(WindowCatalog.pick([(other, false)], frame: r, minimized: false), 0)
        XCTAssertNil(WindowCatalog.pick([(other, false), (other, false)], frame: r, minimized: false))
        // Code-Audit 18.11. (Prüfer): Fenster auf einem anderen Space — die AX-Liste kennt nur den Zwilling hier.
        XCTAssertNil(WindowCatalog.pick([(r, false)], frame: r, minimized: false, elsewhere: true))
    }

    func testVisibleWindowOfAppFirst() {
        let hidden = w(1, 10, on: false), shown = w(2, 10)
        let out = WindowCatalog.order([hidden, shown], stack: [1: 0, 2: 1], appOrder: [10])
        XCTAssertEqual(out.map(\.id), [2, 1])
    }
}

/// Audit 18.11.: Hing ScreenCaptureKit beim Listen, passierte auf ⌘Tab 30 s lang nichts.
final class DeadlineTests: XCTestCase {
    func testHangingWorkFallsBackInTime() async {
        let start = Date()
        let v = await Deadline.value(within: .milliseconds(200), otherwise: -1) {
            try? await Task.sleep(for: .seconds(3))
            return 1
        }
        XCTAssertEqual(v, -1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testQuickWorkWins() async {
        let v = await Deadline.value(within: .seconds(2), otherwise: -1) { 7 }
        XCTAssertEqual(v, 7)
    }
}

final class PendingStepsTests: XCTestCase {
    func testPressAfterEarlyReleaseDoesNotAddSteps() {
        var p = Switcher.PendingSteps()
        p.press(1)
        p.press(1)
        XCTAssertEqual(p.steps, 2)               // gehalten, zweimal Tab: zwei Schritte
        var q = Switcher.PendingSteps()
        q.press(1)
        q.release()
        q.press(1)
        XCTAssertEqual(q.steps, 1)               // losgelassen, dann neues ⌘Tab: Geste war schon zu Ende
    }
}

/// Ungeklärter Punkt aus dem Audit 18.11.: Hover bei ruhendem Zeiger. Abgesichert: erst nach Bewegung.
final class HoverGateTests: XCTestCase {
    func testHoverCountsOnlyAfterPointerMoved() {
        let start = CGPoint(x: 500, y: 400)
        XCTAssertFalse(PreviewModel.pointerMoved(from: start, to: start))
        XCTAssertFalse(PreviewModel.pointerMoved(from: start, to: CGPoint(x: 502, y: 401)))
        XCTAssertTrue(PreviewModel.pointerMoved(from: start, to: CGPoint(x: 510, y: 400)))
        XCTAssertTrue(PreviewModel.pointerMoved(from: nil, to: start))
    }
}
