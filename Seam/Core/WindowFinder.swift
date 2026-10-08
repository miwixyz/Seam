import AppKit

/// Findet die Fenster, die beim Gestenbeginn an einer Kante des führenden
/// Fensters liegen.
///
/// Zweistufig, damit ein Klick nicht jede laufende App abfragt: Erst die
/// Fensterliste des Systems (schnell, liefert Lage und Prozess, **keine Titel
/// ohne Bildschirmaufnahme-Freigabe**, die Seam bewusst nicht anfordert), dann
/// nur für die wenigen Kandidaten die Bedienungshilfen.
@MainActor
enum WindowFinder {

    static func neighbors(of leading: AXWindow, frame: CGRect, gap: CGFloat) -> [(AXWindow, CGRect)] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var candidatePIDs = Set<pid_t>()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { continue }
            if Geometry.isLinkCandidate(bounds, to: frame, gap: gap) { candidatePIDs.insert(pid) }
        }
        var out: [(AXWindow, CGRect)] = []
        for pid in candidatePIDs {
            for w in AXAccess.windows(of: pid) where w != leading {
                guard let f = w.frame, Geometry.isLinkCandidate(f, to: frame, gap: gap) else { continue }
                out.append((w, f))
            }
        }
        return out
    }
}
