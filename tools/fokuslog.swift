// fokuslog — Messwerkzeug für den Sichttest, NICHT Teil von Seam.
//
// Schreibt alle 20 ms die vordere App, ob sie ein Fokusfenster hat (Bedienungshilfen) und die
// obersten Fenster der Ebenen < 20 (ab 20 × 20 pt, mit Deckkraft) — nur bei Änderung. Damit lässt
// sich prüfen, ob Seams Abdunklung jederzeit direkt unter dem richtigen Fenster liegt
// (Seam-Abdunkel-Fenster erscheinen als „SEAM“). 16.10.2026: fand die Linkanzeige von Helium
// (212 × 43 pt, Deckkraft 0) als Ziel der Abdunklung → Blitzen, behoben in 0.6.1.
//
// Liest aus der Fensterliste nur Nummer, Prozess, Ebene, Lage, Deckkraft — keine Titel.
// Braucht die Bedienungshilfen-Freigabe des aufrufenden Programms (Terminal/Obsidian).
//
// Bauen + starten:
//   swiftc -O tools/fokuslog.swift -o /tmp/fokuslog
//   nohup /tmp/fokuslog 600 $(pgrep -x Seam) > /tmp/fokus.log 2>&1 < /dev/null &
// Beenden per Prozessnummer, nicht per `pkill -f` (trifft sonst die eigene Shell).
import AppKit

let secs = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "60") ?? 60
let seam = pid_t(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "0") ?? 0
print("AX vertraut: \(AXIsProcessTrusted())")

func name(_ p: pid_t) -> String {
    p == seam ? "SEAM" : (NSRunningApplication(processIdentifier: p)?.localizedName ?? "pid\(p)")
}

var last = ""
let start = Date()
let fmt = DateFormatter()
fmt.dateFormat = "HH:mm:ss.SSS"
while Date().timeIntervalSince(start) < secs {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    let app = AXUIElementCreateApplication(front)
    AXUIElementSetMessagingTimeout(app, 0.1)
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
    var fokus = "KEIN(\(err.rawValue))"
    if err == .success, let w = value, CFGetTypeID(w) == AXUIElementGetTypeID() {
        var sub: CFTypeRef?
        // swiftlint:disable:next force_cast
        AXUIElementCopyAttributeValue(w as! AXUIElement, kAXSubroleAttribute as CFString, &sub)
        fokus = (sub as? String) ?? "?"
    }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let top = list.compactMap { i -> String? in
        let layer = i[kCGWindowLayer as String] as? Int ?? 0
        guard layer < 20, let n = i[kCGWindowNumber as String] as? Int,
              let p = i[kCGWindowOwnerPID as String] as? pid_t,
              let bd = i[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: bd), b.width > 20, b.height > 20 else { return nil }
        let a = (i[kCGWindowAlpha as String] as? Double) ?? 1
        let alpha = a < 1 ? String(format: " a%.2f", a) : ""
        return "\(name(p))#\(n)[L\(layer) \(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height))\(alpha)]"
    }.prefix(8).joined(separator: "  ")
    let line = "vorn=\(name(front)) fokus=\(fokus) | \(top)"
    if line != last {
        print("\(fmt.string(from: Date())) \(line)")
        fflush(stdout)
        last = line
    }
    // Ereignisschleife laufen lassen — sonst bleibt frontmostApplication stehen (Messfehler 16.10.).
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
