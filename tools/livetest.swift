// livetest — Werkzeug für den Test am echten System. NICHT Teil der App.
//
// Erzeugt echte Maus- und Tastaturereignisse (das tut Seam selbst nie, E2) und
// misst Fensterrahmen über die Bedienungshilfen. Der aufrufende Prozess braucht
// die Bedienungshilfen-Freigabe.
//
//   livetest frames <pid> <titel>...            Rahmen ausgeben
//   livetest set <pid> <titel> x y w h          Rahmen setzen
//   livetest focus <pid> <titel>                Fenster nach vorn
//   livetest drag x1 y1 x2 y2 [schritte]        Ziehen mit gedrückter Maustaste
//   livetest key <keycode> <ctrl|opt|cmd>...    Tastenkürzel drücken
//   livetest sample <pidL> <titelL> <pidR> <titelR> <sek>   Spalt alle 10 ms messen (AX, nacheinander)
//   livetest samplecg <pidL> <pidR> <y> <h> <sek>   Spalt aus EINEM Fensterserver-Abzug
//     (beide Fenster gleichzeitig: Der AX-Messer liest nacheinander und täuscht beim
//      Schmalerziehen Lücken, beim Breiterziehen Überlappungen vor, 08.10.)
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)
let a = CommandLine.arguments

func windows(_ pid: pid_t) -> [AXUIElement] {
    var w: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &w)
    return (w as? [AXUIElement]) ?? []
}
func title(_ w: AXUIElement) -> String {
    var t: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t); return (t as? String) ?? ""
}
func frame(_ w: AXUIElement) -> CGRect {
    var p: CFTypeRef?, s: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p)
    AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s)
    var pt = CGPoint.zero, sz = CGSize.zero
    if let p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
    if let s { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
    return CGRect(origin: pt, size: sz)
}
func find(_ pid: pid_t, _ t: String) -> AXUIElement {
    guard let w = windows(pid).first(where: { title($0) == t || title($0).hasPrefix(t) }) else {
        print("❌ Fenster '\(t)' fehlt, vorhanden: \(windows(pid).map(title))"); exit(1)
    }
    return w
}
func fmt(_ r: CGRect) -> String { "x \(Int(r.minX)) y \(Int(r.minY)) b \(Int(r.width)) h \(Int(r.height)) | rechts \(Int(r.maxX)) unten \(Int(r.maxY))" }

let src = CGEventSource(stateID: .hidSystemState)
func mouse(_ type: CGEventType, _ x: CGFloat, _ y: CGFloat) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

switch a.count > 1 ? a[1] : "" {
case "frames":
    let pid = pid_t(a[2])!
    for t in a.dropFirst(3) { print("\(t): \(fmt(frame(find(pid, t))))") }
case "set":
    let pid = pid_t(a[2])!, w = find(pid, a[3])
    var pt = CGPoint(x: Double(a[4])!, y: Double(a[5])!), sz = CGSize(width: Double(a[6])!, height: Double(a[7])!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &sz)!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pt)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &sz)!)
    print("gesetzt: \(fmt(frame(w)))")
case "focus":
    let pid = pid_t(a[2])!, w = find(pid, a[3])
    NSRunningApplication(processIdentifier: pid)?.activate()
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    usleep(300_000)
case "drag":
    // Sperre (2026-10-08): Ein Ziehen landete in Michaels Obsidian, weil die
    // Testfenster nicht mehr dort lagen. Gezogen wird nur, wenn das ERWARTETE
    // Testfenster (pid + Titel) am Startpunkt liegt (±10 px für den Kantengriff)
    // und davor kein anderes Fenster den Punkt verdeckt.
    //   livetest drag x1 y1 x2 y2 schritte <pid> <titel>
    guard a.count > 8, let pid = pid_t(a[7]) else { print("❌ drag braucht <pid> <titel> des Testfensters"); exit(1) }
    let (x1, y1, x2, y2) = (Double(a[2])!, Double(a[3])!, Double(a[4])!, Double(a[5])!)
    let steps = Int(a[6])!
    let target = frame(find(pid, a[8]))
    guard target.insetBy(dx: -10, dy: -10).contains(CGPoint(x: x1, y: y1)) else {
        print("❌ Startpunkt liegt nicht am Testfenster '\(a[8])' (\(fmt(target))) — abgebrochen"); exit(1)
    }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
        guard let b = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
              r.contains(CGPoint(x: x1, y: y1)) else { continue }
        let owner = info[kCGWindowOwnerPID as String] as? pid_t
        if owner == pid { break }                       // vorderstes Fenster am Punkt ist TextEdit: gut
        if r.width >= 3000 && r.height >= 1400 { continue }   // Vollbild-Abdunkler (HazeOver) ignorieren
        print("❌ Am Startpunkt liegt vorne ein fremdes Fenster (\(info[kCGWindowOwnerName as String] ?? "?")) — abgebrochen"); exit(1)
    }
    mouse(.mouseMoved, x1, y1); usleep(250_000)
    mouse(.leftMouseDown, x1, y1); usleep(150_000)
    for i in 1...steps {
        let f = Double(i) / Double(steps)
        mouse(.leftMouseDragged, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f)
        usleep(16_000)
    }
    usleep(250_000)
    mouse(.leftMouseUp, x2, y2)
    usleep(400_000)
    print("gezogen \(Int(x1)),\(Int(y1)) → \(Int(x2)),\(Int(y2)) in \(steps) Schritten")
case "key":
    let code = CGKeyCode(a[2])!
    var flags: CGEventFlags = []
    for m in a.dropFirst(3) {
        switch m { case "ctrl": flags.insert(.maskControl); case "opt": flags.insert(.maskAlternate)
        case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift); default: break }
    }
    // Echte Pfeil-/Navigationstasten tragen Fn und Ziffernblock im Ereignis. Ohne
    // diese Merkmale erkannte macOS ⌃⌥← nicht als Seams Kürzel (gemessen 08.10.).
    if [123, 124, 125, 126, 115, 119, 116, 121].contains(code) {
        flags.insert(.maskSecondaryFn)
        if code <= 126 { flags.insert(.maskNumericPad) }
    }
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!
    down.flags = flags; down.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!
    up.flags = flags; up.post(tap: .cghidEventTap)
    // Zusatztasten ausdrücklich loslassen. Sonst hält macOS ⌃/⌥/⇧ für gedrückt, und ein
    // folgendes Ziehen wird zum ⌃-Klick (Rechtsklick) statt zum Größeziehen (08.10.).
    if let clear = CGEvent(source: src) {
        clear.type = .flagsChanged
        clear.flags = []
        clear.post(tap: .cghidEventTap)
    }
    usleep(400_000)
    print("Taste \(code) mit \(a.dropFirst(3).joined(separator: "+"))")
case "sample":
    // Spalt zwischen rechter Kante links und linker Kante rechts, alle 10 ms.
    let l = find(pid_t(a[2])!, a[3]), r = find(pid_t(a[4])!, a[5])
    let end = CFAbsoluteTimeGetCurrent() + Double(a[6])!
    var gaps: [Int] = []
    while CFAbsoluteTimeGetCurrent() < end {
        gaps.append(Int(frame(r).minX - frame(l).maxX))
        usleep(10_000)
    }
    let moving = gaps.enumerated().filter { $0.offset > 0 && gaps[$0.offset - 1] != $0.element }.count
    let s = gaps.sorted()
    print("Stichproben \(gaps.count), Spalt min \(s.first ?? 0) / Median \(s[s.count / 2]) / max \(s.last ?? 0) px, Anteil ≠ 5 px: \(gaps.filter { $0 != 5 }.count * 100 / max(gaps.count, 1)) %, Wechsel \(moving)")
case "samplecg":
    let pl = pid_t(a[2])!, pr = pid_t(a[3])!, y = Double(a[4])!, h = Double(a[5])!
    let end = CFAbsoluteTimeGetCurrent() + Double(a[6])!
    var gaps: [Int] = []
    while CFAbsoluteTimeGetCurrent() < end {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        func bounds(_ pid: pid_t) -> CGRect? {
            for i in list where (i[kCGWindowOwnerPID as String] as? pid_t) == pid && (i[kCGWindowLayer as String] as? Int) == 0 {
                if let b = i[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                   abs(r.minY - y) <= 6, abs(r.height - h) <= 12 { return r }
            }
            return nil
        }
        if let l = bounds(pl), let r = bounds(pr) { gaps.append(Int(r.minX - l.maxX)) }
        usleep(10_000)
    }
    let s = gaps.sorted()
    guard !s.isEmpty else { print("keine Stichproben"); exit(1) }
    print("Fensterserver: Stichproben \(gaps.count), Spalt min \(s.first!) / Median \(s[s.count / 2]) / max \(s.last!) px, Lücke > 5 px: \(gaps.filter { $0 > 5 }.count * 100 / gaps.count) %")
default:
    print("Aufruf siehe Kopfkommentar"); exit(1)
}
