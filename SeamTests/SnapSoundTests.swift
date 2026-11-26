import XCTest
@testable import Seam

/// Ton beim Einrasten: ab Werk aus, Einstellung bleibt erhalten, Datei liegt im Bündel.
final class SnapSoundTests: XCTestCase {

    @MainActor
    func testSnapSoundDefaultsOff() {
        XCTAssertFalse(Preferences(defaults: freshDefaults()).snapSound)
    }

    @MainActor
    func testSnapSoundPersists() {
        let d = freshDefaults()
        Preferences(defaults: d).snapSound = true
        XCTAssertTrue(Preferences(defaults: d).snapSound)
    }

    /// Test-Host ist die App: seam.caf muss im Bündel liegen, sonst schweigt der Ton (nur Protokoll).
    func testSoundFileInBundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: "seam", withExtension: "caf"))
    }

    /// Menüleisten-Symbole und App-Symbol kommen aus dem Asset-Katalog.
    @MainActor
    func testMenuBarImagesInBundle() {
        for name in ["MenuBarSeam", "MenuBarSeamSlash", "MenuBarSeamFill"] {
            let img = NSImage(named: name)
            XCTAssertNotNil(img, name)
            XCTAssertEqual(img?.isTemplate, true, name)
            XCTAssertEqual(img?.size, NSSize(width: 18, height: 18), name)
        }
    }
}
