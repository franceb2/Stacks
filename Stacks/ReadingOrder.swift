import Foundation
import SwiftUI

/// A curated reading order bundled with the app (for example Spawn and its essential side series).
/// It's matched against your Kavita library and shown as a tab on the series page; no Kavita reading list
/// is created, and your files aren't changed.
struct ReadingOrder: Decodable, Identifiable {
    struct Entry: Decodable {
        let series: String
        let label: String
        let kind: String        // main, spinoff, oneshot
        let section: String     // main, universe
        let number: String?
    }

    let id: String
    let title: String
    let credit: String
    let note: String?
    let hosts: [String]
    let entries: [Entry]
    let years: [String: Int]?

    /// Which year's run an entry means, when the library has several series with the same name.
    func yearHint(_ e: Entry) -> Int? {
        years?["\(e.series)|\(e.section)"] ?? years?[e.series]
    }
}

struct ResolvedEntry: Identifiable {
    let index: Int
    let entry: ReadingOrder.Entry
    let seriesId: Int?
    let seriesName: String?
    let chapter: Chapter?
    var id: Int { index }
    var inLibrary: Bool { chapter != nil }
}

/// Matches titles loosely: case, punctuation, "&"/"and", "The", word order and years don't matter.
enum TitleKey {
    static func make(_ name: String) -> String {
        var s = name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s", with: "s")
        s = s.replacingOccurrences(of: #"\((19|20)\d\d\)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bvol(ume)?\.?\s*\d+\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        let words = s.split(separator: " ").map(String.init).filter { $0 != "the" && !$0.isEmpty }
        return words.sorted().joined(separator: " ")
    }

    static func year(in name: String) -> Int? {
        guard let r = name.range(of: #"\((19|20)\d\d\)"#, options: .regularExpression) else { return nil }
        return Int(name[r].dropFirst().dropLast())
    }

    /// "001", "1", "1.0" all become 1.
    static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }
}

@MainActor
final class ReadingOrderStore: ObservableObject {
    static let shared = ReadingOrderStore()

    let orders: [ReadingOrder]
    @Published private(set) var resolved: [String: [ResolvedEntry]] = [:]
    @Published private(set) var loading: Set<String> = []

    private var lastResolved: [String: Date] = [:]

    private init() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        orders = urls.compactMap { try? JSONDecoder().decode(ReadingOrder.self, from: Data(contentsOf: $0)) }
            .sorted { $0.title < $1.title }
    }

    /// Reading orders that include this series.
    func orders(for seriesName: String) -> [ReadingOrder] {
        let key = TitleKey.make(seriesName)
        return orders.filter { order in order.entries.contains { TitleKey.make($0.series) == key } }
    }

    /// True when this series is the main one for the order (the tab opens first there).
    func isHost(_ order: ReadingOrder, seriesName: String) -> Bool {
        let key = TitleKey.make(seriesName)
        return order.hosts.contains { TitleKey.make($0) == key }
    }

    /// Chapter ids in reading order, for the reader's next/previous.
    func chapterIds(_ order: ReadingOrder) -> [Int] {
        (resolved[order.id] ?? []).compactMap { $0.chapter?.id }
    }

    /// Finds every entry in the library. Runs again at most every few minutes unless forced.
    func resolve(_ order: ReadingOrder, client: KavitaClient, force: Bool = false) async {
        if loading.contains(order.id) { return }
        if !force, let last = lastResolved[order.id], Date().timeIntervalSince(last) < 300 { return }
        loading.insert(order.id)
        defer { loading.remove(order.id) }

        // 1. Everything in the library, indexed by loose title.
        var library: [Series] = []
        var page = 1
        while page < 200, let batch = try? await client.series(libraryId: nil, search: "", sort: .name, page: page) {
            library.append(contentsOf: batch)
            if batch.count < 60 { break }
            page += 1
        }
        guard !library.isEmpty else { return }
        var byKey: [String: [Series]] = [:]
        for s in library { byKey[TitleKey.make(s.name), default: []].append(s) }

        // 2. Pick the library series for each title in the order (using year hints when there are several).
        var yearCache: [Int: Int] = [:]
        func year(of s: Series) async -> Int? {
            if let y = TitleKey.year(in: s.name) { return y }
            if let y = yearCache[s.id] { return y }
            let y = (try? await client.metadata(seriesId: s.id))?.releaseYear
            if let y, y > 0 { yearCache[s.id] = y; return y }
            return nil
        }
        var chosen: [String: Series] = [:]  // "series|section" -> library series
        for e in order.entries {
            let k = "\(e.series)|\(e.section)"
            if chosen[k] != nil { continue }
            guard let candidates = byKey[TitleKey.make(e.series)], !candidates.isEmpty else { continue }
            if candidates.count == 1 { chosen[k] = candidates[0]; continue }
            var dated: [(Series, Int?)] = []
            for c in candidates { dated.append((c, await year(of: c))) }
            if let hint = order.yearHint(e) {
                chosen[k] = dated.min { abs(($0.1 ?? 0) - hint) < abs(($1.1 ?? 0) - hint) }?.0
            } else {
                let sorted = dated.sorted { ($0.1 ?? 0) < ($1.1 ?? 0) }
                chosen[k] = (e.section == "universe" ? sorted.last : sorted.first)?.0
            }
        }

        // 3. Each chosen series' issues, by number.
        var details: [Int: SeriesDetail] = [:]
        let ids = Array(Set(chosen.values.map(\.id)))
        var i = 0
        while i < ids.count {
            let batch = Array(ids[i..<min(i + 4, ids.count)])
            i += batch.count
            let results = await withTaskGroup(of: (Int, SeriesDetail?).self) { group -> [(Int, SeriesDetail?)] in
                for id in batch { group.addTask { (id, try? await client.seriesDetail(id: id)) } }
                var out: [(Int, SeriesDetail?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, d) in results { if let d { details[id] = d } }
        }

        // 4. Line them up.
        var out: [ResolvedEntry] = []
        for (index, e) in order.entries.enumerated() {
            let s = chosen["\(e.series)|\(e.section)"]
            var chapter: Chapter?
            if let s, let d = details[s.id] {
                let chapters = d.allChapters.filter { !$0.isWholeVolume }
                if let n = TitleKey.number(e.number) {
                    chapter = chapters.first {
                        TitleKey.number($0.number) == n || TitleKey.number($0.range) == n
                    }
                } else {
                    chapter = chapters.first ?? d.allChapters.first  // one-shot
                }
            }
            out.append(ResolvedEntry(index: index, entry: e, seriesId: s?.id, seriesName: s?.name, chapter: chapter))
        }
        resolved[order.id] = out
        lastResolved[order.id] = Date()
    }
}

// MARK: - Tab content

/// The Reading order tab on a series page: the whole order, your progress through it, and a Continue button.
struct ReadingOrderSection: View {
    let order: ReadingOrder
    let client: KavitaClient
    let hideRead: Bool
    let open: (Int, [Int]) -> Void   // chapter id, the order's chapter ids

    @ObservedObject private var store = ReadingOrderStore.shared
    @EnvironmentObject private var downloads: Downloads
    @AppStorage("orderShowMissing") private var showMissing = false

    private var entries: [ResolvedEntry] { store.resolved[order.id] ?? [] }
    private var matched: [ResolvedEntry] { entries.filter(\.inLibrary) }
    private var readCount: Int { matched.filter { $0.chapter?.isRead == true }.count }
    private var nextUp: ResolvedEntry? { matched.first { $0.chapter?.isRead != true } }

    private var visible: [ResolvedEntry] {
        entries.filter { e in
            if !e.inLibrary { return showMissing }
            if hideRead, e.chapter?.isRead == true { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if store.loading.contains(order.id) && entries.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Matching the reading order with your library…").font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
            }
            LazyVStack(spacing: 0) {
                ForEach(visible) { e in row(e) }
            }
            if !entries.isEmpty && visible.isEmpty {
                Text(hideRead ? "You've read everything here that's in your library." : "Nothing to show.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 16)
            }
        }
        .task { await store.resolve(order, client: client) }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await store.resolve(order, client: client, force: true) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.title).font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Menu {
                    Toggle("Show issues not in my library", isOn: $showMissing)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.resolve(order, client: client, force: true) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
                }
            }
            Text(order.credit).font(.caption).foregroundStyle(Theme.muted)
            if !entries.isEmpty {
                Text("\(matched.count) of \(entries.count) in your library · \(readCount) read")
                    .font(.caption).foregroundStyle(Theme.muted)
                ProgressView(value: matched.isEmpty ? 0 : Double(readCount) / Double(matched.count))
                    .tint(Theme.primary)
            }
            if let next = nextUp, let chapter = next.chapter {
                Button {
                    open(chapter.id, store.chapterIds(order))
                } label: {
                    Label(readCount == 0 ? "Start: \(shortLabel(next))" : "Continue: \(shortLabel(next))",
                          systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func shortLabel(_ e: ResolvedEntry) -> String {
        e.entry.label.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? e.entry.label
    }

    private func row(_ e: ResolvedEntry) -> some View {
        let chapter = e.chapter
        return Button {
            if let chapter { open(chapter.id, store.chapterIds(order)) }
        } label: {
            HStack(spacing: 12) {
                Text("\(e.index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, alignment: .trailing)
                Group {
                    if let chapter {
                        CoverImage(url: client.chapterCoverURL(chapter.id),
                                   localFile: downloads.coverURL(chapterId: chapter.id))
                    } else {
                        Rectangle().fill(Theme.card)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .overlay(Image(systemName: "questionmark").font(.caption).foregroundStyle(Theme.muted))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 34)
                .opacity(chapter?.isRead == true ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(e.entry.label)
                        .font(.subheadline)
                        .foregroundStyle(e.inLibrary ? (chapter?.isRead == true ? Theme.muted : Theme.text) : Theme.muted)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if e.entry.kind == "oneshot" {
                            tag("One-shot")
                        } else if e.entry.kind == "spinoff" {
                            tag(e.entry.series)
                        }
                        if !e.inLibrary {
                            Text("Not in your library").font(.caption2).foregroundStyle(Theme.muted)
                        } else if let chapter, chapter.isStarted {
                            Text("Page \(chapter.pagesRead + 1) of \(chapter.pages)")
                                .font(.caption2).foregroundStyle(Theme.primary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if chapter?.isRead == true {
                    Image(systemName: "eye.fill").font(.caption).foregroundStyle(Theme.muted)
                } else if let chapter, downloads.items[chapter.id]?.isComplete == true {
                    Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chapter == nil)
        .contextMenu {
            if let chapter, let seriesId = e.seriesId {
                Button("Read", systemImage: "book") { open(chapter.id, store.chapterIds(order)) }
                Button("Mark as read", systemImage: "checkmark.circle") { mark(chapter, seriesId: seriesId, read: true) }
                Button("Mark as unread", systemImage: "circle") { mark(chapter, seriesId: seriesId, read: false) }
                Button("Mark everything before this as read", systemImage: "checkmark.circle.badge.questionmark") {
                    markBefore(e)
                }
                Button("Download", systemImage: "arrow.down.circle") {
                    downloads.start(client: client, chapterId: chapter.id, seriesId: seriesId,
                                    seriesName: e.seriesName ?? e.entry.series, title: e.entry.label, range: .all)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Theme.primary.opacity(0.15), in: Capsule())
            .lineLimit(1)
    }

    private func mark(_ chapter: Chapter, seriesId: Int, read: Bool) {
        Task {
            downloads.markFinished([chapter.id], finished: read)
            try? await client.markChapter(seriesId: seriesId, chapter: chapter, read: read)
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }
    }

    /// Marks every matched entry earlier in the order as read, series by series.
    private func markBefore(_ target: ResolvedEntry) {
        let earlier = entries.prefix(target.index).filter { $0.chapter != nil && $0.chapter?.isRead != true }
        var bySeries: [Int: [Int]] = [:]
        for e in earlier { if let s = e.seriesId, let c = e.chapter { bySeries[s, default: []].append(c.id) } }
        Task {
            for (seriesId, ids) in bySeries {
                downloads.markFinished(ids)
                try? await client.markMultiple(seriesId: seriesId, volumeIds: [], chapterIds: ids, read: true)
            }
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }
    }
}
