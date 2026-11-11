import XCTest
@testable import Seam

/// E17k: „Alles öffnen“ — welche Apps fehlen, wann ihre Fenster stehen, was gemeldet wird.
final class AppOpenerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testMissingAreOnlyAppsWithoutWindowOnceEach() {
        var plan = DeskPlan()
        plan.skipped = [DeskSkip(bundleID: "com.example.chat", reason: .notRunning),
                        DeskSkip(bundleID: "com.example.chat", reason: .notRunning),
                        DeskSkip(bundleID: "com.example.mail", reason: .deskUnavailable),
                        DeskSkip(bundleID: "com.example.files", reason: .notRunning)]
        XCTAssertEqual(AppOpener.missing(in: plan), ["com.example.chat", "com.example.files"],
                       "fehlender Schreibtisch ist kein Grund zum Öffnen")
    }

    func testFramesIgnoreHiddenWindowsAndOtherApps() {
        let a = CGRect(x: 10, y: 10, width: 500, height: 400)
        let b = CGRect(x: 0, y: 0, width: 300, height: 200)
        let windows = [LiveWindow(bundleID: "com.example.chat", spaceIDs: [3], frame: a),
                       LiveWindow(bundleID: "com.example.chat", spaceIDs: [], frame: b),
                       LiveWindow(bundleID: "com.example.chat", spaceIDs: [1, 3], frame: b),
                       LiveWindow(bundleID: "com.example.mail", spaceIDs: [2], frame: a)]
        XCTAssertEqual(AppOpener.frames(of: "com.example.chat", in: windows), [b, a])
    }

    func testStillSinceRestartsOnChange() {
        let t1 = now.addingTimeInterval(1)
        let f = [CGRect(x: 0, y: 0, width: 10, height: 10)]
        XCTAssertNil(AppOpener.stillSince(previous: nil, current: [], since: nil, now: now))
        XCTAssertEqual(AppOpener.stillSince(previous: nil, current: f, since: nil, now: now), now)
        XCTAssertEqual(AppOpener.stillSince(previous: f, current: f, since: now, now: t1), now)
        XCTAssertEqual(AppOpener.stillSince(previous: [], current: f, since: nil, now: t1), t1)
    }

    func testMessagesSayWhatHappensAndWhatToDo() {
        XCTAssertEqual(DeskMessages.opening(1), "Seam öffnet 1 App aus dem Layout und räumt danach auf …")
        XCTAssertTrue(DeskMessages.opening(3).contains("3 Apps"))
        let text = DeskMessages.notFound(["Chat"])
        XCTAssertTrue(text.hasPrefix("Nicht gefunden: Chat. Diese App ist nicht mehr installiert."))
        XCTAssertTrue(text.contains("→ ZU TUN"))
        XCTAssertTrue(DeskMessages.notStarted(["Chat"]).hasPrefix("macOS hat Chat nicht gestartet."))
        XCTAssertTrue(DeskMessages.notStarted(["Chat", "Mail"]).contains("→ ZU TUN: diese Apps"))
    }
}
