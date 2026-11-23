import XCTest
@testable import Seam

/// Stream Deck (E20): feste Befehle, strenge Prüfung, Rückkanal ohne Inhalte.
final class DeckWireTests: XCTestCase {

    private func parse(_ json: String) -> DeckWire.Command? { DeckWire.parse(Data(json.utf8)) }

    func testValidCommands() {
        XCTAssertEqual(parse(#"{"v":1,"hello":"0.12.0"}"#), .hello(version: "0.12.0"))
        XCTAssertEqual(parse(#"{"v":1,"cmd":"seam","dir":-1}"#), .seam(dir: -1))
        XCTAssertEqual(parse(#"{"v":1,"cmd":"seam","dir":1}"#), .seam(dir: 1))
        XCTAssertEqual(parse(#"{"v":1,"cmd":"place","what":"left"}"#), .place(.left))
    }

    func testEveryPlaceMapsToItsSeamCommand() {
        for p in DeckWire.Place.allCases {
            XCTAssertEqual(DeckLink.command(for: .place(p))?.rawValue, p.rawValue, "\(p)")
        }
        XCTAssertNil(DeckLink.command(for: .hello(version: "1")))
        XCTAssertEqual(DeckLink.command(for: .seam(dir: 1)), .seamRight)
        XCTAssertEqual(DeckLink.command(for: .seam(dir: -1)), .seamLeft)
    }

    /// Neue Seam-Kommandos erscheinen nie von selbst am Deck: außer den festen Plätzen gibt es nur die zwei Naht-Befehle.
    func testDeckReachesNothingBeyondTheFixedList() {
        let reachable = Set(DeckWire.Place.allCases.compactMap { DeckLink.command(for: .place($0)) })
            .union([.seamLeft, .seamRight])
        XCTAssertEqual(reachable, Set(Command.allCases))
    }

    func testRejectsAnythingElse() {
        let bad = [
            #"{"v":2,"cmd":"seam","dir":1}"#, #"{"v":true,"cmd":"seam","dir":1}"#, #"{"v":1.5,"cmd":"seam","dir":1}"#,
            #"{"cmd":"seam","dir":1}"#,
            #"{"v":1,"cmd":"seam","dir":2}"#, #"{"v":1,"cmd":"seam","dir":0}"#, #"{"v":1,"cmd":"seam","dir":true}"#,
            #"{"v":1,"cmd":"seam","dir":"1"}"#, #"{"v":1,"cmd":"seam"}"#,
            #"{"v":1,"cmd":"seam","dir":1,"extra":1}"#,
            #"{"v":1,"cmd":"place","what":"deskTidy"}"#, #"{"v":1,"cmd":"place","what":"seamLeft"}"#,
            #"{"v":1,"cmd":"place","what":"left","x":1}"#, #"{"v":1,"cmd":"place"}"#,
            #"{"v":1,"cmd":"deskSave"}"#, #"{"v":1,"cmd":"wallpaper","dir":1}"#, #"{"v":1,"cmd":"shell","what":"left"}"#,
            #"{"v":1,"hello":"../../x"}"#, #"{"v":1,"hello":""}"#, #"{"v":1,"hello":"1.2.3.4.5.6.7.8.9.10.11"}"#,
            #"{"v":1,"hello":"0.12.0","cmd":"seam"}"#,
            "[]", "null", "{}", "nicht json", #"{"v":1,"cmd":["seam"],"dir":1}"#,
        ]
        for json in bad { XCTAssertNil(parse(json), json) }
    }

    func testRejectsOversizedPayload() {
        let big = #"{"v":1,"hello":""# + String(repeating: "1", count: 600) + #""}"#
        XCTAssertNil(parse(big))
    }

    func testFramingLimits() {
        var empty = Data([0, 0, 0, 0])
        XCTAssertEqual(DeckWire.nextFrame(&empty), .invalid)
        var huge = Data([0, 0, 0xFF, 0xFF])
        XCTAssertEqual(DeckWire.nextFrame(&huge), .invalid)
        var partial = Data([0, 0, 0, 10, 65])
        XCTAssertEqual(DeckWire.nextFrame(&partial), .needMore)
        let frame = DeckWire.frame(DeckWire.encode(.seam(dir: 1)))!
        var two = frame + frame
        XCTAssertEqual(DeckWire.nextFrame(&two), .message(frame.dropFirst(4)))
        XCTAssertEqual(two, frame)
    }

    func testStateRoundTripAndOnlyEnumerations() {
        let s = DeckWire.State(seam: .ok, stop: 12)
        let data = DeckWire.frame(DeckWire.encode(s))!.dropFirst(4)
        XCTAssertEqual(DeckWire.parseState(Data(data)), s)
        // Unbekannte Stufe kommt nicht aufs Gerät, unbekannter Zustand wird verworfen.
        XCTAssertNil(DeckWire.encode(DeckWire.State(seam: .ok, stop: 7))["seam"].flatMap { ($0 as? [String: Any])?["stop"] })
        XCTAssertNil(DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"kaputt"}}"#.utf8)))
        XCTAssertEqual(DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"noPair","stop":99}}"#.utf8)),
                       DeckWire.State(seam: .noPair, stop: nil))
        let text = (try? JSONSerialization.data(withJSONObject: DeckWire.encode(s))).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        XCTAssertFalse(text.contains("/"), "keine Pfade")
    }

    func testAck() {
        XCTAssertTrue(DeckWire.isAck(Data(#"{"v":1,"ok":true}"#.utf8)))
        XCTAssertFalse(DeckWire.isAck(Data(#"{"v":1,"ok":false}"#.utf8)))
        XCTAssertFalse(DeckWire.isAck(Data(#"{"v":1,"ok":1}"#.utf8)))
        XCTAssertFalse(DeckWire.isAck(Data(#"{"v":1,"ok":true,"x":1}"#.utf8)))
    }

    func testStateAfterCommands() {
        typealias DeckState = DeckWire.State
        XCTAssertEqual(DeckLink.state(.notRunning, nil, after: .seam(dir: 1)), DeckState(seam: .needsPermission, stop: nil))
        XCTAssertEqual(DeckLink.state(.noWindow, nil, after: .place(.left)), DeckState(seam: .noWindow, stop: nil))
        XCTAssertEqual(DeckLink.state(.done, .moved(stop: 15), after: .seam(dir: 1)), DeckState(seam: .ok, stop: 15))
        XCTAssertEqual(DeckLink.state(.done, .atEnd(stop: 16), after: .seam(dir: 1)), DeckState(seam: .atEnd, stop: 16))
        XCTAssertEqual(DeckLink.state(.done, .noPair, after: .seam(dir: -1)), DeckState(seam: .noPair, stop: nil))
        // Naht-Befehl ohne Ergebnis (Fenster nicht lesbar): nie „ok“ melden.
        XCTAssertEqual(DeckLink.state(.done, nil, after: .seam(dir: 1)), DeckState(seam: .noWindow, stop: nil))
        // Nach einem Platz-Befehl ist die Stufe unbekannt, ein altes Naht-Ergebnis darf nicht durchscheinen.
        XCTAssertEqual(DeckLink.state(.done, .moved(stop: 15), after: .place(.left)), DeckState(seam: .ok, stop: nil))
    }

    func testRequirementsPinIdentifierAndTeam() {
        XCTAssertTrue(DeckWire.pluginRequirement.contains(#"identifier "dev.mwlr.seam.deck""#))
        XCTAssertTrue(DeckWire.pluginRequirement.contains("LTKJ6Z2VYB"))
        XCTAssertTrue(DeckWire.seamRequirement.contains(#"identifier "dev.mwlr.seam""#))
        XCTAssertTrue(DeckWire.streamDeckRequirement.contains("Y93VXCB8Q5"))
        for r in [DeckWire.pluginRequirement, DeckWire.seamRequirement, DeckWire.streamDeckRequirement] {
            var req: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(r as CFString, [], &req), errSecSuccess, r)
        }
    }
}
