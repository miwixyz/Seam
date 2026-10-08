import CoreGraphics
import Foundation

/// Welche Fenster gehören als geteiltes Paar zusammen (docs/SECURE-DESIGN.md E12).
///
/// Reine Buchführung ohne Bedienungshilfen, damit sie testbar ist. Ein Fenster gehört
/// zu höchstens einem Paar; ein neues Paar mit einem schon gepaarten Fenster löst das
/// alte auf. Nur im Speicher (E10).
struct PairBook<W: Hashable> {

    private(set) var pairs: [(W, W)] = []

    /// Neues Paar. Alte Paare mit `a` oder `b` lösen sich auf.
    mutating func add(_ a: W, _ b: W) {
        guard a != b else { return }
        remove(containing: a)
        remove(containing: b)
        pairs.append((a, b))
    }

    func partner(of w: W) -> W? {
        for (a, b) in pairs {
            if a == w { return b }
            if b == w { return a }
        }
        return nil
    }

    /// Löst das Paar mit `w` auf. Rückgabe: der bisherige Partner.
    @discardableResult
    mutating func remove(containing w: W) -> W? {
        let p = partner(of: w)
        pairs.removeAll { $0.0 == w || $0.1 == w }
        return p
    }

    /// Löst alle Paare auf, in denen ein Fenster die Bedingung erfüllt (z. B. App beendet).
    mutating func removeAll(where match: (W) -> Bool) {
        pairs.removeAll { match($0.0) || match($0.1) }
    }

    mutating func removeAll() { pairs = [] }

    var windows: [W] { pairs.flatMap { [$0.0, $0.1] } }
    var isEmpty: Bool { pairs.isEmpty }
}

extension Geometry {
    /// Stehen zwei Fenster noch Kante an Kante? Sonst gilt ein Paar als aufgelöst (E12):
    /// Ein altes Paar darf kein Fenster an einer unerwarteten Stelle nach vorn holen.
    static func stillSideBySide(_ a: CGRect, _ b: CGRect, gap: CGFloat) -> Bool {
        [Edge.left, .right, .top, .bottom].contains { isFacing(b, to: a, gap: gap, edge: $0) }
    }
}
