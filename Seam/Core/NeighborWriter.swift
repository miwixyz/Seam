import Foundation

/// Stellt Nachbarfenster auf einer eigenen Warteschlange nach, nicht auf dem
/// Hauptthread.
///
/// Gemessen 2026-10-08 (Edge ↔ Outlook): Ein Setzen bei Outlook dauerte bis 56 ms,
/// weil die Bedienungshilfen synchron auf die andere App warten. Auf dem Hauptthread
/// blockierte das Seam.
///
/// **Eine Aufgabe, neueste gewinnt:** Es gibt immer nur eine wartende Nachstell-Aufgabe.
/// Eine neue ersetzt die alte. So geht nie der letzte Stand verloren, und eine langsame
/// App wird nicht mit Zwischenständen überhäuft.
///
/// **Höchstens 40 Nachstellungen pro Sekunde:** In der Bildschirmaufnahme vom 08.10.
/// kam Edge bei ~100 Nachstellungen pro Sekunde mit dem Zeichnen nicht nach; für knapp
/// eine Sekunde war statt Edge das Fenster dahinter zu sehen.
final class NeighborWriter: @unchecked Sendable {

    private let queue = DispatchQueue(label: "dev.mwlr.seam.nachstellen", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (@Sendable () -> Int)?
    private var draining = false
    private var lastRun: CFAbsoluteTime = 0
    static let minInterval: CFAbsoluteTime = 0.025

    // Messwerte der laufenden Geste
    private var jobs = 0
    private var writes = 0
    private var total: CFAbsoluteTime = 0
    private var maximum: CFAbsoluteTime = 0
    private var readTotal: CFAbsoluteTime = 0
    private var setTotal: CFAbsoluteTime = 0

    /// Aufteilung eines Laufs: Kante der gezogenen App lesen / Nachbarn setzen.
    func note(read: CFAbsoluteTime, set: CFAbsoluteTime) {
        lock.lock(); readTotal += read; setTotal += set; lock.unlock()
    }

    /// Reicht eine Nachstell-Aufgabe ein; sie gibt die Zahl gesetzter Fenster zurück.
    func track(_ job: @escaping @Sendable () -> Int) {
        lock.lock()
        pending = job
        let start = !draining
        draining = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = pending else { draining = false; lock.unlock(); return }
            pending = nil
            let wait = lastRun + Self.minInterval - CFAbsoluteTimeGetCurrent()
            lock.unlock()
            if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
            // Nach dem Warten könnte eine neuere Aufgabe da sein: dann die nehmen.
            lock.lock()
            let latest = pending ?? job
            pending = nil
            lock.unlock()
            let t0 = CFAbsoluteTimeGetCurrent()
            // Takt ab BEGINN des Laufs: Ab dem Ende gemessen wurden es effektiv nur ~25
            // statt 40 Läufe pro Sekunde (Lauf 14 ms + 25 ms Pause, gemessen 08.10.).
            lock.lock(); lastRun = t0; lock.unlock()
            let n = latest()
            let dt = CFAbsoluteTimeGetCurrent() - t0
            lock.lock()
            jobs += 1; writes += n; total += dt; maximum = max(maximum, dt)
            lock.unlock()
        }
    }

    /// Verwirft Wartendes und wartet, bis die laufende Aufgabe fertig ist. Vor dem
    /// Abschluss einer Geste aufrufen, sonst überholt ein später Zwischenstand das Ende.
    func flush() {
        lock.lock(); pending = nil; lock.unlock()
        queue.sync {}
    }

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

    static func setVerified(_ w: AXWindow, _ r: CGRect) -> CGRect? {
        var previous: CGRect?
        for delay in retryDelays {
            w.setFrame(r)
            usleep(delay)
            guard let a = w.frame else { return nil }
            if close(a, r) { return a }
            // Mindestgröße: Lage sitzt, nur die Größe weicht ab, und das zweimal gleich.
            // NICHT bei abweichender Lage: Das ist Edges kurze Positionssperre nach dem
            // Größeziehen, dort liefert die App ebenfalls zweimal denselben Wert, nimmt
            // die Position aber kurz danach an.
            let originOK = abs(a.minX - r.minX) <= 2 && abs(a.minY - r.minY) <= 2
            if originOK, let p = previous, close(p, a) { return a }
            previous = a
        }
        return previous
    }

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    struct Stats { let jobs: Int, writes: Int, avgMs: Int, maxMs: Int, readAvgMs: Int, setAvgMs: Int }

    /// Messwerte abholen und zurücksetzen (Ø/max je Nachstell-Aufgabe).
    func takeStats() -> Stats {
        lock.lock(); defer { jobs = 0; writes = 0; total = 0; maximum = 0; readTotal = 0; setTotal = 0; lock.unlock() }
        func avg(_ t: CFAbsoluteTime) -> Int { jobs > 0 ? Int(t / Double(jobs) * 1000) : 0 }
        return Stats(jobs: jobs, writes: writes, avgMs: avg(total), maxMs: Int(maximum * 1000),
                     readAvgMs: avg(readTotal), setAvgMs: avg(setTotal))
    }
}
