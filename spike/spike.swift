// Machbarkeits-Prototyp „Fenster mitziehen" (2026-10-08).
//
// Frage: Läuft das Nachbarfenster WÄHREND des Ziehens mit, oder meldet macOS
// die Größenänderung erst am Ende? Wie groß ist der Versatz?
//
// Ablauf: Zwei TextEdit-Fenster (vom Aufrufer angelegt) stehen nebeneinander.
// Der Prototyp beobachtet das linke Fenster (kAXResizedNotification), stellt bei
// jeder Meldung das rechte Fenster nach und simuliert selbst ein Mausziehen an
// der gemeinsamen Kante: nach links, dann zurück nach rechts.
//
// Aufruf: spike <pid>     Ausgabe: Messwerte, keine Dateien.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)
// Aufruf: spike <pid links> <Titelteil links> <pid rechts> <Titelteil rechts>
// Zwei verschiedene Apps möglich (z. B. Chrome links, TextEdit rechts).
let args = CommandLine.arguments
guard args.count > 4, let pid = pid_t(args[1]), let pidRight = pid_t(args[3]) else {
    print("Aufruf: spike <pid links> <Titel links> <pid rechts> <Titel rechts>"); exit(1)
}
let leftTitle = args[2], rightTitle = args[4]
guard AXIsProcessTrusted() else { print("❌ keine Bedienungshilfen-Freigabe"); exit(1) }

let app = AXUIElementCreateApplication(pid)

func frame(_ w: AXUIElement) -> CGRect {
    var p: CFTypeRef?, s: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p)
    AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s)
    var pt = CGPoint.zero, sz = CGSize.zero
    if let p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
    if let s { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
    return CGRect(origin: pt, size: sz)
}

func setFrame(_ w: AXUIElement, _ r: CGRect) {
    var pt = r.origin, sz = r.size
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pt)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &sz)!)
}

func windows(_ p: pid_t) -> [AXUIElement] {
    var w: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(p), kAXWindowsAttribute as CFString, &w)
    return (w as? [AXUIElement]) ?? []
}
// Fenster über den Titel wählen, nicht über die Lage: Beim ersten Lauf hatte
// TextEdit ein drittes Fenster geöffnet, das als „rechts" erkannt wurde.
func title(_ w: AXUIElement) -> String {
    var t: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t); return (t as? String) ?? ""
}
guard let foundLeft = windows(pid).first(where: { title($0).contains(leftTitle) }),
      let foundRight = windows(pidRight).first(where: { title($0).contains(rightTitle) }) else {
    print("❌ Fenster nicht gefunden: links \(windows(pid).map(title)) rechts \(windows(pidRight).map(title))"); exit(1)
}
// Global statt aus dem guard: Der C-Rückruf des Observers darf keinen Kontext einfangen.
nonisolated(unsafe) let left: AXUIElement = foundLeft
nonisolated(unsafe) let right: AXUIElement = foundRight
setFrame(left, CGRect(x: 200, y: 150, width: 800, height: 700))
setFrame(right, CGRect(x: 1000, y: 150, width: 800, height: 700))
AXUIElementPerformAction(right, kAXRaiseAction as CFString)
AXUIElementPerformAction(left, kAXRaiseAction as CFString)
NSRunningApplication(processIdentifier: pid)?.activate()
usleep(600_000)
let rightEdgeOfRight = frame(right).maxX           // bleibt fest
print("Start  links \(frame(left))  rechts \(frame(right))")

let t0 = CFAbsoluteTimeGetCurrent()
var events: [(t: Double, aRight: CGFloat)] = []
var gaps: [CGFloat] = []

let callback: AXObserverCallback = { _, element, _, _ in
    let a = frame(element)
    events.append((CFAbsoluteTimeGetCurrent() - t0, a.maxX))
    // Nachbarfenster nachstellen: beginnt an der neuen Kante, rechter Rand bleibt.
    setFrame(right, CGRect(x: a.maxX, y: frame(right).minY,
                           width: rightEdgeOfRight - a.maxX, height: frame(right).height))
}

var observer: AXObserver?
guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { print("❌ Observer"); exit(1) }
AXObserverAddNotification(observer, left, kAXResizedNotification as CFString, nil)
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

// Simuliertes Ziehen auf einem Hintergrund-Thread, während der Main-RunLoop die
// Meldungen ausliefert. Abtastung des Versatzes alle 16 ms.
let start = frame(left)
let edgeX = start.maxX - 1, y = start.midY
var dragEnd = 0.0, dragStart = 0.0
DispatchQueue.global().async {
    let src = CGEventSource(stateID: .hidSystemState)
    func post(_ type: CGEventType, _ x: CGFloat) {
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, edgeX); usleep(300_000)
    post(.leftMouseDown, edgeX); usleep(120_000)
    dragStart = CFAbsoluteTimeGetCurrent() - t0
    var x = edgeX
    let path: [CGFloat] = Array(repeating: -10, count: 30) + Array(repeating: 10, count: 15)  // 300 px links, 150 zurück
    for dx in path {
        x += dx
        post(.leftMouseDragged, x)
        usleep(16_000)
        DispatchQueue.main.sync { gaps.append(frame(right).minX - frame(left).maxX) }
    }
    usleep(150_000)
    post(.leftMouseUp, x)
    dragEnd = CFAbsoluteTimeGetCurrent() - t0
    usleep(600_000)
    DispatchQueue.main.async {
        let during = events.filter { $0.t >= dragStart && $0.t <= dragEnd }.count
        let a = frame(left), b = frame(right)
        print("Ende   links \(a)  rechts \(b)")
        print("Meldungen gesamt \(events.count), davon während des Ziehens \(during), Ziehdauer \(String(format: "%.2f", dragEnd - dragStart)) s")
        let absGaps = gaps.map { abs($0) }
        print("Versatz während des Ziehens (px): max \(absGaps.max() ?? -1), Median \(absGaps.sorted()[absGaps.count / 2]), Stichproben \(absGaps.count)")
        print("Endzustand: Lücke zwischen den Fenstern \(b.minX - a.maxX) px, rechter Rand rechts \(b.maxX) (soll \(rightEdgeOfRight))")
        print("Erwartete linke Breite ~ \(start.width - 150), gemessen \(a.width)")
        exit(0)
    }
}
CFRunLoopRun()
