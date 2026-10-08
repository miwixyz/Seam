import AppKit

/// Merkt sich, wie schnell App-PAARE beim Mitziehen sind (Michael, 08.10.:
/// „automatisch je App“).
///
/// **Paar statt einzelne App** (zweite Aufnahme, 08.10.): Bewertet wurde zuerst nur das
/// Setzen des Nachbarn. Die Wartezeit steckt aber im ganzen Durchgang (Kante der
/// gezogenen App lesen + Nachbar setzen): Outlook→Edge Ø 81 ms, Edge→Outlook Ø 159 ms,
/// trotzdem stufte Seam nichts als langsam ein, und Edge zeigte eine Sekunde lang den
/// Schreibtisch statt sich selbst. Je Paar, damit Edge mit Obsidian live bleibt.
///
/// Gemessen 2026-10-08: Outlook brauchte als folgendes Fenster Ø 125 ms, max 448 ms
/// je Größenänderung und kam während einer Geste auf nur 4 Bilder. Edge lag bei
/// 11–17 ms mit einem Ausreißer von 162 ms. Deshalb entscheidet der **Median** der
/// letzten fünf Messungen, ab drei Messungen, nicht ein Einzelwert.
///
/// Langsame Apps folgen nicht live: Seam zeigt eine Kontur und setzt das Fenster beim
/// Loslassen. Nur im Speicher, an die Prozess-ID gebunden (docs/SECURE-DESIGN.md E10).
final class SlowApps: @unchecked Sendable {

    static let threshold: Double = 0.060
    static let window = 5
    static let minSamples = 3

    private let lock = NSLock()
    private var samples: [String: [Double]] = [:]

    static func key(_ leading: pid_t, _ neighbor: pid_t) -> String { "\(leading)-\(neighbor)" }

    func record(_ leading: pid_t, _ neighbor: pid_t, seconds: Double) {
        let pid = Self.key(leading, neighbor)
        lock.lock(); defer { lock.unlock() }
        var s = samples[pid] ?? []
        s.append(seconds)
        if s.count > Self.window { s.removeFirst(s.count - Self.window) }
        samples[pid] = s
    }

    func isSlow(_ leading: pid_t, _ neighbor: pid_t) -> Bool {
        #if DEBUG
        if let forced = Self.forcedBundleID,
           [leading, neighbor].contains(where: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == forced }) {
            return true
        }
        #endif
        lock.lock(); defer { lock.unlock() }
        return Self.isSlow(samples[Self.key(leading, neighbor)] ?? [])
    }

    #if DEBUG
    /// Nur im Debug-Build: `open Seam.app --args -langsam com.apple.TextEdit` stuft eine
    /// App zwangsweise als langsam ein, um den Konturmodus ohne Outlook zu prüfen.
    /// Im Release-Build gibt es diesen Weg nicht.
    static let forcedBundleID: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-langsam"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    #endif

    /// Reine Regel, getestet.
    static func isSlow(_ s: [Double]) -> Bool {
        guard s.count >= minSamples else { return false }
        let sorted = s.sorted()
        return sorted[sorted.count / 2] > threshold
    }
}
