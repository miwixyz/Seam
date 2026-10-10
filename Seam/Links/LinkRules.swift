import Foundation

/// Links verteilen wie Velja (docs/SECURE-DESIGN.md E16). Reine Logik ohne AppKit und ohne
/// Bedienungshilfen: Diese Datei entscheidet nur, welcher Browser eine Adresse bekommt.
/// Lint-Regel `link_weg_ohne_ax` hält AX aus allen Link-Dateien heraus (E16a).

/// Eine Regel: Website und/oder Quell-App → Browser (Bundle-ID). Mindestens eine Bedingung.
struct LinkRule: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// Host ohne Schema, kleingeschrieben, z. B. `cineweb.de` (trifft auch `www.cineweb.de`).
    var host: String?
    /// Bundle-ID der App, aus der der Link kommt, z. B. `com.tinyspeck.slackmacgap`.
    var sourceApp: String?
    /// Bundle-ID des Ziel-Browsers.
    var browser: String
}

enum LinkRules {

    static let maxRules = 200
    static let maxURLLength = 32_768
    static let maxHostLength = 253
    static let maxBundleIDLength = 255

    // MARK: - E16b: Annahme

    /// Nur http/https mit Host, Länge begrenzt. Alles andere: nil (wird verworfen).
    static func accept(_ raw: String) -> URL? {
        guard raw.utf8.count <= maxURLLength,
              let c = URLComponents(string: raw),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    // MARK: - E16e: Website-Vergleich

    /// Host einer Adresse oder einer Eingabe des Nutzers vereinheitlichen. Erlaubt nur
    /// a–z, 0–9, `-`, `.` — Eingaben wie `https://www.cineweb.de/kino` werden auf den Host gekürzt.
    /// Ungültig → nil.
    static func normalizeHost(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("://"), let h = URLComponents(string: s)?.host { s = h }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        while s.hasSuffix(".") { s.removeLast() }
        while s.hasPrefix(".") { s.removeFirst() }
        guard !s.isEmpty, s.count <= maxHostLength,
              s.unicodeScalars.allSatisfy({ allowedHostScalar($0) }),
              !s.contains("..") else { return nil }
        return s
    }

    /// Host einer eingehenden Adresse, streng: dekodiert (IDN als Punycode), kleingeschrieben,
    /// ohne abschließenden Punkt, nur a–z 0–9 `-` `.`. Wird verworfen statt gekürzt — sonst würde
    /// aus `evil%2Ecom%2F.cineweb.de` beim Kürzen am `/` ein anderer Host (Rafter-Review 10.10.).
    /// IPv6, kodierte Zeichen, Leerzeichen → nil (dann greifen nur Regeln ohne Website).
    static func urlHost(_ url: URL) -> String? {
        guard var h = url.host(percentEncoded: false)?.lowercased() else { return nil }
        while h.hasSuffix(".") { h.removeLast() }
        guard !h.isEmpty, h.count <= maxHostLength, !h.hasPrefix("."), !h.contains(".."),
              h.unicodeScalars.allSatisfy({ allowedHostScalar($0) }) else { return nil }
        return h
    }

    /// `rule` trifft `host` genau oder als Subdomain, nur an der Punktgrenze.
    /// `host` muss aus `urlHost` stammen.
    static func hostMatches(_ host: String, rule: String) -> Bool {
        host == rule || host.hasSuffix("." + rule)
    }

    // MARK: - Entscheidung

    /// Ziel-Browser für eine Adresse. Erste passende Regel gewinnt (Reihenfolge der Liste).
    /// Passende Regel mit nicht verfügbarem Ziel → Standard-Browser (E16c). Kein Standard → nil
    /// (dann fragt Seam per Auswahlfenster).
    static func decide(url: URL, source: String?, rules: [LinkRule],
                       available: Set<String>, fallback: String?) -> String? {
        let validFallback = fallback.flatMap { available.contains($0) ? $0 : nil }
        let host = urlHost(url)
        for rule in rules {
            if let h = rule.host {
                guard let host, hostMatches(host, rule: h) else { continue }
            }
            if let s = rule.sourceApp, s != source { continue }
            if rule.host == nil && rule.sourceApp == nil { continue }
            return available.contains(rule.browser) ? rule.browser : validFallback
        }
        return validFallback
    }

    // MARK: - E16h: Tracking-Parameter

    /// Feste Liste, keine nachgeladene. Vergleich kleingeschrieben.
    static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid",
        "igshid", "igsh", "twclid", "ttclid", "yclid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id",
        "oly_enc_id", "vero_id", "wickedid", "rb_clickid", "s_cid", "_ga", "_gl", "srsltid",
    ]
    /// `si` ist nur bei diesen Hosts ein Tracker (anderswo kann es Inhalt sein).
    static let siHosts: Set<String> = ["youtu.be", "youtube.com", "open.spotify.com"]

    /// Entfernt nur bekannte Abfrage-Parameter. Wird nichts entfernt, kommt die Adresse
    /// unverändert zurück (byte-gleich, wichtig für signierte Adressen).
    static func stripTracking(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = c.percentEncodedQueryItems, !items.isEmpty else { return url }
        let host = (c.host ?? "").lowercased()
        let siIsTracker = siHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        let kept = items.filter { item in
            let k = item.name.lowercased()
            if k.hasPrefix("utm_") || trackingKeys.contains(k) { return false }
            if k == "si", siIsTracker { return false }
            return true
        }
        guard kept.count != items.count else { return url }
        c.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return c.url ?? url
    }

    // MARK: - E16i: gespeicherte Regeln bereinigen

    /// Beim Laden: höchstens `maxRules`, ungültige Einträge verworfen, Host vereinheitlicht.
    static func sanitize(_ rules: [LinkRule]) -> [LinkRule] {
        var out: [LinkRule] = []
        for var r in rules {
            guard out.count < maxRules, isBundleID(r.browser) else { continue }
            if let h = r.host {
                guard let n = normalizeHost(h) else { continue }
                r.host = n
            }
            if let s = r.sourceApp, !isBundleID(s) { continue }
            guard r.host != nil || r.sourceApp != nil else { continue }
            out.append(r)
        }
        return out
    }

    /// Regeln aus gespeicherten Daten. Kaputte Daten → leere Liste, einzelne kaputte Einträge
    /// werden übersprungen.
    static func decode(_ data: Data?) -> [LinkRule] {
        guard let data,
              let raw = try? JSONDecoder().decode([Lossy<LinkRule>].self, from: data) else { return [] }
        return sanitize(raw.compactMap(\.value))
    }

    static func encode(_ rules: [LinkRule]) -> Data? {
        try? JSONEncoder().encode(rules)
    }

    static func isBundleID(_ s: String) -> Bool {
        !s.isEmpty && s.count <= maxBundleIDLength && s.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-"
        }
    }

    private static func allowedHostScalar(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "-" || c == "."
    }
}

/// Schutz gegen Pingpong mit unbekannten Link-Verteilern (E16c, Rafter-Review 10.10.): Seam merkt
/// sich 2 s lang, welche Adresse an welche App ging. Kommt genau diese Adresse von genau dieser
/// App zurück, reicht Seam sie nicht noch einmal dorthin.
struct RecentHandoffs {
    static let window: TimeInterval = 2
    static let maxEntries = 50
    private struct Entry { let url: String, target: String, at: Date }
    private var entries: [Entry] = []

    mutating func record(_ url: URL, to target: String, now: Date = Date()) {
        prune(now)
        entries.append(Entry(url: url.absoluteString, target: target.lowercased(), at: now))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    /// Kam `url` gerade von `source` zurück, an die Seam sie selbst gegeben hat?
    mutating func isBounce(_ url: URL, from source: String?, now: Date = Date()) -> Bool {
        prune(now)
        guard let s = source?.lowercased() else { return false }
        let u = url.absoluteString
        return entries.contains { $0.url == u && $0.target == s }
    }

    private mutating func prune(_ now: Date) {
        entries.removeAll { now.timeIntervalSince($0.at) > Self.window }
    }
}

/// Dekodiert ein Element oder liefert nil, statt die ganze Liste scheitern zu lassen.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
