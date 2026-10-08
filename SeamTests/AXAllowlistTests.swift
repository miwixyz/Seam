import XCTest
@testable import Seam

/// docs/SECURE-DESIGN.md E3: Seam liest von fremden Fenstern nur Struktur, Rolle, Lage
/// und Größe. Die Lint-Regel `ax_nur_ueber_allowlist` verhindert Lesen an der Liste
/// vorbei; dieser Test verhindert, dass die Liste selbst still erweitert wird.
/// Wer hier ein Attribut ergänzt, muss E3 im Sicherheitsentwurf mit ändern.
final class AXAllowlistTests: XCTestCase {

    func testAllowlistIsExactlyTheDesignedSet() {
        XCTAssertEqual(Set(AXAttribute.allCases.map(\.rawValue)), [
            "AXRole", "AXSubrole", "AXPosition", "AXSize", "AXMinimized", "AXFullScreen",
            "AXWindow", "AXWindows", "AXFocusedApplication", "AXFocusedWindow",
        ])
    }

    func testNoContentOrTitleAttributes() {
        let forbidden = ["AXTitle", "AXValue", "AXDescription", "AXSelectedText", "AXDocument", "AXURL"]
        for f in forbidden {
            XCTAssertFalse(AXAttribute.allCases.contains { $0.rawValue == f }, "\(f) verletzt E3")
        }
    }
}
