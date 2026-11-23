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
        XCTAssertEqual(parse(#"{"v":1,"cmd":"deskSave"}"#), .deskSave)
        XCTAssertEqual(parse(#"{"v":1,"cmd":"deskTidy"}"#), .deskTidy)
        XCTAssertEqual(parse(#"{"v":1,"cmd":"wallpaper","dir":1}"#), .wallpaper(dir: 1))
        XCTAssertEqual(parse(#"{"v":1,"cmd":"wallpaper","dir":-1}"#), .wallpaper(dir: -1))
    }

    func testHelloCanAnnouncePreviewAndPreviewMessagesAreStrict() {
        XCTAssertEqual(parse(#"{"v":1,"hello":"1.3.0","preview":true}"#), .hello(version: "1.3.0", preview: true))
        XCTAssertEqual(parse(#"{"v":1,"hello":"1.3.0","preview":false}"#), .hello(version: "1.3.0", preview: false))
        XCTAssertNil(parse(#"{"v":1,"hello":"1.3.0","preview":1}"#))
        XCTAssertNil(parse(#"{"v":1,"hello":"1.3.0","preview":"ja"}"#))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let frame = DeckWire.frame(DeckWire.encodePreview(jpeg)!, max: DeckWire.maxPreviewFrame)!.dropFirst(4)
        XCTAssertEqual(DeckWire.parsePreview(Data(frame)), .some(jpeg))
        let none = DeckWire.frame(DeckWire.encodePreview(nil)!, max: DeckWire.maxPreviewFrame)!.dropFirst(4)
        XCTAssertEqual(DeckWire.parsePreview(Data(none)), .some(nil))
        XCTAssertNil(DeckWire.encodePreview(Data(repeating: 0xFF, count: DeckWire.maxPreviewBytes + 1)), "zu groß wird nie gesendet")
        XCTAssertNil(DeckWire.encodePreview(Data([1, 2, 3])), "kein JPEG wird nie gesendet")
        XCTAssertNil(DeckWire.parsePreview(Data(#"{"v":1,"preview":"AAAA"}"#.utf8)), "Base64, aber kein JPEG")
        XCTAssertNil(DeckWire.parsePreview(Data(#"{"v":1,"preview":"/9g=","x":1}"#.utf8)), "fremdes Feld")
        XCTAssertNil(DeckWire.parsePreview(Data(#"{"v":1,"seam":{"state":"ok"}}"#.utf8)), "Zustand ist keine Vorschau")
        var big = Data([0, 0, 0x20, 0x01])   // 8193 Byte
        XCTAssertEqual(DeckWire.nextFrame(&big, max: DeckWire.maxPreviewFrame), .invalid, "Rahmen über 8 KB bleibt ungültig")
    }

    func testWallpaperCommandRejectsPathsAndOddValues() {
        for json in [#"{"v":1,"cmd":"wallpaper","dir":0}"#, #"{"v":1,"cmd":"wallpaper","dir":2}"#, #"{"v":1,"cmd":"wallpaper"}"#,
                     #"{"v":1,"cmd":"wallpaper","dir":true}"#, #"{"v":1,"cmd":"wallpaper","dir":1,"path":"/etc/passwd"}"#,
                     #"{"v":1,"cmd":"wallpaper","dir":1,"file":"a.jpg"}"#, #"{"v":1,"cmd":"wallpaper","dir":"1"}"#] {
            XCTAssertNil(parse(json), json)
        }
    }

    func testWallpaperStateCarriesOnlyCountsAndEnumerations() {
        let w = DeckWire.Wallpaper(phase: .ok, index: 3, count: 12, dark: true, kind: .video)
        let s = DeckWire.State(seam: .ok, stop: nil, desk: nil, wallpaper: w)
        XCTAssertEqual(DeckWire.parseState(Data(DeckWire.frame(DeckWire.encode(s))!.dropFirst(4)))?.wallpaper, w)
        let bad = DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"ok"},"wallpaper":{"state":"ok","index":9,"count":3,"kind":"/etc/x"}}"#.utf8))
        XCTAssertEqual(bad?.wallpaper, DeckWire.Wallpaper(phase: .ok, index: nil, count: nil, dark: nil, kind: nil),
                       "Stelle außerhalb des Rings und freier Text fallen weg")
        XCTAssertNil(DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"ok"},"wallpaper":{"state":"x"}}"#.utf8))?.wallpaper)
        let big = DeckWire.Wallpaper(phase: .ok, index: 1, count: 5000, dark: nil, kind: nil)
        let enc = DeckWire.encode(DeckWire.State(seam: .ok, stop: nil, desk: nil, wallpaper: big))["wallpaper"] as? [String: Any]
        XCTAssertNil(enc?["count"], "Ring über 200 geht nicht aufs Gerät")
    }

    func testEveryDeskReasonCovered() {
        let blocks: [DeskBlock] = [.noLayout, .noAccessibility, .switchKeysOff, .screenLocked, .fullScreenActive, .cooldown,
                                   .alreadyRunning, .spacesUnavailable]
        XCTAssertEqual(Set(blocks.map(DeckLink.reason(for:))).count, blocks.count, "jeder Grund hat einen eigenen Wert")
        XCTAssertEqual(DeckLink.reason(for: DeskRunResult.Abort.userInput), .userInput)
        XCTAssertEqual(DeckLink.reason(for: DeskRunResult.Abort.modifiersStuck), .modifiersStuck)
        XCTAssertEqual(DeckLink.reason(for: DeskRunResult.Abort.timeLimit), .timeLimit)
        XCTAssertGreaterThanOrEqual(DeckLink.deskInterval, 3)
        XCTAssertGreaterThanOrEqual(DeckLink.wallpaperInterval, 1.5)
    }

    func testDeskStateRoundTripCarriesOnlyEnumerationsAndACount() {
        let desk = DeckWire.Desk(phase: .saved, apps: 14, last: .blocked, reason: .fullScreen, cmd: .tidy)
        let s = DeckWire.State(seam: .ok, stop: nil, desk: desk)
        let data = DeckWire.frame(DeckWire.encode(s))!.dropFirst(4)
        XCTAssertEqual(DeckWire.parseState(Data(data))?.desk, desk)
        XCTAssertNil(DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"ok"},"desk":{"state":"kaputt"}}"#.utf8))?.desk)
        let odd = DeckWire.parseState(Data(#"{"v":1,"seam":{"state":"ok"},"desk":{"state":"saved","apps":-3,"reason":"Safari"}}"#.utf8))
        XCTAssertEqual(odd?.desk, DeckWire.Desk(phase: .saved, apps: nil, last: nil, reason: nil, cmd: nil),
                       "falsche Zahl und freier Text fallen weg")
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
            #"{"v":1,"cmd":"deskSave","what":"x"}"#, #"{"v":1,"cmd":"deskTidy","dir":1}"#, #"{"v":1,"cmd":"deskTidy2"}"#,
            #"{"v":1,"cmd":"deskDelete"}"#, #"{"v":1,"cmd":"wallpaperNext","dir":1}"#, #"{"v":1,"cmd":"shell","what":"left"}"#,
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
