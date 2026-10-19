import XCTest

extension XCTestCase {
    /// Leere UserDefaults-Suite fuer einen Test.
    ///
    /// Alle Tests teilen EINE feste Suite, die vor und nach jedem Test geleert wird.
    /// Gemessen 19.10. (macOS 27): Je Test eine neue Suite (`seam.test.<UUID>`) hinterliess je
    /// Lauf eine plist in ~/Library/Preferences (98 Stueck); auch nach `removePersistentDomain`
    /// plus Loeschen legt cfprefsd sie beim Prozessende leer wieder an. Mit einem festen Namen
    /// bleibt hoechstens eine Datei. Setzt voraus, dass Tests nacheinander laufen (kein
    /// paralleles Testen eingestellt).
    func freshDefaults() -> UserDefaults {
        let name = "dev.mwlr.seam.tests"
        UserDefaults().removePersistentDomain(forName: name)
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("UserDefaults-Suite \(name) nicht anlegbar")
            return .standard
        }
        // Nur den Namen mitnehmen, nicht das Objekt (Swift 6: UserDefaults ist nicht Sendable).
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }
}
