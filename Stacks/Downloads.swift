import CryptoKit
import Foundation
import UIKit

/// A chapter (issue, volume file, book) saved on the phone, fully or as a page range.
struct DownloadedChapter: Codable, Identifiable {
    let chapterId: Int
    let seriesId: Int
    let seriesName: String
    let title: String
    let info: ChapterInfo
    /// Downloaded page indexes (0-based). For EPUBs these are book sections.
    var pages: [Int]
    var bytes: Int64
    var date: Date
    /// Last page read on this phone, kept so offline reading resumes correctly.
    var lastPage: Int?

    var id: Int { chapterId }
    var totalPages: Int { info.pages }
    var isComplete: Bool { Set(pages).count >= info.pages }
    var isBook: Bool { info.seriesFormat == MangaFormat.epub.rawValue }

    /// "Pages 1–200 of 640" or "All 24 pages"
    var rangeText: String {
        let noun = isBook ? "sections" : "pages"
        if isComplete { return "All \(info.pages) \(noun)" }
        let sorted = pages.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "Nothing yet" }
        let contiguous = last - first + 1 == sorted.count
        let label = isBook ? "Sections" : "Pages"
        if contiguous { return "\(label) \(first + 1)–\(last + 1) of \(info.pages)" }
        return "\(sorted.count) of \(info.pages) \(noun)"
    }
}

enum DownloadRange {
    case all
    case pages(ClosedRange<Int>) // 0-based, inclusive
}

/// Downloads chapters page by page through Kavita's reader API (works for CBZ, CBR, PDF and EPUB),
/// stores them on the phone, and queues reading progress made while offline.
@MainActor
final class Downloads: ObservableObject {
    static let shared = Downloads()

    struct Job: Equatable {
        var title: String
        var seriesName: String
        var done = 0
        var total = 0
        var failed = 0
        var waiting = true
        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    private struct Request {
        let client: KavitaClient
        let chapterId: Int
        let seriesId: Int
        let seriesName: String
        let title: String
        let range: DownloadRange
    }

    @Published private(set) var items: [Int: DownloadedChapter] = [:]
    @Published private(set) var jobs: [Int: Job] = [:]
    @Published private(set) var pending: [Int: ProgressBody] = [:]
    @Published var lastError: String?

    private var queue: [Request] = []
    private var current: (id: Int, task: Task<Void, Never>)?

    private let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var pendingURL: URL { root.appendingPathComponent("pending.json") }

    private init() {
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([DownloadedChapter].self, from: data) {
            items = Dictionary(uniqueKeysWithValues: list.map { ($0.chapterId, $0) })
        }
        if let data = try? Data(contentsOf: pendingURL),
           let list = try? JSONDecoder().decode([ProgressBody].self, from: data) {
            pending = Dictionary(list.map { ($0.chapterId, $0) }, uniquingKeysWith: { _, b in b })
        }
    }

    // MARK: Queries

    func folder(_ chapterId: Int) -> URL { root.appendingPathComponent("\(chapterId)", isDirectory: true) }

    func imageURL(chapterId: Int, page: Int) -> URL? {
        guard items[chapterId]?.pages.contains(page) == true else { return nil }
        let url = folder(chapterId).appendingPathComponent("p\(page).img")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func sectionURL(chapterId: Int, section: Int) -> URL? {
        guard items[chapterId]?.pages.contains(section) == true else { return nil }
        let url = folder(chapterId).appendingPathComponent("s\(section).html")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func coverURL(chapterId: Int) -> URL? {
        let url = folder(chapterId).appendingPathComponent("cover.img")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalBytes: Int64 { items.values.reduce(0) { $0 + $1.bytes } }

    var sortedItems: [DownloadedChapter] {
        items.values.sorted {
            if $0.seriesName != $1.seriesName {
                return $0.seriesName.localizedStandardCompare($1.seriesName) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    // MARK: Downloading

    /// Adds a chapter to the download queue. Chapters download one at a time, 4 pages in parallel.
    func start(client: KavitaClient, chapter: Chapter, seriesId: Int, seriesName: String, title: String,
               range: DownloadRange) {
        guard jobs[chapter.id] == nil else { return }
        jobs[chapter.id] = Job(title: title, seriesName: seriesName)
        queue.append(Request(client: client, chapterId: chapter.id, seriesId: seriesId, seriesName: seriesName,
                             title: title, range: range))
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        let task = Task { [weak self] in
            await self?.run(client: next.client, chapterId: next.chapterId, seriesId: next.seriesId,
                            seriesName: next.seriesName, title: next.title, range: next.range)
            self?.finished(next.chapterId)
        }
        current = (next.chapterId, task)
    }

    private func finished(_ chapterId: Int) {
        if current?.id == chapterId { current = nil }
        jobs[chapterId] = nil
        pump()
    }

    func cancel(_ chapterId: Int) {
        queue.removeAll { $0.chapterId == chapterId }
        if current?.id == chapterId {
            current?.task.cancel()
            current = nil
        }
        jobs[chapterId] = nil
        pump()
    }

    func cancelAll() {
        queue.removeAll()
        current?.task.cancel()
        current = nil
        jobs = [:]
    }

    func delete(_ chapterId: Int) {
        cancel(chapterId)
        try? FileManager.default.removeItem(at: folder(chapterId))
        items[chapterId] = nil
        save()
    }

    func deleteAll() {
        cancelAll()
        for id in Array(items.keys) { try? FileManager.default.removeItem(at: folder(id)) }
        items = [:]
        save()
    }

    private func run(client: KavitaClient, chapterId: Int, seriesId: Int, seriesName: String, title: String,
                     range: DownloadRange) async {
        let dir = folder(chapterId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let info: ChapterInfo
        do {
            info = try await client.chapterInfo(chapterId: chapterId)
        } catch {
            lastError = "Couldn't start the download: \(error.localizedDescription)"
            return
        }

        let all = 0..<max(info.pages, 0)
        var wanted: [Int]
        switch range {
        case .all: wanted = Array(all)
        case .pages(let r): wanted = Array(all.clamped(to: r.lowerBound..<(r.upperBound + 1)))
        }
        var entry = items[chapterId] ?? DownloadedChapter(chapterId: chapterId, seriesId: seriesId,
                                                          seriesName: seriesName, title: title, info: info,
                                                          pages: [], bytes: 0, date: Date(), lastPage: nil)
        let have = Set(entry.pages)
        wanted.removeAll { have.contains($0) }
        jobs[chapterId]?.total = wanted.count
        jobs[chapterId]?.waiting = false

        // Cover for the Downloads list, so it shows offline.
        if coverURL(chapterId: chapterId) == nil, let url = client.chapterCoverURL(chapterId),
           let data = try? await client.fetch(url) {
            try? data.write(to: dir.appendingPathComponent("cover.img"))
            entry.bytes += Int64(data.count)
        }
        items[chapterId] = entry
        save()

        let isBook = info.seriesFormat == MangaFormat.epub.rawValue
        var index = 0
        let parallel = 4
        while index < wanted.count {
            if Task.isCancelled { break }
            let batch = Array(wanted[index..<min(index + parallel, wanted.count)])
            index += batch.count
            let results = await withTaskGroup(of: (Int, Int64?).self) { group -> [(Int, Int64?)] in
                for page in batch {
                    group.addTask {
                        let bytes: Int64?
                        if isBook {
                            bytes = try? await Self.saveSection(client: client, chapterId: chapterId,
                                                                section: page, dir: dir)
                        } else {
                            bytes = try? await Self.savePage(client: client, chapterId: chapterId,
                                                             page: page, dir: dir)
                        }
                        return (page, bytes)
                    }
                }
                var out: [(Int, Int64?)] = []
                for await r in group { out.append(r) }
                return out
            }
            if Task.isCancelled { break }
            guard var job = jobs[chapterId] else { break }
            for (page, bytes) in results {
                job.done += 1
                if let bytes {
                    entry.pages.append(page)
                    entry.bytes += bytes
                } else {
                    job.failed += 1
                }
            }
            entry.pages = Array(Set(entry.pages)).sorted()
            entry.date = Date()
            items[chapterId] = entry
            jobs[chapterId] = job
            if job.failed > 0 && job.failed == job.done {
                lastError = "Downloads are failing. Check that your server is reachable."
                break
            }
        }
        save()
    }

    nonisolated private static func savePage(client: KavitaClient, chapterId: Int, page: Int,
                                             dir: URL) async throws -> Int64 {
        let data = try await client.pageImageData(chapterId: chapterId, page: page)
        try data.write(to: dir.appendingPathComponent("p\(page).img"), options: .atomic)
        return Int64(data.count)
    }

    /// Saves one EPUB section plus the images and styles it uses, with links pointing at the local copies.
    nonisolated private static func saveSection(client: KavitaClient, chapterId: Int, section: Int,
                                                dir: URL) async throws -> Int64 {
        var html = try await client.bookPageHTML(chapterId: chapterId, page: section)
        var bytes: Int64 = 0
        let resDir = dir.appendingPathComponent("res", isDirectory: true)
        try? FileManager.default.createDirectory(at: resDir, withIntermediateDirectories: true)

        let pattern = #"https?://[^"'\s)]+?/api/book/[^"'\s)]*book-resources[^"'\s)]*"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let found = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .compactMap { Range($0.range, in: html).map { String(html[$0]) } }
        for link in Set(found) {
            let real = link.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: real) else { continue }
            let file = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "file" })?.value ?? real
            let ext = (file as NSString).pathExtension.lowercased()
            let digest = SHA256.hash(data: Data(file.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20)
            let name = "\(digest)" + (ext.isEmpty || ext.count > 5 ? "" : ".\(ext)")
            let target = resDir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: target.path) {
                if let data = try? await client.fetch(url) {
                    try? data.write(to: target, options: .atomic)
                    bytes += Int64(data.count)
                }
            }
            html = html.replacingOccurrences(of: link, with: "res/\(name)")
        }
        let data = Data(html.utf8)
        try data.write(to: dir.appendingPathComponent("s\(section).html"), options: .atomic)
        return bytes + Int64(data.count)
    }

    // MARK: Offline progress

    func rememberPage(_ page: Int, chapterId: Int) {
        guard var entry = items[chapterId] else { return }
        entry.lastPage = page
        items[chapterId] = entry
        save()
    }

    func queue(_ body: ProgressBody) {
        pending[body.chapterId] = body
        savePending()
    }

    func clearPending(_ chapterId: Int) {
        guard pending[chapterId] != nil else { return }
        pending[chapterId] = nil
        savePending()
    }

    /// Sends progress saved while offline. Safe to call any time.
    func flush(client: KavitaClient) async {
        for body in Array(pending.values) {
            do {
                try await client.saveProgress(body)
                pending[body.chapterId] = nil
            } catch {
                if KavitaClient.isOffline(error) { break }
                pending[body.chapterId] = nil // server rejected it; don't retry forever
            }
        }
        savePending()
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(Array(items.values)) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(Array(pending.values)) {
            try? data.write(to: pendingURL, options: .atomic)
        }
    }
}

extension Int64 {
    var fileSizeText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
