import Foundation
import ServiceManagement

/// Start bei der Anmeldung.
///
/// **Bewusst ohne eigene Einstellung in `Preferences`.** Der wahre Zustand liegt
/// bei macOS (`SMAppService`), nicht bei uns. Ein gespiegeltes `Bool` in den
/// UserDefaults würde beim ersten Eingriff von außen falsch — der Nutzer kann
/// den Eintrag jederzeit in den Systemeinstellungen abschalten, ohne dass Seam
/// davon erfährt. Dann stünde in unserem Schalter „an", während nichts startet.
///
/// Deshalb wird der Status bei jedem Lesen frisch erfragt.
@MainActor
enum LoginItem {

    enum State {
        case on
        case off
        /// macOS hat den Eintrag angelegt, der Nutzer muss ihn noch freigeben.
        case needsApproval
        /// Registrierung nicht möglich — typisch für Builds, die nicht an einem
        /// festen Ort liegen oder keine stabile Signatur haben.
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .notRegistered: .off
        case .requiresApproval: .needsApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    /// Schaltet um. Gibt den Fehler zurück, statt ihn zu schlucken — ein still
    /// fehlgeschlagener Autostart sieht aus wie ein funktionierender.
    @discardableResult
    static func set(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }

    /// Öffnet die Systemeinstellungen an der Stelle, an der der Nutzer den
    /// Eintrag freigeben kann.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
