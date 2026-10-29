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
/// Image and file URLs carry it as `?apiKey=` so they also work in image views and web views.
struct KavitaClient {
    let baseURL: URL
    let apiKey: String

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

    func series(libraryId: Int, search: String?, page: Int, pageSize: Int = 60) async throws -> [Series] {
        try await send("POST", "/api/Series/all-v2", query: ["PageNumber": "\(page)", "PageSize": "\(pageSize)"],
                       body: SeriesFilter.library(libraryId, search: search))
    }

    func onDeck() async throws -> [Series] {
        try await send("POST", "/api/Series/on-deck", query: ["PageNumber": "1", "PageSize": "30"],
                       body: Optional<String>.none)
    }

    func series(id: Int) async throws -> Series {
        try await send("GET", "/api/Series/\(id)")
    }

    func seriesDetail(id: Int) async throws -> SeriesDetail {
        try await send("GET", "/api/Series/series-detail", query: ["seriesId": "\(id)"])
    }

    func continuePoint(seriesId: Int) async throws -> Chapter {
        try await send("GET", "/api/Reader/continue-point", query: ["seriesId": "\(seriesId)"])
    }

    // MARK: Reading

    func chapterInfo(chapterId: Int) async throws -> ChapterInfo {
        try await send("GET", "/api/Reader/chapter-info", query: ["chapterId": "\(chapterId)"])
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

    func bookInfo(chapterId: Int) async throws -> BookInfo {
        try await send("GET", "/api/Book/\(chapterId)/book-info")
    }

    func bookTOC(chapterId: Int) async throws -> [BookTOCItem] {
        try await send("GET", "/api/Book/\(chapterId)/chapters")
    }

    func bookPageHTML(chapterId: Int, page: Int) async throws -> String {
        let data = try await raw("GET", "/api/Book/\(chapterId)/book-page", query: ["page": "\(page)"],
                                 accept: "text/plain")
        let text = String(decoding: data, as: UTF8.self)
        // Kavita may JSON-encode the string depending on the Accept header; unwrap if so.
        if text.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return text
    }

    func pdfData(chapterId: Int) async throws -> Data {
        try await raw("GET", "/api/Reader/pdf", query: ["chapterId": "\(chapterId)"], accept: "application/pdf")
    }

    func pageImageData(chapterId: Int, page: Int) async throws -> Data {
        try await raw("GET", "/api/Reader/image", query: ["chapterId": "\(chapterId)", "page": "\(page)"],
                      accept: "image/*")
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

    // MARK: URLs for image views

    func seriesCoverURL(_ seriesId: Int) -> URL? {
        makeURL("/api/Image/series-cover", ["seriesId": "\(seriesId)", "apiKey": apiKey])
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
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func raw(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil,
                     accept: String = "application/json", authenticated: Bool = true) async throws -> Data {
        let req = try makeRequest(method, path, query: query, body: body, accept: accept, authenticated: authenticated)
        let (data, response) = try await Self.session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw KavitaError.http(code, String(decoding: data, as: UTF8.self))
        }
        return data
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
