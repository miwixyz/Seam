import AppKit
import SwiftUI
import XCTest
@testable import Seam

/// Absturz 18.11. (Seam-2026-11-18-101900.ips): Die Kachelliste griff mit alten Indizes auf
/// `model.windows` zu, nachdem die Liste geschrumpft war (Q im Umschalter, Dock-Vorschau).
@MainActor
final class WindowGridTests: XCTestCase {

    private func window(_ id: CGWindowID) -> CatalogWindow {
        CatalogWindow(id: id, pid: 0, title: "", frame: .zero, onScreen: true)
    }

    func testShrinkingListDoesNotCrash() {
        let model = PreviewModel()
        model.reset((1...5).map(window), size: .normal, columns: 3, selection: 4)
        let host = NSHostingView(rootView: WindowGridView(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()

        model.windows = [window(1)]
        model.selection = 0
        host.layoutSubtreeIfNeeded()
        model.windows = []
        host.layoutSubtreeIfNeeded()
    }

    /// Sichttest 18.11.: Q im Umschalter kommt mit gehaltenem ⌘ als ⌘Q an und beendete Seam selbst.
    /// Solange der Umschalter Tasten annimmt, gehören ⌘-Tasten ihm, nicht Seams Menü.
    func testCommandQGoesToSwitcherNotToSeamMenu() throws {
        let panel = PreviewPanel.make(model: PreviewModel())
        var got: [UInt16] = []
        panel.onKey = { got.append($0.keyCode) }
        let cmdQ = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                  characters: "q", charactersIgnoringModifiers: "q",
                                                  isARepeat: false, keyCode: 12))
        panel.acceptsKey = false
        XCTAssertFalse(panel.performKeyEquivalent(with: cmdQ))   // Dock-Vorschau / zu: nichts abfangen
        XCTAssertEqual(got, [])

        panel.acceptsKey = true
        XCTAssertTrue(panel.performKeyEquivalent(with: cmdQ))
        XCTAssertEqual(got, [12])
    }

    func testRowsKeepIndexAndWindowTogether() {
        let rows = WindowGridView.rows((1...5).map(window), columns: 2)
        XCTAssertEqual(rows.map { $0.map(\.index) }, [[0, 1], [2, 3], [4]])
        XCTAssertEqual(rows.map { $0.map(\.window.id) }, [[1, 2], [3, 4], [5]])
        XCTAssertTrue(WindowGridView.rows([], columns: 3).isEmpty)
    }
}
