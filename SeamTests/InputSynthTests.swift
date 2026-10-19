import XCTest
@testable import Seam

/// docs/SECURE-DESIGN.md E17a: Was die einzige Datei mit künstlichen Eingaben darf.
/// Wer hier etwas ergänzt, muss E17a im Sicherheitsentwurf mit ändern.
final class InputSynthTests: XCTestCase {

    func testEventAllowlistIsExactlyTheDesignedSet() {
        XCTAssertEqual(Set(InputSynth.Kind.allCases.map(\.rawValue)),
                       ["mouseMove", "leftMouseDown", "leftMouseDragged", "leftMouseUp", "arrowWithControl", "releaseModifier"])
    }

    func testOnlyArrowKeysAndModifierRelease() {
        XCTAssertEqual(InputSynth.arrowLeft, 123)
        XCTAssertEqual(InputSynth.arrowRight, 124)
        XCTAssertEqual(InputSynth.releasedKeys, [59, 62, 63], "⌃ links, ⌃ rechts, fn")
    }

    func testStepsAreBounded() {
        XCTAssertFalse(InputSynth.validSteps(0))
        XCTAssertTrue(InputSynth.validSteps(-3))
        XCTAssertTrue(InputSynth.validSteps(InputSynth.maxSteps))
        XCTAssertFalse(InputSynth.validSteps(InputSynth.maxSteps + 1))
    }

    // MARK: Griffpunkt (E17a-2)

    func testNeverGripsControls() {
        for role in ["AXButton", "AXTab", "AXTextField", "AXLink", "AXPopUpButton", "AXCheckBox", "AXSearchField"] {
            XCTAssertFalse(InputSynth.isSafeGrip(role: role, actions: [], belongsToTarget: true), role)
        }
    }

    func testNeverGripsAnythingThatActs() {
        XCTAssertFalse(InputSynth.isSafeGrip(role: "AXGroup", actions: ["AXPress"], belongsToTarget: true))
        XCTAssertFalse(InputSynth.isSafeGrip(role: "AXGroup", actions: ["AXShowMenu", "AXConfirm"], belongsToTarget: true))
    }

    func testGripsPlainAreasOfTheTargetWindow() {
        // Gemessen 19.10.: Teams/Edge/Outlook antworten oben mit Gruppen ohne Aktion.
        XCTAssertTrue(InputSynth.isSafeGrip(role: "AXGroup", actions: [], belongsToTarget: true))
        XCTAssertTrue(InputSynth.isSafeGrip(role: "AXToolbar", actions: ["AXShowMenu"], belongsToTarget: true))
        XCTAssertTrue(InputSynth.isSafeGrip(role: "AXWindow", actions: ["AXRaise"], belongsToTarget: true))
    }

    func testNeverGripsAnotherWindowOrUnknownRole() {
        XCTAssertFalse(InputSynth.isSafeGrip(role: "AXGroup", actions: [], belongsToTarget: false))
        XCTAssertFalse(InputSynth.isSafeGrip(role: nil, actions: [], belongsToTarget: true))
    }

    func testCandidatesStayInTopBandAwayFromEdges() {
        let f = CGRect(x: 100, y: 200, width: 1000, height: 700)
        let c = InputSynth.gripCandidates(in: f)
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(c.first, CGPoint(x: f.midX, y: f.minY + 12), "Mitte, mittige Zeile zuerst")
        XCTAssertTrue(c.allSatisfy { $0.y >= f.minY + 4 && $0.y <= f.minY + 36 })
        XCTAssertTrue(c.allSatisfy { $0.x >= f.minX + 90 && $0.x <= f.maxX - 90 })
        XCTAssertLessThanOrEqual(c.count, 160)
    }

    func testTinyWindowHasNoCandidates() {
        XCTAssertTrue(InputSynth.gripCandidates(in: CGRect(x: 0, y: 0, width: 150, height: 100)).isEmpty)
    }

    // MARK: Eingreifen des Nutzers (E17b)

    func testMouseMovedByUser() {
        XCTAssertFalse(InputSynth.mouseIntervened(current: CGPoint(x: 100, y: 100), expected: CGPoint(x: 103, y: 101)))
        XCTAssertTrue(InputSynth.mouseIntervened(current: CGPoint(x: 140, y: 100), expected: CGPoint(x: 100, y: 100)))
    }

    func testKeyPressedAfterSeamsOwnKey() {
        // Seams eigene Taste vor 0,5 s; letzte Taste im System auch vor 0,5 s → niemand sonst.
        XCTAssertFalse(InputSynth.keyIntervened(idle: 0.5, ownAge: 0.5))
        // Letzte Taste vor 0,1 s, Seams eigene vor 0,5 s → der Nutzer.
        XCTAssertTrue(InputSynth.keyIntervened(idle: 0.1, ownAge: 0.5))
        // Letzte Taste lange vor dem Lauf.
        XCTAssertFalse(InputSynth.keyIntervened(idle: 300, ownAge: 2))
    }

    // MARK: code-audit 19.10.: Kurzbefehl muss auf ⌃← / ⌃→ liegen

    private func shortcut(_ on: Bool, _ code: Int, _ mods: Int) -> [String: Any] {
        ["enabled": on, "value": ["parameters": [65535, code, mods], "type": "standard"]]
    }

    func testMeasuredShortcutIsAccepted() {
        XCTAssertTrue(InputSynth.isSwitchShortcut(shortcut(true, 123, 262_144), key: InputSynth.arrowLeft), "gemessen bei Michael")
        XCTAssertTrue(InputSynth.isSwitchShortcut(shortcut(true, 124, 262_144 | 8_388_608), key: InputSynth.arrowRight), "fn erlaubt")
        XCTAssertTrue(InputSynth.isSwitchShortcut(nil, key: InputSynth.arrowLeft), "kein Eintrag = macOS-Standard")
    }

    func testOtherKeyOrModifierOrOffIsRejected() {
        XCTAssertFalse(InputSynth.isSwitchShortcut(shortcut(false, 123, 262_144), key: InputSynth.arrowLeft))
        XCTAssertFalse(InputSynth.isSwitchShortcut(shortcut(true, 18, 262_144), key: InputSynth.arrowLeft), "auf Taste 1 gelegt")
        XCTAssertFalse(InputSynth.isSwitchShortcut(shortcut(true, 123, 262_144 | 1_048_576), key: InputSynth.arrowLeft), "⌃⌘←")
        XCTAssertFalse(InputSynth.isSwitchShortcut(["enabled": true], key: InputSynth.arrowLeft), "kaputter Eintrag")
    }
}
