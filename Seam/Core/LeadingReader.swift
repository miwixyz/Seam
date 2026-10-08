import Foundation

/// Liest während einer Größen-Geste laufend den Rahmen des gezogenen Fensters, auf
/// einem eigenen Faden.
///
/// Gemessen 2026-10-08: Outlook brauchte als gezogenes Fenster 43–99 ms, bis es seinen
/// Rahmen verriet (Edge zu setzen dagegen 1–2 ms). Las das Nachstellen selbst, wartete
/// jedes Setzen auf Outlook. Jetzt liest dieser Faden so schnell, wie die App antwortet,
/// und das Nachstellen nimmt den zuletzt gelesenen Wert, ohne zu warten.
final class LeadingReader: @unchecked Sendable {

    private let queue = DispatchQueue(label: "dev.mwlr.seam.lesen", qos: .userInteractive)
    private let lock = NSLock()
    private var latest: CGRect?
    private var running = false
    private var generation = 0

    func start(_ w: AXWindow, initial: CGRect) {
        lock.lock()
        generation += 1
        let gen = generation
        latest = initial
        running = true
        lock.unlock()
        queue.async { [self] in
            while true {
                lock.lock(); let go = running && generation == gen; lock.unlock()
                guard go else { return }
                if let f = w.frame {
                    lock.lock(); if generation == gen { latest = f }; lock.unlock()
                }
                usleep(4_000)   // schnelle Apps nicht mit Abfragen überschütten
            }
        }
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }

    var last: CGRect? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}
