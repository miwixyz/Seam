// fensterlog — Werkzeug für die Fehlersuche am echten System. NICHT Teil der App.
//
// Schreibt alle 30 ms die Lage der Fenster der genannten Apps mit, dazu Maustaste,
// Zusatztasten und Seams eigene Schilder/Overlays (Fenster von Seam außerhalb von Ebene 0).
// Nur Zeilen, die sich ändern. Liest die Fensterliste des Systems, braucht KEINE
// Bedienungshilfen-Freigabe und sieht auch Fenster auf anderen Spaces („on:false“).
//
//   swiftc -O tools/fensterlog.swift -o /tmp/fensterlog
//   /tmp/fensterlog <sekunden> "Microsoft Edge" "Microsoft Outlook" > /tmp/fensterlog.txt &
//
// Danach daneben Seams Protokoll lesen (`/usr/bin/log`, falls die Shell `log` überschattet):
//   /usr/bin/log show --last 10m --predicate 'subsystem == "dev.mwlr.seam"' --style compact
//
// Entstanden 10.10. (Edge + Outlook auf dem MacBook): Ein Durchgang zeigte die 30 pt
// Überlappung, die Mindestbreiten und dass Seam beim Teilen zurücksetzte, in einer Minute.
import Cocoa

let args = Array(CommandLine.arguments.dropFirst())
guard let secs = args.first.flatMap(Double.init), args.count >= 2 else {
    FileHandle.standardError.write(Data("fensterlog <sekunden> <App-Name>...\n".utf8))
    exit(2)
}
let apps = Set(args.dropFirst())
let end = Date().addingTimeInterval(secs)
let fmt = DateFormatter()
fmt.dateFormat = "HH:mm:ss.SSS"
setvbuf(stdout, nil, _IOLBF, 0)
print("START", fmt.string(from: Date()), "Apps:", apps.sorted().joined(separator: ", "))

var last = ""
while Date() < end {
    let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var parts: [String] = []
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { continue }
        let on = w[kCGWindowIsOnscreen as String] as? Bool ?? false
        if owner == "Seam", layer != 0, on, wd < 1200 {
            parts.append("Seam-Schild L\(layer) x\(Int(x)) y\(Int(y)) \(Int(wd))×\(Int(ht))")
        } else if apps.contains(owner), layer == 0, wd > 200, ht > 200 {
            parts.append("\(owner) x\(Int(x))-\(Int(x + wd)) y\(Int(y))-\(Int(y + ht)) on:\(on)")
        }
    }
    let mouse = NSEvent.pressedMouseButtons & 1 == 1 ? "MAUS↓" : "maus "
    let m = NSEvent.modifierFlags
    let mods = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
        + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    let line = "\(mouse) \(mods) " + parts.sorted().joined(separator: " | ")
    if line != last {
        print(fmt.string(from: Date()), line)
        last = line
    }
    usleep(30_000)
}
print("END", fmt.string(from: Date()))
