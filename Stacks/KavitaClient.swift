import Foundation

enum KavitaError: LocalizedError {
    case badURL
    case http(Int, String)
    case noApiKey

    var errorDescription: String? {
        switch self {
        case .badURL: return "That server address doesn't look right. Try something like http://192.168.1.20:5000"
        case .http(401, _): return "Kavita rejected the login. Check your username and password, or your Auth Key."
        case .http(let code, let body): return "Server error \(code). \(body.prefix(200))"
        case .noApiKey: return "Kavita didn't return an Auth Key for this account."
        }
    }
}

/// Thin async wrapper around the Kavita REST API.
/// Every request sends the user's Auth Key in the `x-api-key` header.
/// Image URLs carry it as `?apiKey=` so they also work in image views and web views.
struct KavitaClient {
    let baseURL: URL
    let apiKey: String

    /// Lets Kavita show this app as an iPhone in its device list and reading history.
    /// Set once at launch with the real screen size.
    nonisolated(unsafe) static var clientHeader = "web-app/1.0 (Stacks/1.0; Ios; Mobile; 390x844; portrait)"

    /// A stable id for this install, so Kavita sees one device rather than many.
    static let deviceId: String = {
        if let saved = UserDefaults.standard.string(forKey: "deviceId") { return saved }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "deviceId")
        return id
    }()

    private func addClientHeaders(_ req: inout URLRequest) {
        req.setValue(Self.clientHeader, forHTTPHeaderField: "X-Kavita-Client")
        req.setValue(Self.deviceId, forHTTPHeaderField: "X-Device-Id")
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 500_000_000)
        return URLSession(configuration: config)
    }()

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    /// True for errors that mean "the server couldn't be reached" rather than "the server said no".
    static func isOffline(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        if case KavitaError.http(let code, _) = error, code == 502 || code == 503 || code == 504 || code == 530 {
            return true // Cloudflare answers with these when the PC or Kavita is down
        }
        return false
    }

    // MARK: Auth

    static func login(server: URL, username: String, password: String) async throws -> String {
        let client = KavitaClient(baseURL: server, apiKey: "")
        let user: LoginResponse = try await client.send("POST", "/api/Account/login",
                                                        body: LoginBody(username: username, password: password),
                                                        authenticated: false)
        guard let key = user.apiKey, !key.isEmpty else { throw KavitaError.noApiKey }
        return key
    }

    // MARK: Browsing

    func libraries() async throws -> [Library] {
        try await send("GET", "/api/Library/libraries")
    }

    func series(libraryId: Int?, search: String?, sort: SeriesSort = .name, page: Int,
                pageSize: Int = 60) async throws -> [Series] {
        try await send("POST", "/api/Series/all-v2", query: ["PageNumber": "\(page)", "PageSize": "\(pageSize)"],
                       body: SeriesFilter.make(libraryId: libraryId, search: search, sort: sort))
    }

    func onDeck() async throws -> [Series] {
        try await send("POST", "/api/Series/on-deck", query: ["PageNumber": "1", "PageSize": "30"],
                       body: Optional<String>.none)
    }

    func recentlyAdded() async throws -> [Series] {
        try await send("POST", "/api/Series/recently-added-v2", query: ["PageNumber": "1", "PageSize": "30"],
                       body: SeriesFilter.make(libraryId: nil, search: nil, sort: .added))
    }

    func recentlyUpdated() async throws -> [GroupedSeries] {
        try await send("POST", "/api/Series/recently-updated-series", query: ["PageNumber": "1", "PageSize": "30"],
                       body: Optional<String>.none)
    }

    func series(id: Int) async throws -> Series {
        try await send("GET", "/api/Series/\(id)")
    }

    func seriesDetail(id: Int) async throws -> SeriesDetail {
        try await send("GET", "/api/Series/series-detail", query: ["seriesId": "\(id)"])
    }

    func metadata(seriesId: Int) async throws -> SeriesMetadata {
        try await send("GET", "/api/Series/metadata", query: ["seriesId": "\(seriesId)"])
    }

    func continuePoint(seriesId: Int) async throws -> Chapter {
        try await send("GET", "/api/Reader/continue-point", query: ["seriesId": "\(seriesId)"])
    }

    // MARK: Reading

    /// `extractPdf` makes Kavita treat PDFs as page images, so they read like comics.
    func chapterInfo(chapterId: Int) async throws -> ChapterInfo {
        try await send("GET", "/api/Reader/chapter-info", query: ["chapterId": "\(chapterId)", "extractPdf": "true"])
    }

    func progress(chapterId: Int) async throws -> ProgressBody {
        try await send("GET", "/api/Reader/get-progress", query: ["chapterId": "\(chapterId)"])
    }

    func saveProgress(_ body: ProgressBody) async throws {
        try await sendNoContent("POST", "/api/Reader/progress", body: body)
    }

    /// Returns the next chapter id, or nil when this is the last one.
    func nextChapter(seriesId: Int, volumeId: Int, chapterId: Int) async throws -> Int? {
        let id: Int = try await send("GET", "/api/Reader/next-chapter",
                                     query: ["seriesId": "\(seriesId)", "volumeId": "\(volumeId)",
                                             "currentChapterId": "\(chapterId)"])
        return id > 0 ? id : nil
    }

    /// Returns the previous chapter id, or nil when this is the first one.
    func previousChapter(seriesId: Int, volumeId: Int, chapterId: Int) async throws -> Int? {
        let id: Int = try await send("GET", "/api/Reader/prev-chapter",
                                     query: ["seriesId": "\(seriesId)", "volumeId": "\(volumeId)",
                                             "currentChapterId": "\(chapterId)"])
        return id > 0 ? id : nil
    }

    func bookInfo(chapterId: Int) async throws -> BookInfo {
        try await send("GET", "/api/Book/\(chapterId)/book-info")
    }

    func bookTOC(chapterId: Int) async throws -> [BookTOCItem] {
        try await send("GET", "/api/Book/\(chapterId)/chapters")
    }

    /// One EPUB section as HTML. Resource links are rewritten to point at this server address,
    /// so they work no matter which address Kavita thinks it is on.
    func bookPageHTML(chapterId: Int, page: Int) async throws -> String {
        let data = try await raw("GET", "/api/Book/\(chapterId)/book-page", query: ["page": "\(page)"],
                                 accept: "text/plain")
        var text = String(decoding: data, as: UTF8.self)
        // Kavita may JSON-encode the string depending on the Accept header; unwrap if so.
        if text.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: data) {
            text = decoded
        }
        return rewriteResourceLinks(text)
    }

    func rewriteResourceLinks(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?:https?:)?//[^"'\s)]+?/api/book/"#,
                                                   options: [.caseInsensitive]) else { return html }
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast())
                                                         : baseURL.absoluteString
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range,
                                              withTemplate: NSRegularExpression.escapedTemplate(for: base + "/api/book/"))
    }

    func pageImageData(chapterId: Int, page: Int) async throws -> Data {
        try await raw("GET", "/api/Reader/image",
                      query: ["chapterId": "\(chapterId)", "page": "\(page)", "extractPdf": "true",
                              "apiKey": apiKey], // Kavita only reads the key from the URL here
                      accept: "image/*")
    }

    /// Fetches an absolute URL (used for EPUB images, which carry their own apiKey).
    func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        addClientHeaders(&req)
        let (data, response) = try await Self.session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw KavitaError.http(code, "") }
        return data
    }

    // MARK: Read status

    func markSeries(_ seriesId: Int, read: Bool) async throws {
        try await sendNoContent("POST", read ? "/api/Reader/mark-read" : "/api/Reader/mark-unread",
                                body: SeriesIdBody(seriesId: seriesId))
    }

    func markVolume(seriesId: Int, volumeId: Int, read: Bool) async throws {
        try await sendNoContent("POST", read ? "/api/Reader/mark-volume-read" : "/api/Reader/mark-volume-unread",
                                body: VolumeReadBody(seriesId: seriesId, volumeId: volumeId))
    }

    func markChapter(seriesId: Int, chapter: Chapter, read: Bool) async throws {
        if read {
            try await sendNoContent("POST", "/api/Reader/mark-chapter-read",
                                    body: ChapterReadBody(seriesId: seriesId, chapterId: chapter.id))
        } else {
            // Kavita has no "mark chapter unread"; resetting progress to page 0 does the same thing.
            let info = try await chapterInfo(chapterId: chapter.id)
            try await saveProgress(ProgressBody(volumeId: info.volumeId, chapterId: chapter.id, pageNum: 0,
                                                seriesId: seriesId, libraryId: info.libraryId, bookScrollId: nil))
        }
    }

    // MARK: Reading lists

    func readingLists() async throws -> [ReadingList] {
        try await send("POST", "/api/ReadingList/lists",
                       query: ["PageNumber": "1", "PageSize": "200", "includePromoted": "true",
                               "sortByLastModified": "true"],
                       body: Optional<String>.none)
    }

    func readingListItems(_ listId: Int) async throws -> [ReadingListItem] {
        try await send("GET", "/api/ReadingList/items", query: ["readingListId": "\(listId)"])
    }

    func createReadingList(title: String) async throws -> ReadingList {
        try await send("POST", "/api/ReadingList/create", body: CreateListBody(title: title))
    }

    func addToReadingList(_ listId: Int, _ target: ListTarget) async throws {
        switch target {
        case .series(let seriesId):
            try await sendNoContent("POST", "/api/ReadingList/update-by-series",
                                    body: AddSeriesBody(seriesId: seriesId, readingListId: listId))
        case .volume(let seriesId, let volumeId):
            try await sendNoContent("POST", "/api/ReadingList/update-by-volume",
                                    body: AddVolumeBody(volumeId: volumeId, seriesId: seriesId, readingListId: listId))
        case .chapter(let seriesId, let chapterId):
            try await sendNoContent("POST", "/api/ReadingList/update-by-chapter",
                                    body: AddChapterBody(chapterId: chapterId, seriesId: seriesId, readingListId: listId))
        }
    }

    func removeFromReadingList(_ item: ReadingListItem) async throws {
        try await sendNoContent("POST", "/api/ReadingList/delete-item",
                                body: ListPositionBody(readingListId: item.readingListId, readingListItemId: item.id,
                                                       fromPosition: item.order, toPosition: item.order))
    }

    func moveInReadingList(_ item: ReadingListItem, to position: Int) async throws {
        try await sendNoContent("POST", "/api/ReadingList/update-position",
                                body: ListPositionBody(readingListId: item.readingListId, readingListItemId: item.id,
                                                       fromPosition: item.order, toPosition: position))
    }

    func removeReadItems(_ listId: Int) async throws {
        _ = try await raw("POST", "/api/ReadingList/remove-read", query: ["readingListId": "\(listId)"])
    }

    func deleteReadingList(_ listId: Int) async throws {
        _ = try await raw("DELETE", "/api/ReadingList", query: ["readingListId": "\(listId)"])
    }

    func nextInList(chapterId: Int, listId: Int) async throws -> Int? {
        let id: Int = try await send("GET", "/api/ReadingList/next-chapter",
                                     query: ["currentChapterId": "\(chapterId)", "readingListId": "\(listId)"])
        return id > 0 ? id : nil
    }

    func previousInList(chapterId: Int, listId: Int) async throws -> Int? {
        let id: Int = try await send("GET", "/api/ReadingList/prev-chapter",
                                     query: ["currentChapterId": "\(chapterId)", "readingListId": "\(listId)"])
        return id > 0 ? id : nil
    }

    func readingListCoverURL(_ listId: Int) -> URL? {
        makeURL("/api/Image/readinglist-cover", ["readingListId": "\(listId)", "apiKey": apiKey])
    }

    // MARK: Want to Read

    func wantToRead() async throws -> [Series] {
        try await send("POST", "/api/want-to-read/v2", query: ["PageNumber": "1", "PageSize": "200"],
                       body: SeriesFilter.make(libraryId: nil, search: nil, sort: .name))
    }

    func isWantToRead(_ seriesId: Int) async throws -> Bool {
        try await send("GET", "/api/want-to-read", query: ["seriesId": "\(seriesId)"])
    }

    func setWantToRead(_ seriesId: Int, _ on: Bool) async throws {
        try await sendNoContent("POST", on ? "/api/want-to-read/add-series" : "/api/want-to-read/remove-series",
                                body: SeriesIdsBody(seriesIds: [seriesId]))
    }

    // MARK: URLs for image views

    func seriesCoverURL(_ seriesId: Int) -> URL? {
        makeURL("/api/Image/series-cover", ["seriesId": "\(seriesId)", "apiKey": apiKey])
    }

    func volumeCoverURL(_ volumeId: Int) -> URL? {
        makeURL("/api/Image/volume-cover", ["volumeId": "\(volumeId)", "apiKey": apiKey])
    }

    func chapterCoverURL(_ chapterId: Int) -> URL? {
        makeURL("/api/Image/chapter-cover", ["chapterId": "\(chapterId)", "apiKey": apiKey])
    }

    // MARK: Plumbing

    private func makeURL(_ path: String, _ query: [String: String] = [:]) -> URL? {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { return nil }
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url
    }

    private func makeRequest(_ method: String, _ path: String, query: [String: String], body: Data?,
                             accept: String, authenticated: Bool) throws -> URLRequest {
        guard let url = makeURL(path, query) else { throw KavitaError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if authenticated { req.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        addClientHeaders(&req)
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Browsing calls whose answers are saved for offline use. Reader calls are left out on purpose,
    /// so opening something that isn't downloaded says so instead of failing page by page.
    private static let cachedPosts: Set<String> = [
        "/api/Series/all-v2", "/api/Series/on-deck", "/api/Series/recently-added-v2",
        "/api/Series/recently-updated-series", "/api/ReadingList/lists", "/api/want-to-read/v2",
    ]

    private static func isCacheable(_ method: String, _ path: String) -> Bool {
        if method == "POST" { return cachedPosts.contains(path) }
        guard method == "GET" else { return false }
        if path == "/api/Reader/continue-point" { return true }
        return !path.hasPrefix("/api/Reader/") && !path.hasPrefix("/api/Book/")
    }

    private func raw(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil,
                     accept: String = "application/json", authenticated: Bool = true) async throws -> Data {
        let cacheKey = Self.isCacheable(method, path)
            ? ResponseCache.key(method: method, path: path, query: query, body: body) : nil
        do {
            let req = try makeRequest(method, path, query: query, body: body, accept: accept,
                                      authenticated: authenticated)
            let (data, response) = try await Self.session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw KavitaError.http(code, String(decoding: data, as: UTF8.self))
            }
            ConnectionStatus.report(offline: false)
            if let cacheKey { ResponseCache.store(data, key: cacheKey) }
            return data
        } catch {
            if Self.isOffline(error) {
                ConnectionStatus.report(offline: true)
                if let cacheKey, let saved = ResponseCache.load(key: cacheKey) { return saved }
            }
            throw error
        }
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String] = [:],
                                                  body: B?, authenticated: Bool = true) async throws -> T {
        let encoded = try body.map { try JSONEncoder().encode($0) }
        let data = try await raw(method, path, query: query, body: encoded, authenticated: authenticated)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(method, path, query: query, body: Optional<String>.none)
    }

    private func sendNoContent<B: Encodable>(_ method: String, _ path: String, body: B) async throws {
        _ = try await raw(method, path, body: try JSONEncoder().encode(body))
    }
}
