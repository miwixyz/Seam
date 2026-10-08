import Foundation

/// Setzt Fensterrahmen auf einer eigenen Warteschlange, nicht auf dem Hauptthread,
/// jeweils mit Nachprüfung (`setVerified`).
///
/// Gemessen 2026-10-08: Ein Setzen bei Outlook dauerte bis 56 ms, Edge übernahm Rahmen
/// teils erst beim zweiten Versuch. Auf dem Hauptthread blockierte das Seam.
final class NeighborWriter: @unchecked Sendable {

    private let queue = DispatchQueue(label: "dev.mwlr.seam.setzen", qos: .userInteractive)

    /// Mehrere Schritte nacheinander auf der Warteschlange (nach allen Zwischenständen).
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    // MARK: - Setzen mit Nachprüfung

    /// Setzt einen Rahmen und prüft nach, bis er sitzt.
    ///
    /// Gemessen 2026-10-08 an Edge und Outlook: Ein einmaliges Setzen landete bei ⌃⌥→
    /// auf x 2449 / Breite 991 oder x 880 statt x 1723 / 1712, und direkt nach dem
    /// Größeziehen nahm Edge 200 ms lang keine Position an. Daher wachsende Pausen bis
    /// ~1,5 s. **Aber:** Liefert die App zweimal hintereinander denselben abweichenden
    /// Rahmen, hat sie sich festgelegt (Mindestgröße), dann sofort aufhören. Ohne diese
    /// Regel dauerte die Mindestgrößen-Korrektur 2,4 s, so lange lagen die Fenster
    /// sichtbar übereinander (Bildschirmaufnahme 08.10.).
    static let retryDelays: [useconds_t] = [50_000, 100_000, 200_000, 400_000, 800_000]

    @discardableResult
    static func setVerified(_ w: AXWindow, _ r: CGRect) -> CGRect? {
        setVerifiedCounting(w, r).frame
    }

    /// Wie `setVerified`, liefert zusätzlich die Zahl der Versuche (Messpunkt: Nach dem
    /// Loslassen vergingen am 08.10. bis zu 1,7 s bis zum Endzustand).
    static func setVerifiedCounting(_ w: AXWindow, _ r: CGRect) -> (frame: CGRect?, attempts: Int) {
        var previous: CGRect?
        var attempts = 0
        for delay in retryDelays {
            attempts += 1
            w.setFrame(r)
            usleep(delay)
            guard let a = w.frame else { return (nil, attempts) }
            if close(a, r) { return (a, attempts) }
            // Mindestgröße: Lage sitzt, nur die Größe weicht ab, und das zweimal gleich.
            // NICHT bei abweichender Lage: Das ist Edges kurze Positionssperre nach dem
            // Größeziehen, dort liefert die App ebenfalls zweimal denselben Wert, nimmt
            // die Position aber kurz danach an.
            let originOK = abs(a.minX - r.minX) <= 2 && abs(a.minY - r.minY) <= 2
            if originOK, let p = previous, close(p, a) { return (a, attempts) }
            previous = a
        }
        return (previous, attempts)
    }

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
