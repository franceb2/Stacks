import Foundation

// MARK: - Kavita data models
// Only the fields the app uses are decoded. Field names match Kavita 0.9.x JSON.

struct LoginResponse: Decodable {
    let username: String
    let apiKey: String?
}

struct Library: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: Int

    /// Kavita LibraryType: 0 Manga, 1 Comic, 2 Book, 3 Image, 4 Light Novel, 5 Comic (ComicVine)
    var systemImage: String {
        switch type {
        case 0: return "book.closed"
        case 1, 5: return "bubble.left.and.bubble.right"
        case 2, 4: return "books.vertical"
        default: return "photo.on.rectangle"
        }
    }

    var isComic: Bool { type == 1 || type == 5 }
}

struct Series: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let pages: Int
    let pagesRead: Int
    let format: Int
    let libraryId: Int
    let libraryName: String?

    var progress: Double { pages > 0 ? min(1, Double(pagesRead) / Double(pages)) : 0 }
    var isRead: Bool { pages > 0 && pagesRead >= pages }
    var isUnread: Bool { pagesRead == 0 }
}

/// Entry in Kavita's "Recently Updated Series" list.
struct GroupedSeries: Decodable, Identifiable, Hashable {
    let seriesId: Int
    let seriesName: String
    let libraryId: Int
    let count: Int
    let format: Int
    var id: Int { seriesId }
}

struct Volume: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let number: Int?
    let minNumber: Double?
    let pages: Int
    let pagesRead: Int
    let chapters: [Chapter]?

    var isRead: Bool { pages > 0 && pagesRead >= pages }
    var progress: Double { pages > 0 ? min(1, Double(pagesRead) / Double(pages)) : 0 }

    var displayName: String {
        if let name, !name.isEmpty, Double(name) == nil { return name }
        if let minNumber, minNumber > -1000 {
            let n = minNumber.rounded() == minNumber ? String(Int(minNumber)) : String(minNumber)
            return "Volume \(n)"
        }
        return "Volume"
    }
}

struct Chapter: Codable, Identifiable, Hashable {
    let id: Int
    let range: String?
    let number: String?
    let title: String?
    let titleName: String?
    let pages: Int
    let pagesRead: Int
    let isSpecial: Bool
    let volumeId: Int
    let sortOrder: Double?

    var isRead: Bool { pages > 0 && pagesRead >= pages }
    var isStarted: Bool { pagesRead > 0 && !isRead }
    var progress: Double { pages > 0 ? min(1, Double(pagesRead) / Double(pages)) : 0 }

    /// Kavita marks a file that is a whole volume with the placeholder range "-100000".
    var isWholeVolume: Bool { range?.hasPrefix("-") ?? false }

    var displayName: String {
        if let titleName, !titleName.isEmpty { return titleName }
        if isWholeVolume { return "Full volume" }
        if let title, !title.isEmpty { return title }
        if let range, !range.isEmpty { return "Chapter \(range)" }
        return "Chapter"
    }
}

struct SeriesDetail: Decodable {
    let specials: [Chapter]
    let chapters: [Chapter]
    let volumes: [Volume]
    let libraryType: Int
    let unreadCount: Int
    let totalCount: Int

    /// Comics call their units "issues"; everything else uses "chapters".
    var chapterNoun: String { (libraryType == 1 || libraryType == 5) ? "Issues" : "Chapters" }
    var isBookLibrary: Bool { libraryType == 2 || libraryType == 4 }

    /// Chapters not already shown inside a volume (Kavita repeats them in the flat list).
    var looseChapters: [Chapter] {
        let inVolumes = Set(volumes.flatMap { ($0.chapters ?? []).map(\.id) })
        return chapters.filter { !inVolumes.contains($0.id) }
    }

    /// Every chapter in reading order, without duplicates.
    var allChapters: [Chapter] {
        let sortedVolumes = volumes.sorted { ($0.minNumber ?? 0) < ($1.minNumber ?? 0) }
        var candidates: [Chapter] = []
        for volume in sortedVolumes { candidates.append(contentsOf: volume.chapters ?? []) }
        candidates.append(contentsOf: chapters)
        candidates.append(contentsOf: specials)
        var seen = Set<Int>()
        var out: [Chapter] = []
        for c in candidates where !seen.contains(c.id) {
            seen.insert(c.id)
            out.append(c)
        }
        return out
    }
}

struct SeriesMetadata: Decodable {
    struct Tag: Decodable, Hashable { let title: String }
    struct Person: Decodable, Hashable { let name: String }

    let summary: String?
    let genres: [Tag]?
    let tags: [Tag]?
    let writers: [Person]?
    let publishers: [Person]?
    let releaseYear: Int?
    let publicationStatus: Int?

    var statusText: String? {
        switch publicationStatus {
        case 0: return "Ongoing"
        case 1: return "Hiatus"
        case 2: return "Completed"
        case 3: return "Cancelled"
        case 4: return "Ended"
        default: return nil
        }
    }
}

struct ChapterInfo: Codable {
    let pages: Int
    let seriesFormat: Int
    let seriesId: Int
    let libraryId: Int
    let volumeId: Int
    let seriesName: String?
    let title: String?
    let subtitle: String?
}

/// Kavita MangaFormat
enum MangaFormat: Int {
    case image = 0, archive = 1, unknown = 2, epub = 3, pdf = 4
}

struct ProgressBody: Codable {
    var volumeId: Int
    var chapterId: Int
    var pageNum: Int
    var seriesId: Int
    var libraryId: Int
    var bookScrollId: String?
}

struct BookInfo: Decodable {
    let pages: Int
    let bookTitle: String?
}

struct BookTOCItem: Decodable, Identifiable, Hashable {
    let title: String?
    let page: Int
    let children: [BookTOCItem]?
    var id: String { "\(page)-\(title ?? "")" }
}

// MARK: - Request bodies

enum SeriesSort: Int, CaseIterable, Identifiable {
    case name = 1, added = 2, updated = 4, progress = 7
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .name: return "Name"
        case .added: return "Recently added"
        case .updated: return "Recently updated"
        case .progress: return "Reading progress"
        }
    }
    /// Newest-first for dates and progress, A–Z for names.
    var ascending: Bool { self == .name }
}

struct SeriesFilter: Encodable {
    struct Statement: Encodable {
        let comparison: Int
        let field: Int
        let value: String
    }
    struct Sort: Encodable {
        let sortField: Int
        let isAscending: Bool
    }
    var id = 0
    var statements: [Statement]
    var combination = 1 // And
    var sortOptions = Sort(sortField: 1, isAscending: true)
    var limitTo = 0

    static func make(libraryId: Int?, search: String?, sort: SeriesSort = .name) -> SeriesFilter {
        var statements: [Statement] = []
        if let libraryId {
            statements.append(Statement(comparison: 0, field: 19, value: String(libraryId))) // Libraries == id
        }
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            statements.append(Statement(comparison: 7, field: 1, value: search)) // SeriesName Matches
        }
        return SeriesFilter(statements: statements,
                            sortOptions: Sort(sortField: sort.rawValue, isAscending: sort.ascending))
    }
}

struct SeriesIdBody: Encodable { let seriesId: Int }
struct VolumeReadBody: Encodable { let seriesId: Int; let volumeId: Int }
struct ChapterReadBody: Encodable { let seriesId: Int; let chapterId: Int }
struct LoginBody: Encodable { let username: String; let password: String }
