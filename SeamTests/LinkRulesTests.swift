import XCTest
@testable import Seam

/// docs/SECURE-DESIGN.md E16: Annahme, Website-Vergleich, Entscheidung, Tracking, gespeicherte Regeln.
final class LinkRulesTests: XCTestCase {

    private let chrome = "com.google.Chrome"
    private let safari = "com.apple.Safari"
    private let edge = "com.microsoft.edgemac"
    private lazy var available: Set<String> = [chrome, safari, edge]

    // MARK: E16b

    func testAcceptsOnlyHttpAndHttpsWithHost() {
        XCTAssertNotNil(LinkRules.accept("https://cineweb.de/kino"))
        XCTAssertNotNil(LinkRules.accept("HTTP://example.com"))
        XCTAssertNil(LinkRules.accept("file:///etc/passwd"))
        XCTAssertNil(LinkRules.accept("javascript:alert(1)"))
        XCTAssertNil(LinkRules.accept("x-apple.systempreferences:com.apple.preference.security"))
        XCTAssertNil(LinkRules.accept("https://"))
        XCTAssertNil(LinkRules.accept("https:///pfad"))
        XCTAssertNil(LinkRules.accept(""))
    }

    func testRejectsOverlongURL() {
        let long = "https://example.com/?q=" + String(repeating: "a", count: LinkRules.maxURLLength)
        XCTAssertNil(LinkRules.accept(long))
    }

    // MARK: E16e

    func testHostMatchesExactAndSubdomainOnly() {
        XCTAssertTrue(LinkRules.hostMatches("cineweb.de", rule: "cineweb.de"))
        XCTAssertTrue(LinkRules.hostMatches("www.cineweb.de", rule: "cineweb.de"))
        XCTAssertFalse(LinkRules.hostMatches("evilcineweb.de", rule: "cineweb.de"))
        XCTAssertFalse(LinkRules.hostMatches("cineweb.de.evil.com", rule: "cineweb.de"))
        XCTAssertFalse(LinkRules.hostMatches("cineweb.com", rule: "cineweb.de"))
    }

    /// Rafter-Review 10.10.: Host so, wie der Browser ihn öffnet; Tricks treffen keine fremde Regel.
    func testURLHostIsStrictAndDecoded() {
        XCTAssertEqual(LinkRules.urlHost(url("https://cineweb.de@evil.com/")), "evil.com")
        XCTAssertEqual(LinkRules.urlHost(url("https://cineweb.de:443@evil.com/")), "evil.com")
        XCTAssertEqual(LinkRules.urlHost(url("https://evil.com?@cineweb.de")), "evil.com")
        XCTAssertEqual(LinkRules.urlHost(url("https://evil.com#@cineweb.de")), "evil.com")
        XCTAssertEqual(LinkRules.urlHost(url("https://CINEWEB.DE./x")), "cineweb.de")
        XCTAssertEqual(LinkRules.urlHost(url("https://cineweb.de:8080/x")), "cineweb.de")
        XCTAssertEqual(LinkRules.urlHost(url("https://cineweb%2Ede/")), "cineweb.de")
        XCTAssertNil(LinkRules.urlHost(url("https://evil%2Ecom%2F.cineweb.de/")))
        XCTAssertNil(LinkRules.urlHost(url("https://[::1]/")))
        XCTAssertNil(LinkRules.urlHost(url("https://a.cineweb.de..evil.com/")))
    }

    func testIDNHostBecomesPunycodeOrNil() {
        if let h = LinkRules.urlHost(url("https://b%C3%BCcher.de/")) {
            XCTAssertEqual(h, "xn--bcher-kva.de")
        }
        XCTAssertFalse(LinkRules.urlHost(url("https://b%C3%BCcher.de/"))?.contains("%") ?? false)
    }

    func testTricksDoNotMatchForeignRule() {
        let rules = [LinkRule(host: "cineweb.de", browser: chrome)]
        for s in ["https://cineweb.de@evil.com/", "https://evil.com?@cineweb.de", "https://evilcineweb.de/",
                  "https://evil%2Ecom%2F.cineweb.de/"] {
            XCTAssertEqual(LinkRules.decide(url: url(s), source: nil, rules: rules, available: available,
                                            fallback: safari), safari, s)
        }
        XCTAssertEqual(LinkRules.decide(url: url("https://cineweb%2Ede/"), source: nil, rules: rules,
                                        available: available, fallback: safari), chrome)
    }

    func testSourceOnlyRuleWorksWithoutValidHost() {
        let rules = [LinkRule(sourceApp: "com.apple.mail", browser: edge)]
        XCTAssertEqual(LinkRules.decide(url: url("https://[::1]/"), source: "com.apple.mail", rules: rules,
                                        available: available, fallback: safari), edge)
    }

    func testBounceIsDetectedOnlyWithinWindowAndFromTarget() {
        var r = RecentHandoffs()
        let u = url("https://example.com/a")
        let t0 = Date()
        r.record(u, to: "com.example.Router", now: t0)
        XCTAssertTrue(r.isBounce(u, from: "com.example.router", now: t0.addingTimeInterval(1)))
        XCTAssertFalse(r.isBounce(u, from: "com.apple.mail", now: t0.addingTimeInterval(1)))
        XCTAssertFalse(r.isBounce(url("https://example.com/b"), from: "com.example.Router", now: t0.addingTimeInterval(1)))
        XCTAssertFalse(r.isBounce(u, from: "com.example.Router", now: t0.addingTimeInterval(3)))
        XCTAssertFalse(r.isBounce(u, from: nil, now: t0))
    }

    func testNormalizeHostFromUserInput() {
        XCTAssertEqual(LinkRules.normalizeHost("https://www.CineWeb.de/kino?x=1"), "www.cineweb.de")
        XCTAssertEqual(LinkRules.normalizeHost("  cineweb.de/ "), "cineweb.de")
        XCTAssertEqual(LinkRules.normalizeHost(".cineweb.de."), "cineweb.de")
        XCTAssertNil(LinkRules.normalizeHost(""))
        XCTAssertNil(LinkRules.normalizeHost("cine web.de"))
        XCTAssertNil(LinkRules.normalizeHost("a..b"))
        XCTAssertNil(LinkRules.normalizeHost("*.cineweb.de"))
    }

    // MARK: Entscheidung

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testFirstMatchingRuleWins() {
        let rules = [
            LinkRule(host: "cineweb.de", browser: chrome),
            LinkRule(host: "de", browser: edge),
        ]
        XCTAssertEqual(LinkRules.decide(url: url("https://www.cineweb.de"), source: nil, rules: rules,
                                        available: available, fallback: safari), chrome)
        XCTAssertEqual(LinkRules.decide(url: url("https://heise.de"), source: nil, rules: rules,
                                        available: available, fallback: safari), edge)
        XCTAssertEqual(LinkRules.decide(url: url("https://apple.com"), source: nil, rules: rules,
                                        available: available, fallback: safari), safari)
    }

    func testSourceAppRuleAndCombinedRule() {
        let slack = "com.tinyspeck.slackmacgap"
        let rules = [
            LinkRule(host: "figma.com", sourceApp: slack, browser: chrome),
            LinkRule(sourceApp: slack, browser: edge),
        ]
        XCTAssertEqual(LinkRules.decide(url: url("https://figma.com/x"), source: slack, rules: rules,
                                        available: available, fallback: safari), chrome)
        XCTAssertEqual(LinkRules.decide(url: url("https://figma.com/x"), source: "com.apple.mail", rules: rules,
                                        available: available, fallback: safari), safari)
        XCTAssertEqual(LinkRules.decide(url: url("https://apple.com"), source: slack, rules: rules,
                                        available: available, fallback: safari), edge)
        // Absender unbekannt → nur Website-Regeln (E16f).
        XCTAssertEqual(LinkRules.decide(url: url("https://apple.com"), source: nil, rules: rules,
                                        available: available, fallback: safari), safari)
    }

    func testUnavailableTargetFallsBackNeverLoops() {
        let rules = [LinkRule(host: "cineweb.de", browser: "dev.mwlr.seam")]
        XCTAssertEqual(LinkRules.decide(url: url("https://cineweb.de"), source: nil, rules: rules,
                                        available: available, fallback: safari), safari)
        // Standard-Browser selbst nicht verfügbar (z. B. Seam oder Velja eingetragen) → Auswahl.
        XCTAssertNil(LinkRules.decide(url: url("https://cineweb.de"), source: nil, rules: rules,
                                      available: available, fallback: "com.sindresorhus.velja"))
        XCTAssertNil(LinkRules.decide(url: url("https://cineweb.de"), source: nil, rules: [],
                                      available: available, fallback: nil))
    }

    func testDecisionIsFastWith200Rules() {
        let rules = (0..<200).map { LinkRule(host: "site\($0).example", browser: chrome) }
        let u = url("https://nichts.example/pfad")
        let start = Date()
        for _ in 0..<100 {
            _ = LinkRules.decide(url: u, source: "x", rules: rules, available: available, fallback: safari)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 100, 0.001, "Entscheidung muss < 1 ms bleiben")
    }

    // MARK: E16g – Tasten für die Auswahl (0.5.2)

    func testPickerKeysEachWorkAlone() {
        let all = Set(PickerKey.allCases)
        XCTAssertTrue(LinkRules.pickerRequested(HeldKeys(fn: true), keys: [.fn]))
        XCTAssertTrue(LinkRules.pickerRequested(HeldKeys(option: true), keys: [.option]))
        XCTAssertTrue(LinkRules.pickerRequested(HeldKeys(shift: true), keys: [.shift]))
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(), keys: all))
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(fn: true, option: true, shift: true, control: true), keys: []))
    }

    func testOnlyChosenKeysCount() {
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(fn: true), keys: [.option]))
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(shift: true), keys: [.fn, .option]))
    }

    func testControlOptionNeedsBoth() {
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(control: true), keys: [.controlOption]))
        XCTAssertFalse(LinkRules.pickerRequested(HeldKeys(option: true), keys: [.controlOption]))
        XCTAssertTrue(LinkRules.pickerRequested(HeldKeys(option: true, control: true), keys: [.controlOption]))
    }

    func testStoredPickerKeys() {
        XCTAssertEqual(LinkRules.pickerKeys(from: nil), [.fn, .option])
        XCTAssertEqual(LinkRules.pickerKeys(from: []), [])
        XCTAssertEqual(LinkRules.pickerKeys(from: ["shift", "unsinn", "fn"]), [.shift, .fn])
    }

    // MARK: E16c

    @MainActor
    func testRoutersAreExcludedCaseInsensitive() {
        XCTAssertTrue(Browsers.isExcluded("com.sindresorhus.Velja"))
        XCTAssertTrue(Browsers.isExcluded("dev.mwlr.seam"))
        XCTAssertTrue(Browsers.isExcluded("com.choosyosx.Choosy"))
        XCTAssertFalse(Browsers.isExcluded("com.apple.Safari"))
    }

    // MARK: E16h

    func testStripsTrackingKeepsEverythingElse() {
        let u = url("https://example.com/a/b?id=7&utm_source=nl&UTM_Medium=x&fbclid=abc&q=k%C3%BC#teil")
        XCTAssertEqual(LinkRules.stripTracking(u).absoluteString, "https://example.com/a/b?id=7&q=k%C3%BC#teil")
    }

    func testAllParamsRemovedLeavesNoQuestionMark() {
        let u = url("https://example.com/x?utm_source=a&gclid=b")
        XCTAssertEqual(LinkRules.stripTracking(u).absoluteString, "https://example.com/x")
    }

    func testUnchangedURLStaysByteIdentical() {
        let signed = "https://bucket.s3.amazonaws.com/f.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=ab%2Bcd&X-Amz-Expires=60"
        XCTAssertEqual(LinkRules.stripTracking(url(signed)).absoluteString, signed)
        let plain = "https://example.com/pfad#anker"
        XCTAssertEqual(LinkRules.stripTracking(url(plain)).absoluteString, plain)
    }

    func testSiOnlyOnKnownHosts() {
        XCTAssertEqual(LinkRules.stripTracking(url("https://youtu.be/abc?si=xyz")).absoluteString, "https://youtu.be/abc")
        XCTAssertEqual(LinkRules.stripTracking(url("https://example.com/?si=1")).absoluteString, "https://example.com/?si=1")
    }

    // MARK: E16i

    func testSanitizeDropsInvalidAndCaps() {
        let rules = [
            LinkRule(host: "https://www.CineWeb.de/x", browser: chrome),
            LinkRule(host: "kaputt host", browser: chrome),
            LinkRule(browser: chrome),
            LinkRule(sourceApp: "evil app;rm", browser: chrome),
            LinkRule(host: "ok.de", browser: "/Applications/Evil.app"),
        ] + (0..<300).map { LinkRule(host: "s\($0).de", browser: safari) }
        let clean = LinkRules.sanitize(rules)
        XCTAssertEqual(clean.count, LinkRules.maxRules)
        XCTAssertEqual(clean.first?.host, "www.cineweb.de")
        XCTAssertEqual(clean[1].host, "s0.de")
    }

    func testDecodeSkipsBrokenEntriesAndUnknownFields() {
        let json = """
        [{"id":"\(UUID().uuidString)","host":"cineweb.de","browser":"\(chrome)","script":"rm -rf"},
         {"host":42},
         {"id":"\(UUID().uuidString)","sourceApp":"com.apple.mail","browser":"\(edge)"}]
        """
        let rules = LinkRules.decode(Data(json.utf8))
        XCTAssertEqual(rules.map(\.browser), [chrome, edge])
        XCTAssertEqual(LinkRules.decode(Data("kein json".utf8)), [])
        XCTAssertEqual(LinkRules.decode(nil), [])
    }
}
