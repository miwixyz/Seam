import AppKit

/// Ein Eintrag der Fensterliste des Systems: nur Nummer, Prozess, Lage — keine Titel (E13).
struct StackWindow: Equatable {
    let number: Int
    let pid: pid_t
    let bounds: CGRect
}

/// Einziger Zugang zur Fensterliste des Systems (`CGWindowListCopyWindowInfo`).
/// Code-Audit 09.10.: vorher fünf fast gleiche Kopien in WindowFinder, DragController und Dimmer.
/// Gelesen werden nur Ebene, Nummer, Prozess und Lage; `kCGWindowName`/`kCGWindowOwnerName`
/// verbietet die Lint-Regel `keine_fenstertitel`.
enum WindowList {

    /// Normale Fenster (Ebene 0) auf dem Bildschirm, vorn zuerst.
    /// `excludingOwn`: Seams eigene Fenster weglassen. Der Abdunkler braucht sie dagegen,
    /// um seine eigenen Abdunkel-Fenster im Stapel wiederzufinden.
    static func onScreen(excludingOwn: Bool = true) -> [StackWindow] {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  !(excludingOwn && pid == own),
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return nil }
            return StackWindow(number: n, pid: pid, bounds: bounds)
        }
    }

    /// Normale App mit Dock-Symbol? Überlagerungen wie HazeOver sind es nicht.
    static func isRegularApp(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }
}
