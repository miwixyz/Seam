import CoreGraphics

/// Rahmen eines Mindestgrößen-Falls: verlangt/tatsächlich beim Nachbarn, danach Soll/Ist beider.
struct MinimumHit: Sendable {
    let wanted: CGRect
    let actual: CGRect
    let fix: (leading: CGRect, neighbor: CGRect)
    let neighborIst: CGRect?
    let leadingIst: CGRect?

    var notice: MinimumNotice? {
        MinimumNotice.evaluate(wanted: wanted, actual: actual, leadingWanted: fix.leading, leadingActual: leadingIst)
    }
}

/// Hinweis, wenn ein Fenster nicht so klein wurde, wie Seam es verlangt hat.
///
/// Anlass (Michael, 10.10.: „Das muss aber irgendwie erkenntlich sein“): Edge + Outlook auf
/// dem MacBook (1470 pt). Seam teilte, Outlook blieb bei 980 pt, Edge bei 500 pt. Beide an
/// ihrer Mindestgröße, zusammen breiter als der Bildschirm. Die Fenster überlappten 30 pt,
/// Seam meldete das nur im Protokoll. Für den Nutzer sah es aus, als funktioniere die Naht nicht.
enum MinimumNotice: Equatable, Sendable {
    /// Der Nachbar blieb an seiner Mindestgröße, die Naht steht dort. Beide passen.
    case held(minimum: CGFloat, horizontal: Bool)
    /// Auch das andere Fenster blieb an seiner Mindestgröße: Die beiden passen nicht nebeneinander.
    case noRoom(minimum: CGFloat, otherMinimum: CGFloat, horizontal: Bool)

    /// - Parameters:
    ///   - wanted/actual: verlangter und tatsächlicher Rahmen des Nachbarn beim ersten Setzen.
    ///   - leadingWanted/leadingActual: Rahmen, auf den das andere Fenster danach angepasst
    ///     werden sollte (`Geometry.resolveMinimum`), und was es tatsächlich wurde.
    /// - Returns: `nil`, wenn der Nachbar wie verlangt gesetzt wurde.
    static func evaluate(wanted w: CGRect, actual a: CGRect,
                         leadingWanted lw: CGRect, leadingActual la: CGRect?) -> MinimumNotice? {
        let e: CGFloat = 1
        let horizontal = a.width > w.width + e
        guard horizontal || a.height > w.height + e else { return nil }
        let minimum = horizontal ? a.width : a.height
        // Nicht lesbar heißt nicht „passt nicht“: dann nur die gehaltene Naht melden.
        guard let la else { return .held(minimum: minimum, horizontal: horizontal) }
        let got = horizontal ? la.width : la.height
        let asked = horizontal ? lw.width : lw.height
        if got > asked + e {
            return .noRoom(minimum: minimum, otherMinimum: got, horizontal: horizontal)
        }
        return .held(minimum: minimum, horizontal: horizontal)
    }

    /// Text für das Hinweisschild. `neighbor` = App mit der Mindestgröße, `other` = das andere Fenster.
    func text(neighbor: String, other: String) -> String {
        switch self {
        case let .held(minimum, horizontal):
            return "\(neighbor) geht nicht \(horizontal ? "schmaler" : "niedriger") als \(Int(minimum.rounded())) pt.\n"
                + "Die Naht steht an dieser Grenze."
        case let .noRoom(minimum, otherMinimum, horizontal):
            let side = horizontal ? "nebeneinander" : "übereinander"
            return "\(other) und \(neighbor) passen hier nicht \(side).\n"
                + "\(other) braucht mindestens \(Int(otherMinimum.rounded())) pt, \(neighbor) \(Int(minimum.rounded())) pt.\n"
                + "Tipp: Seitenleiste einer App einklappen."
        }
    }

    /// Mitte der Kante des Nachbarn, die dem anderen Fenster zugewandt ist (dort steht das Schild).
    static func anchor(leading l: CGRect, neighbor n: CGRect, horizontal: Bool) -> CGPoint {
        if horizontal {
            return CGPoint(x: n.midX > l.midX ? n.minX : n.maxX, y: n.midY)
        }
        return CGPoint(x: n.midX, y: n.midY > l.midY ? n.minY : n.maxY)
    }

    var horizontal: Bool {
        switch self {
        case let .held(_, h), let .noRoom(_, _, h): return h
        }
    }
}
