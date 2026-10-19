import AppKit
import ApplicationServices
import CoreGraphics

/// **Einzige Stelle, an der Seam Eingaben erzeugt** (docs/SECURE-DESIGN.md E17a, Michaels
/// Zustimmung 19.10.). Zweck: ein fremdes Fenster an der Titelleiste greifen und mit ⌃←/⌃→ auf
/// einen anderen Space tragen — der einzige gemessene Weg ohne abgeschalteten Systemschutz.
///
/// Die Lint-Regel `keine_synthetischen_ereignisse` gilt für alle anderen Dateien weiter. Jedes
/// Ereignis geht durch `Session.emit(_:)` — nur die Arten aus `Kind` (Positivliste), nur die
/// Tasten aus `arrowLeft`/`arrowRight`/`releasedKeys`.
/// Pflichten (alle gemessen 19.10.):
/// 1. Sondertasten nach jedem Kürzel ausdrücklich lösen und nachprüfen — sonst hängt ⌃ und jeder
///    weitere Klick ist ein Rechtsklick (traf Michaels echte Eingaben).
/// 2. Nur auf ein Element des Zielfensters klicken, das nichts auslöst (kein Knopf, Tab, Feld),
///    unmittelbar vor dem Drücken noch einmal geprüft.
/// 3. Die App nicht aktivieren (macOS springt sonst zu ihren Fenstern auf anderen Spaces).
/// 4. Nach dem Ziehen (12 pt) nachprüfen, ob das Fenster mitkam; sonst loslassen, keine Taste.
/// 5. Frist: jeder Einzelschritt prüft sie (code-audit 19.10.: vorher nur zwischen Fenstern).
///
/// Blockiert bis zu ~1 s je Schritt: nur von einer eigenen Warteschlange aufrufen, nie vom Hauptthread.
enum InputSynth {

    /// Positivliste der erzeugten Ereignisse (E17a). `InputSynthTests` hält sie fest.
    enum Kind: String, CaseIterable, Sendable {
        case mouseMove, leftMouseDown, leftMouseDragged, leftMouseUp, arrowWithControl, releaseModifier
    }

    /// ← und → — die einzigen Tasten, die Seam drückt.
    static let arrowLeft: CGKeyCode = 123
    static let arrowRight: CGKeyCode = 124
    /// Nach jedem Kürzel ausdrücklich gelöst: ⌃ links, ⌃ rechts, fn.
    static let releasedKeys: [CGKeyCode] = [59, 62, 63]
    static let maxSteps = 16

    enum Outcome: Equatable, Sendable {
        case moved
        /// Keine sichere Stelle zum Greifen gefunden — Fenster ausgelassen.
        case noGripPoint
        /// Ziehen bewegte das Fenster nicht — losgelassen, keine Taste gesendet.
        case notGrabbed
        /// Der Nutzer hat Maus oder Tastatur benutzt — abgebrochen.
        case interrupted
        /// Eine Sondertaste hing auch nach erneutem Lösen.
        case modifiersStuck
        /// Frist des Laufs abgelaufen.
        case timeUp
        case invalidSteps
    }

    // MARK: Regeln (rein, getestet)

    /// Rollen, auf die Seam nie klickt (E17a-2c).
    static let forbiddenRoles: Set<String> = [
        "AXButton", "AXLink", "AXTab", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton",
        "AXSlider", "AXTextField", "AXTextArea", "AXComboBox", "AXIncrementor", "AXDisclosureTriangle",
        "AXMenuItem", "AXMenuBarItem", "AXSearchField",
    ]
    /// Aktionen, die nichts auslösen. Alles andere (z. B. `AXPress`) heißt: nicht anklicken.
    static let harmlessActions: Set<String> = ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI",
                                               "AXShowAlternateUI", "AXRaise"]

    /// Darf an diesem Element gegriffen werden? (E17a-2)
    static func isSafeGrip(role: String?, actions: [String], belongsToTarget: Bool) -> Bool {
        guard belongsToTarget, let role, !forbiddenRoles.contains(role) else { return false }
        return actions.allSatisfy(harmlessActions.contains)
    }

    /// Kandidaten im oberen Band (4–36 pt) des Fensters, von der Mitte nach außen,
    /// mit Abstand zu den Rändern (Ampelknöpfe links, Fensterknöpfe rechts).
    static func gripCandidates(in frame: CGRect) -> [CGPoint] {
        let left = frame.minX + 90, right = frame.maxX - 90
        guard right > left else { return [] }
        var xs: [CGFloat] = [frame.midX]
        var d: CGFloat = 48
        while frame.midX - d >= left || frame.midX + d <= right {
            if frame.midX - d >= left { xs.append(frame.midX - d) }
            if frame.midX + d <= right { xs.append(frame.midX + d) }
            d += 48
        }
        let rows: [CGFloat] = [12, 8, 20, 4, 28, 36].filter { $0 < frame.height / 2 }
        return rows.flatMap { dy in xs.map { CGPoint(x: $0, y: frame.minY + dy) } }.prefix(160).map { $0 }
    }

    static func validSteps(_ steps: Int) -> Bool { steps != 0 && abs(steps) <= maxSteps }

    /// Hat der Nutzer die Maus bewegt? Seam weiß, wo es den Zeiger zuletzt hingesetzt hat.
    static func mouseIntervened(current: CGPoint, expected: CGPoint) -> Bool {
        hypot(current.x - expected.x, current.y - expected.y) > 4
    }

    /// Hat der Nutzer eine Taste gedrückt? `idle` = Sekunden seit der letzten Taste im System,
    /// `ownAge` = Sekunden seit Seams eigener letzter Taste (bzw. seit Beginn des Laufs).
    /// Kam danach noch eine, war es der Nutzer. Liest keine Tasteninhalte (E1).
    static func keyIntervened(idle: Double, ownAge: Double) -> Bool {
        idle + 0.05 < ownAge
    }

    // MARK: Vorbedingung

    /// Liegt der symbolische Kurzbefehl auf genau dieser Taste mit ⌃ (fn erlaubt, sonst nichts)?
    /// Fehlt der Eintrag, gilt der macOS-Standard: an, ⌃←/⌃→. Gemessen 19.10. bei Michael:
    /// `parameters = [65535, 123, 262144]` (262144 = ⌃).
    static func isSwitchShortcut(_ entry: [String: Any]?, key: CGKeyCode) -> Bool {
        guard let entry else { return true }
        let on = (entry["enabled"] as? Bool) ?? (entry["enabled"] as? NSNumber)?.boolValue ?? false
        let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any] ?? []
        guard on, params.count >= 3,
              let code = (params[1] as? NSNumber)?.intValue, let mods = (params[2] as? NSNumber)?.intValue else { return false }
        let control = 262_144, fn = 8_388_608
        return code == Int(key) && (mods & ~fn) == control
    }

    /// Sind ⌃←/⌃→ als „Einen Schreibtisch nach links/rechts“ aktiv (Kurzbefehle 79/81)?
    /// Sonst landete ⌃← in der App im Vordergrund — Seam läuft dann nicht (code-audit 19.10.:
    /// vorher wurde nur „eingeschaltet“ geprüft, nicht die Taste).
    static func spaceSwitchKeysEnabled() -> Bool {
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                            "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        return isSwitchShortcut(all?["79"] as? [String: Any], key: arrowLeft)
            && isSwitchShortcut(all?["81"] as? [String: Any], key: arrowRight)
    }

    // MARK: Ausführen

    /// Fenster um `steps` Spaces verschieben (positiv = nach rechts). Prüft am Ende nicht selbst,
    /// ob der Space stimmt — das macht der Lauf über `SpaceReader`.
    static func shift(_ window: AXWindow, by steps: Int, deadline: Date = .distantFuture) -> Outcome {
        guard validSteps(steps) else { return .invalidSteps }
        // Wächter ab dem ersten Moment: Wer schon während der Griffpunkt-Suche die Maus bewegt,
        // dem nimmt Seam sie nicht weg (Sichttest 19.10.: vorher griff Seam trotzdem zu).
        let session = Session()
        var outcome = Outcome.moved
        defer { session.finish(restoreCursor: outcome != .interrupted) }   // Pflicht 1: immer loslassen

        window.perform(.raise)                       // Pflicht 3: anheben, App nicht aktivieren
        usleep(250_000)
        guard let frame = window.frame else { outcome = .noGripPoint; return outcome }
        switch findGrip(window, in: frame, session: session, deadline: deadline) {
        case .failure(let stop): outcome = stop.outcome
        case .success(let grip):
            switch grab(window, at: grip, from: frame, session: session) {
            case .failure(let stop): outcome = stop.outcome
            case .success(let held):
                outcome = press(steps, session: session, deadline: deadline)
                if outcome == .moved {
                    session.emit(.leftMouseUp, at: held)
                    usleep(200_000)
                    outcome = session.modifiersClear() ? .moved : .modifiersStuck
                }
            }
        }
        return outcome
    }

    /// Abbruchgrund als `Error`, damit die Teilschritte `Result` liefern können.
    private struct Stop: Error { let outcome: Outcome }

    /// Erster sicherer Griffpunkt; prüft vor jedem Kandidaten Frist und Eingriff.
    private static func findGrip(_ window: AXWindow, in frame: CGRect, session: Session,
                                 deadline: Date) -> Result<CGPoint, Stop> {
        for candidate in gripCandidates(in: frame) {
            if Date() > deadline { return .failure(Stop(outcome: .timeUp)) }
            if session.userIntervened() { return .failure(Stop(outcome: .interrupted)) }
            if isSafe(candidate, for: window) { return .success(candidate) }
        }
        return .failure(Stop(outcome: .noGripPoint))
    }

    /// Zeiger hin, unmittelbar vorher noch einmal prüfen (Pflicht 2, rafter-code-review Fund 2),
    /// drücken, ziehen, Pflicht 4: Kam das Fenster mit? Rückgabe: Punkt, an dem die Maustaste gehalten wird.
    private static func grab(_ window: AXWindow, at grip: CGPoint, from frame: CGRect,
                             session: Session) -> Result<CGPoint, Stop> {
        // Vor dem ersten eigenen Zug: Hat der Nutzer seit dem Start die Maus bewegt? Danach setzt
        // Seam den Zeiger selbst um und könnte es nicht mehr erkennen (Sichttest 19.10., 14:35:
        // beim Aufteilen der Funktion verloren gegangen, früher Eingriff wurde übersehen).
        if session.userIntervened() { return .failure(Stop(outcome: .interrupted)) }
        session.emit(.mouseMove, at: grip); usleep(80_000)
        guard isSafe(grip, for: window) else { return .failure(Stop(outcome: .noGripPoint)) }
        if session.userIntervened() { return .failure(Stop(outcome: .interrupted)) }
        session.emit(.leftMouseDown, at: grip); usleep(150_000)
        var p = grip
        for _ in 0..<4 {
            p.x += 3
            session.emit(.leftMouseDragged, at: p)
            usleep(40_000)
        }
        // Prüfung erst nach dem ganzen Ziehweg (12 pt): Sichttest 19.10., 14:33 — eine Prüfung schon
        // nach 3 pt (code-audit-Vorschlag) ließ JEDES Greifen scheitern, macOS bewegt das Fenster
        // erst nach mehr Weg. Restrisiko: auf einem Web-Element, das die Taste schluckt, wird 12 pt
        // gezogen (z. B. Text markiert) — nur auf Elementen ohne Aktion (Pflicht 2).
        guard let moved = window.frame, abs(moved.minX - frame.minX) >= 1 else { return .failure(Stop(outcome: .notGrabbed)) }
        return .success(p)
    }

    /// ⌃←/⌃→ `steps`-mal, vor jedem Druck Frist und Eingriff prüfen. `.moved` = alle gedrückt.
    private static func press(_ steps: Int, session: Session, deadline: Date) -> Outcome {
        for _ in 0..<abs(steps) {
            if Date() > deadline { return .timeUp }
            if session.userIntervened() { return .interrupted }
            session.emit(.arrowWithControl, key: steps > 0 ? arrowRight : arrowLeft)
            usleep(900_000)                          // Wechselanimation
        }
        return session.userIntervened() ? .interrupted : .moved
    }

    /// Ansicht eines Bildschirms um `steps` Spaces umschalten, ohne etwas zu greifen — damit nach
    /// einer Fahrt der Ausgangs-Space wieder sichtbar ist (Bedienungshilfen sehen nur Fenster auf
    /// sichtbaren Spaces) und der Nutzer am Ende dort steht, wo er war. ⌃←/⌃→ wirkt auf den
    /// Bildschirm unter dem Zeiger (gemessen 19.10.) → Zeiger kurz dorthin, kein Klick.
    static func switchView(on screen: CGRect, by steps: Int, deadline: Date = .distantFuture) -> Outcome {
        guard validSteps(steps) else { return .invalidSteps }
        let session = Session()
        var interrupted = false
        defer { session.finish(restoreCursor: !interrupted) }
        let spot = CGPoint(x: screen.midX, y: screen.minY + min(200, screen.height / 3))
        session.emit(.mouseMove, at: spot)
        usleep(60_000)
        let outcome = press(steps, session: session, deadline: deadline)
        if outcome == .interrupted { interrupted = true }
        guard outcome == .moved else { return outcome }
        return session.modifiersClear() ? .moved : .modifiersStuck
    }

    /// Liegt an diesem Punkt ein harmloses Element genau dieses Fensters? (E17a-2)
    private static func isSafe(_ p: CGPoint, for window: AXWindow) -> Bool {
        guard let hit = AXAccess.element(at: p) else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid == window.pid else { return false }
        let owner = CFEqual(hit, window.element) ? hit : AXAccess.element(hit, .window)
        let belongs = owner.map { CFEqual($0, window.element) } ?? false
        return isSafeGrip(role: AXAccess.string(hit, .role), actions: AXAccess.actionNames(hit), belongsToTarget: belongs)
    }

    /// Ein Durchgang: merkt sich, wo der Zeiger stand, was gedrückt ist und wann Seam zuletzt
    /// eine Taste gesendet hat.
    private final class Session {
        private let source = CGEventSource(stateID: .hidSystemState)
        private let startCursor: CGPoint
        private var lastPoint: CGPoint?
        private var lastOwnKey = Date()
        private var buttonDown = false

        init() {
            startCursor = CGEvent(source: nil)?.location ?? .zero
            lastPoint = startCursor      // bis zum ersten eigenen Zug: Zeiger muss hier bleiben
        }

        /// **Einziger Ausgang für Ereignisse.** Art aus der Positivliste, Taste nur ← → bzw. die
        /// Sondertasten zum Lösen. Alles andere wird verworfen.
        func emit(_ kind: Kind, at point: CGPoint? = nil, key: CGKeyCode? = nil) {
            switch kind {
            case .mouseMove, .leftMouseDown, .leftMouseDragged, .leftMouseUp:
                guard let point else { return }
                let types: [Kind: CGEventType] = [.mouseMove: .mouseMoved, .leftMouseDown: .leftMouseDown,
                                                  .leftMouseDragged: .leftMouseDragged, .leftMouseUp: .leftMouseUp]
                guard let type = types[kind] else { return }
                let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                e?.flags = []
                e?.post(tap: .cghidEventTap)
                lastPoint = point
                if kind == .leftMouseDown { buttonDown = true }
                if kind == .leftMouseUp { buttonDown = false }
            case .arrowWithControl:
                guard let key, key == InputSynth.arrowLeft || key == InputSynth.arrowRight else { return }
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
                    e?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
                    e?.post(tap: .cghidEventTap)
                    usleep(30_000)
                }
                releaseModifiers()
                lastOwnKey = Date()
            case .releaseModifier:
                guard let key, InputSynth.releasedKeys.contains(key) else { return }
                let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
                e?.type = .flagsChanged
                e?.flags = []
                e?.post(tap: .cghidEventTap)
            }
        }

        private func releaseModifiers() {
            for k in InputSynth.releasedKeys { emit(.releaseModifier, key: k) }
        }

        func modifiersClear() -> Bool {
            let stuck: CGEventFlags = [.maskControl, .maskSecondaryFn]
            if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: stuck) { return true }
            releaseModifiers()
            usleep(50_000)
            return CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: stuck)
        }

        func userIntervened() -> Bool {
            if let expected = lastPoint, let now = CGEvent(source: nil)?.location,
               InputSynth.mouseIntervened(current: now, expected: expected) { return true }
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            return InputSynth.keyIntervened(idle: idle, ownAge: Date().timeIntervalSince(lastOwnKey))
        }

        /// Pflicht 1: Maustaste los, Sondertasten los, Zeiger zurück (nicht, wenn der Nutzer ihn bewegt hat).
        func finish(restoreCursor: Bool) {
            // Nach einem Eingriff dort loslassen, wo der Nutzer den Zeiger gerade hat — sonst
            // risse das Loslassen den Zeiger zurück an den alten Griffpunkt.
            let here = restoreCursor ? lastPoint : (CGEvent(source: nil)?.location ?? lastPoint)
            if buttonDown, let p = here { emit(.leftMouseUp, at: p) }
            releaseModifiers()
            if restoreCursor, let last = lastPoint, last != startCursor { emit(.mouseMove, at: startCursor) }
        }
    }
}
