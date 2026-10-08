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

    struct Stats { let count: Int, avgMs: Int, maxMs: Int }

    /// Messwerte abholen und zurücksetzen.
    func takeStats() -> Stats {
        lock.lock(); defer { writes = 0; total = 0; maximum = 0; lock.unlock() }
        return Stats(count: writes, avgMs: writes > 0 ? Int(total / Double(writes) * 1000) : 0, maxMs: Int(maximum * 1000))
    }
}
