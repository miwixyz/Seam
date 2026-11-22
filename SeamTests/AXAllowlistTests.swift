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
            "AXWindows", "AXFocusedApplication", "AXFocusedWindow",
            "AXWindow",   // E17a: Elternfenster am Griffpunkt (19.10.)
            // E21e: nur am Dock-Prozess über AXAccess.dock… (18.11.); Lint `dock_attribute_nur_in_axaccess`.
            "AXChildren", "AXSelectedChildren", "AXURL",
        ])
    }

    /// E12: genau eine Aktion auf fremden Fenstern. Wer hier ergänzt, ändert E12 mit.
    func testActionAllowlistIsOnlyRaise() {
        XCTAssertEqual(Set(AXActionName.allCases.map(\.rawValue)), ["AXRaise"])
    }

    /// E24b: eigene Liste für die Menüleiste. `AXTitle` nur hier, nie in `AXAttribute` (Fenster).
    /// Wer hier ergänzt, ändert E24b im Sicherheitsentwurf mit.
    func testMenuAllowlistIsExactlyTheDesignedSet() {
        XCTAssertEqual(Set(AXMenuAttribute.allCases.map(\.rawValue)), [
            "AXMenuBar", "AXChildren", "AXRole", "AXTitle",
            "AXMenuItemCmdChar", "AXMenuItemCmdModifiers", "AXMenuItemCmdVirtualKey",
        ])
    }

    func testNoContentOrTitleAttributes() {
        // AXURL ist seit E21e erlaubt, aber nur am Dock (Lint-Regel), daher nicht mehr in dieser Liste.
        let forbidden = ["AXTitle", "AXValue", "AXDescription", "AXSelectedText", "AXDocument"]
        for f in forbidden {
            XCTAssertFalse(AXAttribute.allCases.contains { $0.rawValue == f }, "\(f) verletzt E3")
        }
    }
}
