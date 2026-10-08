import Foundation

/// Stellt Nachbarfenster auf einer eigenen Warteschlange nach, nicht auf dem
/// Hauptthread.
///
/// Gemessen 2026-10-08 (Edge ↔ Outlook): Ein Setzen bei Outlook dauerte im Schnitt
/// 8 ms, in der Spitze 56 ms, weil die Bedienungshilfen synchron auf die andere App
/// warten. Auf dem Hauptthread blockierte das Seam, Meldungen des gezogenen Fensters
/// stauten sich, der Nachbar hinkte sichtbar hinterher.
///
/// **Neuester Wert gewinnt:** Je Nachbar zählt nur der zuletzt eingereichte Rahmen.
/// Ist das Setzen langsamer als die Meldungen, werden Zwischenstände übersprungen,
/// nie der letzte. Das ersetzt die frühere Bremse „höchstens alle 8 ms“, die genau
/// den letzten Wert eines Meldungsstoßes verwarf.
final class NeighborWriter: @unchecked Sendable {

    private let queue = DispatchQueue(label: "dev.mwlr.seam.nachstellen", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: [Int: (AXWindow, CGRect)] = [:]
    private var draining = false

    // Messwerte der laufenden Geste
    private var writes = 0
    private var total: CFAbsoluteTime = 0
    private var maximum: CFAbsoluteTime = 0

    func submit(_ items: [Int: (AXWindow, CGRect)]) {
        lock.lock()
        pending.merge(items) { _, new in new }
        let start = !draining
        draining = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            let batch = pending
            pending = [:]
            if batch.isEmpty { draining = false; lock.unlock(); return }
            lock.unlock()
            for (window, rect) in batch.values {
                let t0 = CFAbsoluteTimeGetCurrent()
                window.setFrameLive(rect)
                let dt = CFAbsoluteTimeGetCurrent() - t0
                lock.lock(); writes += 1; total += dt; maximum = max(maximum, dt); lock.unlock()
            }
        }
    }

    /// Wartet, bis alle eingereichten Rahmen gesetzt sind. Vor dem abschließenden
    /// Setzen mit Zurücklesen aufrufen, sonst überholt ein später Zwischenstand das Ende.
    func flush() {
        lock.lock(); pending = [:]; lock.unlock()
        queue.sync {}
    }

    // MARK: - Setzen mit Nachprüfung

    /// Setzt einen Rahmen und prüft nach, bis er sitzt (höchstens `attempts` Mal).
    ///
    /// Gemessen 2026-10-08 an Edge und Outlook: Ein einmaliges Setzen landete bei
    /// ⌃⌥→ auf x 2449 / Breite 991 oder x 880 statt x 1723 / 1712; erst ein zweiter
    /// Tastendruck saß. Vermutlich ziehen die Apps ihre eigene Größenänderung nach.
    /// Läuft auf der Warteschlange: Seam bleibt währenddessen bedienbar.
    /// - Returns: der zuletzt gelesene Ist-Rahmen.
    static func setVerified(_ w: AXWindow, _ r: CGRect, attempts: Int = 4) -> CGRect? {
        var actual: CGRect?
        for i in 0..<attempts {
            actual = w.setFrame(r)
            usleep(50_000)
            actual = w.frame
            guard let a = actual else { return nil }
            if close(a, r) { return a }
            if i == attempts - 1 { break }
        }
        return actual
    }

    /// Mehrere Schritte nacheinander auf der Warteschlange (nach allen Zwischenständen).
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    struct Stats { let count: Int, avgMs: Int, maxMs: Int }

    /// Messwerte abholen und zurücksetzen.
    func takeStats() -> Stats {
        lock.lock(); defer { writes = 0; total = 0; maximum = 0; lock.unlock() }
        return Stats(count: writes, avgMs: writes > 0 ? Int(total / Double(writes) * 1000) : 0, maxMs: Int(maximum * 1000))
    }
}
