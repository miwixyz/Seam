import XCTest
@testable import Seam

/// E19: Online-Auswahl — Server-Liste, Adressen, Antworten, Dateinamen, Aufräumen.
final class OnlineMediaTests: XCTestCase {

    // MARK: E19a

    func testOnlyListedHttpsHosts() {
        XCTAssertTrue(OnlineHosts.isAllowed(URL(string: "https://images.pexels.com/photos/1/a.jpeg")))
        XCTAssertTrue(OnlineHosts.isAllowed(URL(string: "https://UPLOAD.wikimedia.org/x.jpg")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "http://images.pexels.com/a.jpeg")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "https://images.pexels.com.evil.example/a.jpeg")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "https://evil.example/images.pexels.com")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "https://images.pexels.com:8443/a.jpeg")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "https://user:pw@images.pexels.com/a.jpeg")))
        XCTAssertFalse(OnlineHosts.isAllowed(URL(string: "https://127.0.0.1/a.jpeg")))
        XCTAssertFalse(OnlineHosts.isAllowed(nil))
    }

    // MARK: E19c

    func testQueryIsCleanedAndEncoded() {
        XCTAssertEqual(OnlineAPI.cleanQuery("  Berge\n\u{0}  "), "Berge")
        XCTAssertEqual(OnlineAPI.cleanQuery(String(repeating: "a", count: 300)).count, 100)
        let url = OnlineAPI.pexels(query: "Berg & See", kind: .video, page: 2)!
        XCTAssertEqual(url.host, "api.pexels.com")
        XCTAssertEqual(url.path, "/videos/search")
        XCTAssertTrue(url.absoluteString.contains("query=Berg%20%26%20See"))
        XCTAssertTrue(url.absoluteString.contains("page=2"))
        XCTAssertEqual(OnlineAPI.pexels(query: "", kind: .photo, page: 1)?.path, "/v1/curated")
    }

    func testWikimediaSearchIsPhotosOnly() {
        let url = OnlineAPI.wikimedia(query: "Nebel", offset: 30)!
        XCTAssertEqual(url.host, "commons.wikimedia.org")
        XCTAssertTrue(url.absoluteString.contains("filetype:bitmap"))
        XCTAssertTrue(url.absoluteString.contains("gsroffset=30"))
    }

    // MARK: Antworten

    func testPexelsPhotos() throws {
        let json = """
        {"page":1,"per_page":2,"next_page":"https://api.pexels.com/v1/search?page=2",
         "photos":[
          {"id":2014422,"width":6000,"height":4000,"photographer":"Joey &amp; Co","alt":"x",
           "src":{"original":"https://images.pexels.com/photos/2014422/pexels-photo-2014422.jpeg",
                  "medium":"https://images.pexels.com/photos/2014422/pexels-photo-2014422.jpeg?h=350"}},
          {"id":5,"width":10,"height":10,"photographer":"Evil",
           "src":{"original":"https://evil.example/p.jpeg","medium":"https://evil.example/t.jpeg"}}]}
        """
        let page = try OnlineDecode.pexels(Data(json.utf8), kind: .photo)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].credit, "Joey & Co")
        XCTAssertEqual(page.items[0].fileExtension, "jpg")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.blockedHosts, ["evil.example"])
    }

    func testPexelsVideosPickMp4UpTo4K() throws {
        let json = """
        {"videos":[{"id":857195,"width":3840,"height":2160,"image":"https://images.pexels.com/videos/857195/a.jpeg",
         "user":{"name":"Ana"},"video_files":[
          {"link":"https://videos.pexels.com/video-files/857195/hd.mp4","width":1920,"height":1080,"file_type":"video/mp4"},
          {"link":"https://videos.pexels.com/video-files/857195/uhd.mp4","width":3840,"height":2160,"file_type":"video/mp4"},
          {"link":"https://videos.pexels.com/video-files/857195/8k.mp4","width":7680,"height":4320,"file_type":"video/mp4"},
          {"link":"https://videos.pexels.com/video-files/857195/x.webm","width":3840,"height":2160,"file_type":"video/webm"}]}]}
        """
        let page = try OnlineDecode.pexels(Data(json.utf8), kind: .video)
        XCTAssertEqual(page.items.first?.file.lastPathComponent, "uhd.mp4")
        XCTAssertEqual(page.items.first?.fileExtension, "mp4")
        XCTAssertFalse(page.hasMore)
    }

    func testWikimediaPagesFromMeasuredShape() throws {
        // Form wie gemessen 10.11. (formatversion=2).
        let json = """
        {"continue":{"gsroffset":30,"continue":"gsroffset||"},"query":{"pages":[
         {"pageid":134682226,"ns":6,"title":"File:Mountains.jpg","imageinfo":[{"url":"https://upload.wikimedia.org/a/Mountains.jpg",
          "thumburl":"https://upload.wikimedia.org/thumb/a/480px.jpg","width":4032,"height":2688,"mime":"image/jpeg",
          "extmetadata":{"LicenseShortName":{"value":"CC BY 4.0"},"Artist":{"value":"<a href=\\"//x\\">Vyacheslav <b>Argenberg</b></a>"}}}]},
         {"pageid":2,"ns":6,"title":"File:Clip.webm","imageinfo":[{"url":"https://upload.wikimedia.org/c.webm",
          "thumburl":"https://upload.wikimedia.org/c.jpg","width":1,"height":1,"mime":"video/webm"}]}]}}
        """
        let (page, next) = try OnlineDecode.wikimedia(Data(json.utf8))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].credit, "Vyacheslav Argenberg")
        XCTAssertEqual(page.items[0].license, "CC BY 4.0")
        XCTAssertEqual(next, 30)
    }

    // MARK: E19d

    func testFileNameNeverFromServer() {
        let item = OnlineItem(source: .pexels, kind: .photo, number: 42, width: 1, height: 1,
                              thumb: URL(string: "https://images.pexels.com/t.jpg")!,
                              file: URL(string: "https://images.pexels.com/../../etc/passwd.jpeg")!,
                              fileExtension: "jpg", credit: "", license: "")
        XCTAssertEqual(OnlineFiles.name(for: item), "pexels-42.jpg")
        let bad = OnlineItem(source: .pexels, kind: .photo, number: 42, width: 1, height: 1,
                             thumb: item.thumb, file: item.file, fileExtension: "sh", credit: "", license: "")
        XCTAssertNil(OnlineFiles.name(for: bad))
    }

    func testCleanupKeepsChosenFiles() {
        let now = Date()
        let files = (0..<33).map { (name: "pexels-\($0).jpg", date: now.addingTimeInterval(Double($0))) }
        let gone = OnlineFiles.toRemove(files, keep: ["pexels-0.jpg"])
        XCTAssertEqual(gone, ["pexels-1.jpg", "pexels-2.jpg", "pexels-3.jpg"])
        XCTAssertTrue(OnlineFiles.toRemove(Array(files.prefix(30)), keep: []).isEmpty)
    }

    // MARK: E19e und E19b

    func testPlainTextStripsHTML() {
        XCTAssertEqual(OnlineText.plain("<span>A &amp; B</span>\n<script>x</script>"), "A & B x")
        XCTAssertEqual(OnlineText.plain(String(repeating: "x", count: 500)).count, 120)
    }

    func testKeyShape() {
        XCTAssertTrue(ApiKey.isValid(String(repeating: "aB3", count: 18)))
        XCTAssertFalse(ApiKey.isValid("kurz"))
        XCTAssertFalse(ApiKey.isValid(String(repeating: "a", count: 30) + " "))
        XCTAssertFalse(ApiKey.isValid(String(repeating: "ä", count: 30)))
        XCTAssertTrue(ApiKey.isValid("12345678-0123456789abcdef01234567"))
        XCTAssertFalse(ApiKey.isValid("12345678-0123456789abcdef0123456&x=1"))
    }

    // MARK: Pixabay (Doku 10.11.)

    func testPixabayAddressCarriesKeyOnlyToPixabay() {
        let url = OnlineAPI.pixabay(query: "Nebel", kind: .video, page: 2, key: "12345678-abcdef0123456789abcd")!
        XCTAssertEqual(url.host, "pixabay.com")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://pixabay.com/api/videos/?"))
        XCTAssertTrue(url.absoluteString.contains("key=12345678-abcdef0123456789abcd"))
        XCTAssertTrue(url.absoluteString.contains("q=Nebel"))
        XCTAssertTrue(OnlineHosts.isAllowed(url))
        let photos = OnlineAPI.pixabay(query: "", kind: .photo, page: 1, key: "k")!
        XCTAssertTrue(photos.absoluteString.hasPrefix("https://pixabay.com/api/?"))
        XCTAssertTrue(photos.absoluteString.contains("editors_choice=true"))
        XCTAssertTrue(photos.absoluteString.contains("orientation=horizontal"))
    }

    func testPixabayVideosSkipEmptyLarge() throws {
        let json = """
        {"total":2,"totalHits":45,"hits":[
         {"id":125,"user":"Ana","videos":{
           "large":{"url":"","width":0,"height":0,"size":0,"thumbnail":""},
           "medium":{"url":"https://cdn.pixabay.com/video/2015/08/08/125_medium.mp4","width":1280,"height":720,
                     "thumbnail":"https://cdn.pixabay.com/video/2015/08/08/125_medium.jpg"}}},
         {"id":7,"user":"B","videos":{
           "large":{"url":"https://cdn.pixabay.com/video/7_large.mp4","width":3840,"height":2160,
                    "thumbnail":"https://cdn.pixabay.com/video/7_large.jpg"}}}]}
        """
        let page = try OnlineDecode.pixabay(Data(json.utf8), kind: .video, page: 1)
        XCTAssertEqual(page.items.map(\.number), [125, 7])
        XCTAssertEqual(page.items[0].width, 1280)
        XCTAssertEqual(page.items[1].file.lastPathComponent, "7_large.mp4")
        XCTAssertTrue(page.hasMore)   // 30 < 45
    }

    func testPixabayPhotoTakesLargestOffered() throws {
        let json = """
        {"total":1,"totalHits":1,"hits":[
         {"id":195893,"user":"Josch13","imageWidth":4000,"imageHeight":2250,
          "previewURL":"https://cdn.pixabay.com/photo/2013/10/15/09/12/flower-195893_150.jpg",
          "webformatURL":"https://pixabay.com/get/35bbf209e13e39d2_640.jpg",
          "largeImageURL":"https://pixabay.com/get/ed6a99fd0a76647_1280.jpg"}]}
        """
        let page = try OnlineDecode.pixabay(Data(json.utf8), kind: .photo, page: 1)
        XCTAssertEqual(page.items.first?.file.lastPathComponent, "ed6a99fd0a76647_1280.jpg")
        XCTAssertEqual(page.items.first?.width, 1280)
        XCTAssertEqual(page.items.first?.height, 720)
        XCTAssertFalse(page.hasMore)
    }
}
