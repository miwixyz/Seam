import AppKit
import SwiftUI
import XCTest
@testable import Seam

/// Q9 (Code-Audit 09.10.): SnapOverlay nutzt `NSColor(FamilyTheme.accent)`. Das ist nur richtig,
/// wenn die Farbe dabei dynamisch bleibt (hell #3E5398, dunkel #98A9E1).
final class ThemeTests: XCTestCase {

    private func rgb(_ c: NSColor, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let s = c.usingColorSpace(.sRGB)!
            out = [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    @MainActor
    func testSeamAccentStaysDynamicAsNSColor() {
        FamilyTheme.app = .seam
        let c = NSColor(FamilyTheme.accent)
        XCTAssertEqual(rgb(c, .aqua), [0x3E, 0x53, 0x98])
        XCTAssertEqual(rgb(c, .darkAqua), [0x98, 0xA9, 0xE1])
    }
}
