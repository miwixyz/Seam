import XCTest
@testable import Seam

/// Schritt 6: Jede Meldung sagt, was los ist, und was zu tun ist (→ ZU TUN / → Nichts zu tun).
final class DeskMessagesTests: XCTestCase {

    private let names = DeskMessages.Names(app: { ["com.example.chat": "Chat", "com.example.mail": "Post"][$0] ?? $0 },
                                           display: { $0 == "NEBEN" ? "Kleiner Bildschirm" : "Großer Bildschirm" })

    private func ref(_ name: String?, _ display: String = "NEBEN", _ n: Int = 2) -> DeskRef {
        DeskRef(name: name, display: display, number: n)
    }

    func testRestartOneTellsWhichDesksAndWhatToDo() {
        let text = DeskMessages.issues([DeskIssue(desk: ref("Prod"), kind: .onOtherDisplay("HAUPT")),
                                        DeskIssue(desk: ref("Term", "NEBEN", 3), kind: .onOtherDisplay("HAUPT"))], names: names)
        XCTAssertEqual(text, "„Prod“ und „Term“ liegen nicht auf Kleiner Bildschirm.\n→ ZU TUN: Mission Control öffnen (F3) "
            + "und die Schreibtische auf die Leiste des richtigen Bildschirms ziehen. Seam räumt danach selbst auf.")
    }

    func testMissingDeskAsksToCreateOne() {
        let text = DeskMessages.issues([DeskIssue(desk: ref("Team", "NEBEN", 1), kind: .missing)], names: names) ?? ""
        XCTAssertTrue(text.hasPrefix("„Team“ fehlt."))
        XCTAssertTrue(text.contains("→ ZU TUN:"))
        XCTAssertTrue(text.contains("„+“"))
    }

    func testNoIssuesNoText() {
        XCTAssertNil(DeskMessages.issues([], names: names))
    }

    func testEverythingInPlace() {
        XCTAssertEqual(DeskMessages.result(DeskRunResult(), names: names), "Alles an seinem Platz.\n→ Nichts zu tun.")
    }

    func testNotRunningAppsAreNotATask() {
        let r = DeskRunResult(moved: 2, framed: 3, skipped: [DeskSkip(bundleID: "com.example.mail", reason: .notRunning)])
        XCTAssertEqual(DeskMessages.result(r, names: names), "Aufgeräumt: 2 Fenster verschoben, 3 Größen gesetzt.\n→ Nichts zu tun.")
    }

    func testFailuresNameTheAppsAndSayWhatToDo() {
        let r = DeskRunResult(moved: 1, framed: 1, skipped: [DeskSkip(bundleID: "com.example.chat", reason: .notGrabbable),
                                                             DeskSkip(bundleID: "com.example.chat", reason: .notVerified)])
        let text = DeskMessages.result(r, names: names)
        XCTAssertTrue(text.contains("Nicht geschafft: Chat."), "jede App nur einmal")
        XCTAssertTrue(text.hasSuffix("→ ZU TUN: diese Fenster von Hand an den Platz schieben."))
    }

    func testAbortsSayHowToContinue() {
        XCTAssertTrue(DeskMessages.result(DeskRunResult(moved: 1, aborted: .userInput), names: names).contains("⌃⌥⌘L"))
        XCTAssertTrue(DeskMessages.result(DeskRunResult(aborted: .modifiersStuck), names: names).contains("→ ZU TUN: einmal ⌃ drücken"))
    }

    func testAutomaticRunStaysQuietWhereNothingCanBeDone() {
        XCTAssertNil(DeskMessages.blocked(.noLayout, automatic: true))
        XCTAssertNil(DeskMessages.blocked(.cooldown, automatic: true))
        XCTAssertNil(DeskMessages.blocked(.screenLocked, automatic: false))
        XCTAssertNotNil(DeskMessages.blocked(.noLayout, automatic: false))
        XCTAssertTrue(DeskMessages.blocked(.switchKeysOff, automatic: true)?.contains("→ ZU TUN") ?? false)
    }

    func testSaved() {
        XCTAssertTrue(DeskMessages.saved(apps: 16).hasPrefix("Layout gespeichert: 16 Apps."))
        XCTAssertTrue(DeskMessages.saved(apps: 0).contains("→ ZU TUN"))
    }

    func testUnnamedDeskUsesNumber() {
        XCTAssertEqual(DeskMessages.label(ref(nil, "HAUPT", 4)), "Schreibtisch 4")
    }

    // MARK: code-audit 19.10.

    func testIssueTextFollowsAutomaticSwitch() {
        let issue = [DeskIssue(desk: ref("Prod"), kind: .onOtherDisplay("HAUPT"))]
        XCTAssertTrue(DeskMessages.issues(issue, names: names, autoTidy: true)?.hasSuffix("Seam räumt danach selbst auf.") ?? false)
        XCTAssertTrue(DeskMessages.issues(issue, names: names, autoTidy: false)?.hasSuffix("Danach ⌃⌥⌘L drücken.") ?? false)
    }

    func testRefusedSizeIsNamedButNoTask() {
        let r = DeskRunResult(moved: 1, skipped: [DeskSkip(bundleID: "com.example.chat", reason: .sizeRefused)])
        let text = DeskMessages.result(r, names: names)
        XCTAssertTrue(text.contains("Größe nicht übernommen: Chat"))
        XCTAssertTrue(text.hasSuffix("→ Nichts zu tun."))
    }

    func testUnreadableSpacesSayWhatToDo() {
        XCTAssertTrue(DeskMessages.blocked(.spacesUnavailable, automatic: false)?.contains("→ ZU TUN") ?? false)
        XCTAssertNil(DeskMessages.blocked(.spacesUnavailable, automatic: true))
    }
}
