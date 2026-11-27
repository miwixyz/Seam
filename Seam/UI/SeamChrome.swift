import SwiftUI

// Glas-Sprache der App-Familie für Seam (wie Knippi 0.7.0, Kalli 0.20.0, Qotti 1.7.0; Vault:
// „App-Familie Design-System“, Abschnitt „Glas-Sprache“). Hintergrund ist ein deckender, ruhig
// lebender Verlauf (`AmbientBackdrop`) statt des festen Familien-Verlaufs. Inhalte bleiben auf
// festen Karten (`familyCard`), Schwebendes auf Glas. Keine Insel-Lichter: im schmalen Popover
// werden sie zum dunklen Balken (Kalli 0.20.0, Runde 2).

extension View {
    /// Fenster- und Popover-Hintergrund der Glas-Sprache. Bei „Transparenz reduzieren“/„Kontrast
    /// erhöhen“ fester Familien-Verlauf, bei „Bewegung reduzieren“ stillstehend (im Kit geregelt).
    func familyAmbientBackground() -> some View {
        background(AmbientBackdrop(glow: 0.9).ignoresSafeArea())
    }

    /// Knopf in einer Glas-Insel: kein eigenes Glas, nur der Hover-Schatten des Kits.
    func islandButton(size: CGFloat = 30) -> some View {
        buttonStyle(.plain)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .familyHoverLift(in: Circle())
    }
}
