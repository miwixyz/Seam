import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Seam

/// Stream Deck, Stufe 3 (E20l): Bildordner-Ring. Echte Dateien in einem Wegwerf-Ordner unter /tmp.
final class ImageRingTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        dir = URL(fileURLWithPath: "/tmp/seamring-test-\(UInt32.random(in: 0...999_999))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let p = dir.appendingPathComponent(n).path
            var st = stat()
            if lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR { rmdir(p) } else { unlink(p) }
        }
        rmdir(dir.path)
    }

    @discardableResult
    private func make(_ name: String, bytes: Int = 10, sparse: Int? = nil) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        if let sparse, let h = try? FileHandle(forWritingTo: url) {
            try? h.truncate(atOffset: UInt64(sparse))
            try? h.close()
        }
        return url
    }

    private func names(_ files: [URL]) -> [String] { files.map(\.lastPathComponent) }

    func testOnlyValidDirectFilesAreInTheRing() throws {
        make("b.jpg"); make("A.png"); make("c.MOV"); make("d.heic"); make("e.mp4")
        make("notiz.txt"); make("leer.jpg", bytes: 0); make(".versteckt.jpg"); make("skript.sh"); make("bild.jpg.exe")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("unterordner.jpg"), withIntermediateDirectories: true)
        make("unterordner.jpg/inner.jpg")   // Dateien in Unterordnern zählen nicht
        XCTAssertEqual(symlink(dir.appendingPathComponent("b.jpg").path, dir.appendingPathComponent("link.jpg").path), 0)
        XCTAssertEqual(names(ImageRing.files(in: dir)), ["A.png", "b.jpg", "c.MOV", "d.heic", "e.mp4"],
                       "nach Name sortiert, ohne Link, Ordner, leere und fremde Dateien")
    }

    func testSizeLimitsAndFileCap() {
        make("klein.jpg")
        make("gross.jpg", bytes: 1, sparse: ImageRing.maxImageBytes + 1)
        make("grenze.jpg", bytes: 1, sparse: ImageRing.maxImageBytes)
        make("video.mp4", bytes: 1, sparse: ImageRing.maxImageBytes + 1)          // Video darf größer sein
        make("riesig.mov", bytes: 1, sparse: ImageRing.maxVideoBytes + 1)
        XCTAssertEqual(names(ImageRing.files(in: dir)), ["grenze.jpg", "klein.jpg", "video.mp4"])
        for i in 0..<(ImageRing.maxFiles + 5) { make(String(format: "z%03d.png", i)) }
        XCTAssertEqual(ImageRing.files(in: dir).count, ImageRing.maxFiles, "höchstens 200")
    }

    func testMissingFolderGivesEmptyRing() {
        XCTAssertTrue(ImageRing.files(in: URL(fileURLWithPath: "/tmp/gibt-es-nicht-\(UInt32.random(in: 0...999_999))")).isEmpty)
    }

    func testStepWrapsAndJumpsToTheEndsWhenCurrentIsOutside() {
        let ring = ["a", "b", "c"].map { URL(fileURLWithPath: "/x/\($0).jpg") }
        XCTAssertEqual(ImageRing.step(from: "/x/a.jpg", in: ring, dir: 1)?.lastPathComponent, "b.jpg")
        XCTAssertEqual(ImageRing.step(from: "/x/c.jpg", in: ring, dir: 1)?.lastPathComponent, "a.jpg", "letztes → erstes")
        XCTAssertEqual(ImageRing.step(from: "/x/a.jpg", in: ring, dir: -1)?.lastPathComponent, "c.jpg", "erstes → letztes")
        XCTAssertEqual(ImageRing.step(from: "/anderswo/q.jpg", in: ring, dir: 1)?.lastPathComponent, "a.jpg", "außerhalb → erste Datei")
        XCTAssertEqual(ImageRing.step(from: nil, in: ring, dir: -1)?.lastPathComponent, "c.jpg")
        XCTAssertNil(ImageRing.step(from: "/x/a.jpg", in: [], dir: 1), "leerer Ring: nichts")
        XCTAssertEqual(ImageRing.position(of: "/x/b.jpg", in: ring), 2)
        XCTAssertNil(ImageRing.position(of: "/x/zz.jpg", in: ring))
    }

    func testNeverReturnsAFileOutsideTheFolder() {
        make("a.jpg"); make("b.jpg")
        let ring = ImageRing.files(in: dir)
        for dirn in [1, -1] {
            let next = ImageRing.step(from: "/etc/passwd", in: ring, dir: dirn)
            XCTAssertEqual(next?.deletingLastPathComponent().path, dir.path)
        }
    }

    // MARK: Vorschau (E20m)

    private func writePNG(_ name: String, width: Int, height: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for i in 0..<20 {   // bunte Streifen: bewusst schwer zu komprimieren
            ctx.setFillColor(CGColor(red: CGFloat(i % 5) / 4, green: CGFloat(i % 3) / 2, blue: CGFloat(i % 7) / 6, alpha: 1))
            ctx.fill(CGRect(x: i * width / 20, y: 0, width: width / 20 + 1, height: height))
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func testPreviewIsASmallJPEGAndNeverTheOriginal() throws {
        let url = writePNG("wide.png", width: 1600, height: 900)
        let data = try XCTUnwrap(ImageRing.previewJPEG(of: url))
        XCTAssertLessThanOrEqual(data.count, DeckWire.maxPreviewBytes)
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8]))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 200)
        XCTAssertEqual(img.height, 100)
        let high = writePNG("hoch.png", width: 300, height: 900)    // Hochformat wird zugeschnitten, nicht verzerrt gesendet
        XCTAssertNotNil(ImageRing.previewJPEG(of: high))
    }

    func testPreviewRefusesVideoLinkEmptyAndUnknownFiles() {
        let real = writePNG("echt.png", width: 400, height: 300)
        make("film.mp4"); make("notiz.txt"); make("leer.png", bytes: 0)
        XCTAssertEqual(symlink(real.path, dir.appendingPathComponent("link.png").path), 0)
        for name in ["film.mp4", "notiz.txt", "leer.png", "link.png", "gibt-es-nicht.png"] {
            XCTAssertNil(ImageRing.previewJPEG(of: dir.appendingPathComponent(name)), name)
        }
        make("kaputt.jpg", bytes: 2000)   // kein gültiges Bild
        XCTAssertNil(ImageRing.previewJPEG(of: dir.appendingPathComponent("kaputt.jpg")))
    }
}
