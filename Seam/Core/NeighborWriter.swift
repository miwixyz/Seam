import Foundation

/// Setzt Fensterrahmen (und hebt an / minimiert, E12) auf einer eigenen Warteschlange, nicht
/// auf dem Hauptthread. Fensterrahmen jeweils mit Nachprüfung (`setVerified`).
///
/// Gemessen 2026-10-08: Ein Setzen bei Outlook dauerte bis 56 ms, Edge übernahm Rahmen
/// teils erst beim zweiten Versuch. Auf dem Hauptthread blockierte das Seam.
///
/// **Eine Instanz für die ganze App** (Code-Audit 09.10., R4): Vorher hatten WindowActions,
/// DragController und PairKeeper je eine eigene Warteschlange; ein Kürzel und das Loslassen
/// nach einem Ziehen setzten dasselbe Fenster dann parallel und abwechselnd.
final class NeighborWriter: @unchecked Sendable {

    private let queue = DispatchQueue(label: "dev.mwlr.seam.setzen", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0

    /// Mehrere Schritte nacheinander auf der Warteschlange (nach allen Zwischenständen).
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Noch laufende Wiederholungen abbrechen (Code-Audit 09.10., R3): Beginnt der Nutzer eine
    /// neue Geste, während Seam noch bis ~1,5 s nachsetzt, hielt die neue Geste Seams eigene
    /// Setz-Meldungen für eine Bewegung des Nutzers. Aufruf bei jedem Mausklick.
    func cancelRetries() {
        lock.lock(); generation += 1; lock.unlock()
    }

    /// Marke für einen Auftrag; `isCurrent(marke)` ist false, sobald `cancelRetries` lief.
    func mark() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    func isCurrent(_ m: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == m
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
    static func setVerified(_ w: AXWindow, _ r: CGRect, while stillWanted: () -> Bool = { true }) -> CGRect? {
        setVerifiedCounting(w, r, while: stillWanted).frame
    }

    /// Wie `setVerified`, liefert zusätzlich die Zahl der Versuche (Messpunkt: Nach dem
    /// Loslassen vergingen am 08.10. bis zu 1,7 s bis zum Endzustand).
    /// `stillWanted`: zwischen den Versuchen gefragt; false = abbrechen (neue Geste, R3).
    static func setVerifiedCounting(_ w: AXWindow, _ r: CGRect,
                                    while stillWanted: () -> Bool = { true }) -> (frame: CGRect?, attempts: Int) {
        var previous: CGRect?
        var attempts = 0
        for delay in retryDelays {
            guard stillWanted() else { return (previous, attempts) }
            attempts += 1
            w.setFrame(r)
            usleep(delay)
            guard let a = w.frame else { return (nil, attempts) }
            if Geometry.close(a, r) { return (a, attempts) }
            // Mindestgröße: Lage sitzt, nur die Größe weicht ab, und das zweimal gleich.
            // NICHT bei abweichender Lage: Das ist Edges kurze Positionssperre nach dem
            // Größeziehen, dort liefert die App ebenfalls zweimal denselben Wert, nimmt
            // die Position aber kurz danach an.
            let originOK = abs(a.minX - r.minX) <= 2 && abs(a.minY - r.minY) <= 2
            if originOK, let p = previous, Geometry.close(p, a) { return (a, attempts) }
            previous = a
        }
        return (previous, attempts)
    }
}
