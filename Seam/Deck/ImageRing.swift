import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bildordner-Ring für das Stream Deck (Stufe 3, E20l): „nächstes/voriges Bild“ aus einem vom Nutzer gewählten Ordner.
/// Rein bis auf `lstat`/Verzeichnisliste, getestet. Der Ordner kommt nur aus dem Öffnen-Dialog der Einstellungen, nie aus einem
/// Deck-Befehl; der Dateiname entsteht hier aus der Verzeichnisliste, nie aus einer Nachricht.
enum ImageRing {

    nonisolated static let maxFiles = 200
    nonisolated static let maxImageBytes = 60 * 1024 * 1024
    nonisolated static let maxVideoBytes = 600 * 1024 * 1024
    nonisolated static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    nonisolated static let videoExtensions: Set<String> = ["mp4", "mov"]

    /// Reguläre Dateien direkt im Ordner (nicht rekursiv), keine Links, keine Pakete, nur Positivliste, nicht leer, unter der
    /// Größengrenze (Grenzen wie E19c), nach Name sortiert, höchstens 200. Ordner unlesbar → leer.
    nonisolated static func files(in folder: URL) -> [URL] {
        guard let all = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        // Erst nach Name und Endung filtern, dann sortieren: Ein riesiger Ordner (Downloads) kostet sonst bei jedem Aufruf Zeit.
        let known = imageExtensions.union(videoExtensions)
        let names = all.filter { !$0.hasPrefix(".") && known.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var out: [URL] = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard isEligible(url) else { continue }
            out.append(url)
            if out.count == maxFiles { break }
        }
        return out
    }

    /// Positivliste, reguläre Datei (kein Link, Ordner, Paket), nicht leer, unter der Größengrenze.
    nonisolated static func isEligible(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let isImage = imageExtensions.contains(ext), isVideo = videoExtensions.contains(ext)
        guard isImage || isVideo else { return false }
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return false }
        let size = Int(st.st_size)
        return size > 0 && size <= (isVideo ? maxVideoBytes : maxImageBytes)
    }

    /// Nächste (dir > 0) bzw. vorige Datei, ringförmig. Liegt `current` nicht im Ring, springt es zur ersten (bzw. letzten) Datei.
    nonisolated static func step(from current: String?, in ring: [URL], dir: Int) -> URL? {
        guard !ring.isEmpty else { return nil }
        guard let current, let i = ring.firstIndex(where: { $0.path == current }) else { return dir > 0 ? ring.first : ring.last }
        return ring[((i + (dir > 0 ? 1 : -1)) % ring.count + ring.count) % ring.count]
    }

    /// Stelle im Ring (1-basiert) für die Anzeige, nil wenn die Datei nicht im Ring liegt.
    nonisolated static func position(of current: String?, in ring: [URL]) -> Int? {
        guard let current, let i = ring.firstIndex(where: { $0.path == current }) else { return nil }
        return i + 1
    }

    nonisolated static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }

    // MARK: Vorschau (Stufe 3, E20m)

    /// 200 × 100 JPEG ≤ 5000 Byte aus einem Bild, nur Bilder (kein Video), nur zulässige Dateien. Das Plugin bekommt nie das Original.
    /// System-Decoder (E18b), kein Zwischenspeicher, nichts auf Platte. nil = keine Vorschau.
    nonisolated static func previewJPEG(of url: URL) -> Data? {
        guard imageExtensions.contains(url.pathExtension.lowercased()), isEligible(url) else { return nil }
        let w = DeckWire.previewSize.width, h = DeckWire.previewSize.height
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else { return nil }
        let thumbOpts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: max(w, h) * 2, kCGImageSourceShouldCache: false]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Bildfüllend zuschneiden, mittig.
        let scale = max(CGFloat(w) / CGFloat(thumb.width), CGFloat(h) / CGFloat(thumb.height))
        let dw = CGFloat(thumb.width) * scale, dh = CGFloat(thumb.height) * scale
        ctx.interpolationQuality = .medium
        ctx.draw(thumb, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        guard let image = ctx.makeImage() else { return nil }
        for quality in [0.7, 0.5, 0.35, 0.2] as [CGFloat] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length <= DeckWire.maxPreviewBytes { return out as Data }
        }
        return nil
    }
}
