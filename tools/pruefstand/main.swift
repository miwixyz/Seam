// Prüfstand (06.11.2026): Seams echter DeskPlanner + DeskExecutor gegen TextEdit-Fenster, am echten
// Mehr-Bildschirm-Setup. Eigene Kennung dev.mwlr.seam.pruefstand (eigene Bedienungshilfen-Freigabe),
// fasst nur TextEdit an, liest Michaels Seam-Einstellungen nicht.
//
// Aufruf: Pruefstand.app/Contents/MacOS/Pruefstand <Bildschirmname> <Platz> [Wiederholungen]
//   z. B. „PA34VCNV 6“: alle TextEdit-Fenster auf Platz 6 des Hauptbildschirms.
//   „lage“: nur Lage aller Bildschirme/Spaces und der TextEdit-Fenster ausgeben.
// Während des Laufs wird der TextEdit-Rahmen alle 50 ms protokolliert (zeigt z. B. das Parken).
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DeskRunResult?
    func set(_ v: DeskRunResult) { lock.lock(); value = v; lock.unlock() }
    func get() -> DeskRunResult? { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor func screenName(_ id: String) -> String {
    NSScreen.screens.first { SpaceReader.displayIdentifier(of: $0) == id }?.localizedName ?? String(id.prefix(4))
}

@MainActor func teWindows() -> [LiveWindow] {
    DeskLayouts.liveWindows().filter { $0.bundleID == "com.apple.TextEdit" }
}

@MainActor func where_(_ w: LiveWindow, _ spaces: [SpaceInfo], _ screens: DeskScreens) -> String {
    let sp = w.spaceIDs.map { id in spaces.first { $0.managedID == id }.map { "\(screenName($0.display))#\($0.number)" } ?? "?\(id)" }
    let onScreen = screens.frames.first { $0.value.contains(CGPoint(x: w.frame.midX, y: w.frame.midY)) }.map { screenName($0.key) } ?? "-"
    return "[\(sp.joined(separator: ","))] Mitte auf \(onScreen) @\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))×\(Int(w.frame.height))"
}

@MainActor func lage(_ label: String) {
    let spaces = SpaceReader.read() ?? []
    let screens = DeskLayouts.liveScreens()
    let views = spaces.filter(\.isCurrent).map { "\(screenName($0.display))=\($0.number)" }.joined(separator: " ")
    print("\(label): sichtbar \(views) | Sondertasten 0x\(String(CGEventSource.flagsState(.combinedSessionState).rawValue, radix: 16))")
    for w in teWindows() { print("   TextEdit \(where_(w, spaces, screens))") }
}

/// Messpunkt (06.11.): Kommt nach einem einzelnen künstlichen ⌃→ noch ein weiterer Tastendruck im
/// System an? Sendet ⌃→ und danach ⌃← wie Seam (Quelle hidSystemState, Flags ⌃+fn+Ziffernblock) und
/// meldet jedes Zurücksetzen von „Sekunden seit letzter Taste“ mit Zeit ab dem eigenen Senden.
@MainActor func tasteProbe(_ screens: DeskScreens) {
    let source = CGEventSource(stateID: .hidSystemState)
    if let main = screens.primary.flatMap({ screens.frames[$0] }) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: main.midX, y: main.minY + 200), mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(100_000)
    }
    for key: CGKeyCode in [124, 123] {
        let t0 = Date()
        let cHID = CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
        let cSess = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        let cFlags = CGEventSource.counterForEventType(.combinedSessionState, eventType: .flagsChanged)
        defer {
            print("   Zähler keyDown: hid +\(CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown) - cHID), Sitzung +\(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown) - cSess), flagsChanged Sitzung +\(CGEventSource.counterForEventType(.combinedSessionState, eventType: .flagsChanged) &- cFlags) (eigene 3)")
        }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            e?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            e?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        for k: CGKeyCode in [59, 62, 63] {   // ⌃ links/rechts, fn loslassen wie Seam
            let e = CGEvent(keyboardEventSource: source, virtualKey: k, keyDown: false)
            e?.type = .flagsChanged; e?.flags = []; e?.post(tap: .cghidEventTap)
        }
        var lastIdle = Double.infinity
        var resets: [String] = []
        while Date().timeIntervalSince(t0) < 1.5 {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            if idle < lastIdle - 0.004 {
                resets.append(String(format: "%.3f", Date().timeIntervalSince(t0) - idle))
            }
            lastIdle = idle
            usleep(5_000)
        }
        print("Taste \(key == 124 ? "⌃→" : "⌃←"): Tastendruck-Zeitpunkte ab eigenem Senden [s]: \(resets.joined(separator: ", ")) | Sondertasten danach 0x\(String(CGEventSource.flagsState(.combinedSessionState).rawValue, radix: 16))")
        usleep(500_000)
    }
}

@MainActor func main() -> Int32 {
    let args = CommandLine.arguments
    if !AXAccess.isTrusted {
        // Trägt den Prüfstand in die Liste ein und zeigt die Systemabfrage; bis 90 s auf die Freigabe warten.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let until = Date().addingTimeInterval(90)
        while !AXAccess.isTrusted && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
    }
    guard AXAccess.isTrusted else { print("✗ Keine Bedienungshilfen-Freigabe für den Prüfstand"); return 3 }
    let screens = DeskLayouts.liveScreens()
    print("Bildschirme: " + screens.frames.map { "\(screenName($0.key)) \(Int($0.value.minX)),\(Int($0.value.minY)) \(Int($0.value.width))×\(Int($0.value.height))" }.sorted().joined(separator: " · ")
          + " | Haupt \(screens.primary.map(screenName) ?? "?")")
    if args.count >= 2, args[1] == "lage" { lage("Lage"); return 0 }
    if args.count >= 2, args[1] == "taste" { tasteProbe(screens); return 0 }
    guard args.count >= 3, let number = Int(args[2]),
          let display = screens.frames.keys.first(where: { screenName($0) == args[1] }) else {
        print("Aufruf: Pruefstand lage | <Bildschirmname> <Platz> [Wiederholungen]"); return 2
    }
    let repeats = args.count >= 4 ? Int(args[3]) ?? 1 : 1
    let frame = CGRect(x: 300, y: 120, width: 900, height: 700)
    let layout = DeskLayout(entries: [DeskLayoutEntry(bundleID: "com.apple.TextEdit",
                                                      desk: DeskRef(name: nil, display: display, number: number),
                                                      frames: [DeskFrame(frame)])])
    var failures = 0
    for run in 1...repeats {
        let spaces = SpaceReader.read() ?? []
        let windows = DeskLayouts.liveWindows()
        let plan = DeskPlanner.plan(layout: layout, spaces: spaces, names: [:], windows: windows, screens: screens)
        print("— Lauf \(run): \(plan.moves.count) Züge (\(plan.moves.filter(\.changesSpace).count) mit Space-Wechsel), Probleme \(plan.issues.count), ausgelassen \(plan.skipped.map { "\($0.reason)" })")
        lage("vorher")
        let box = ResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(DeskExecutor.execute(plan, windows: windows, screens: screens))
        }
        var last = ""
        let t0 = Date()
        while box.get() == nil {
            let spaces = SpaceReader.read() ?? []
            let cur = CGEvent(source: nil)?.location ?? .zero
            let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            let views = spaces.filter(\.isCurrent).map { "\(screenName($0.display))=\($0.number)" }.joined(separator: " ")
            let now = "Zeiger \(Int(cur.x)),\(Int(cur.y))\(keyIdle < 0.06 ? " TASTE" : "") | \(views) | "
                + teWindows().filter { $0.spaceIDs.count == 1 }.map { where_($0, spaces, screens) }.joined(separator: " | ")
            if now != last { print(String(format: "   %5.2f s  %@", Date().timeIntervalSince(t0), now)); last = now }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let r = box.get()!
        print("Ergebnis: \(r.moved) verschoben, \(r.framed) Rahmen, ausgelassen \(r.skipped.map { "\($0.reason)" }), Abbruch \(r.aborted.map { "\($0)" } ?? "nein"), \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        lage("nachher")
        let after = SpaceReader.read() ?? []
        let target = after.first { $0.display == display && $0.number == number }
        // Nur echte Fenster (genau ein Space); TextEdit hat ein unsichtbares Hilfsfenster ohne Space.
        let real = teWindows().filter { $0.spaceIDs.count == 1 }
        let wanted = frame.offsetBy(dx: screens.frames[display]!.minX, dy: screens.frames[display]!.minY)
        let ok = !real.isEmpty && real.allSatisfy { $0.spaceIDs == [target?.managedID ?? -1] }
            && real.contains { DeskPlanner.fits($0.frame, wanted) }
            && real.allSatisfy { w in screens.frames[display]!.contains(CGPoint(x: w.frame.midX, y: w.frame.midY)) }
        print(ok ? "✓ alle TextEdit-Fenster am Ziel" : "✗ NICHT alle TextEdit-Fenster am Ziel")
        if !ok { failures += 1 }
        if r.aborted != nil { break }
    }
    return failures == 0 ? 0 : 1
}

exit(MainActor.assumeIsolated { main() })
