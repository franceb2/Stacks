import Foundation
import SwiftUI

struct ResolvedEntry: Identifiable {
    let index: Int
    let entry: ReadingOrder.Entry
    let seriesId: Int?
    let seriesName: String?
    let chapter: Chapter?
    var id: Int { index }
    var inLibrary: Bool { chapter != nil }
}

@MainActor
final class ReadingOrderStore: ObservableObject {
    static let shared = ReadingOrderStore()

    @Published private(set) var orders: [ReadingOrder] = []
    @Published private(set) var resolved: [String: [ResolvedEntry]] = [:]
    @Published private(set) var loading: Set<String> = []

    private let bundled: [ReadingOrder]
    private var lastResolved: [String: Date] = [:]
    private var library: [Series] = []
    private var libraryLoaded: Date?

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ReadingOrders", isDirectory: true)
    }

    private init() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        bundled = urls.compactMap { try? JSONDecoder().decode(ReadingOrder.self, from: Data(contentsOf: $0)) }
        reload()
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let mine = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ReadingOrder.self, from: Data(contentsOf: $0)) }
        orders = (bundled + mine).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Saves (or replaces) an order you added.
    func save(_ order: ReadingOrder) throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(order).write(to: Self.folder.appendingPathComponent("\(order.id).json"), options: .atomic)
        lastResolved[order.id] = nil
        resolved[order.id] = nil
        reload()
    }

    func remove(_ order: ReadingOrder) {
        guard order.isUserAdded else { return }
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(order.id).json"))
        resolved[order.id] = nil
        lastResolved[order.id] = nil
        reload()
    }

    /// Reading orders that include this series, or were added on it. The ones hosted here come first.
    func orders(for seriesName: String) -> [ReadingOrder] {
        let key = TitleKey.make(seriesName)
        let matching = orders.filter { order in
            order.hosts.contains { TitleKey.make($0) == key } || order.entries.contains { TitleKey.make($0.series) == key }
        }
        return matching.filter { isHost($0, seriesName: seriesName) } + matching.filter { !isHost($0, seriesName: seriesName) }
    }

    /// Orders added to a shelf, plus orders hosted by any series on it (like Spawn's on a Spawn shelf).
    func orders(forShelf shelfId: String, seriesNames: [String]) -> [ReadingOrder] {
        let keys = Set(seriesNames.map(TitleKey.make))
        let own = orders.filter { $0.hosts.contains("shelf:\(shelfId)") }
        let hosted = orders.filter { o in !own.contains { $0.id == o.id } && o.hosts.contains { keys.contains(TitleKey.make($0)) } }
        return own + hosted
    }

    /// The chapter ids of a reading order that includes this chapter (already-matched orders first, then
    /// orders that mention this series), or nil when it isn't in any.
    func orderIds(containing chapterId: Int, seriesName: String, client: KavitaClient) async -> [Int]? {
        for o in orders(for: seriesName) + orders where chapterIds(o).contains(chapterId) { return chapterIds(o) }
        for o in orders(for: seriesName) {
            await resolve(o, client: client)
            let ids = chapterIds(o)
            if ids.contains(chapterId) { return ids }
        }
        return nil
    }

    /// Entries between this chapter and the next one you have, in the order these ids came from:
    /// the issues the reader is about to skip because they aren't in your library.
    func missingAfter(_ chapterId: Int, orderIds ids: [Int]) -> [String] {
        guard let order = orders.first(where: { chapterIds($0) == ids }) ?? orders.first(where: { chapterIds($0).contains(chapterId) }),
              let entries = resolved[order.id],
              let i = entries.firstIndex(where: { $0.chapter?.id == chapterId }) else { return [] }
        var labels: [String] = []
        for e in entries[(i + 1)...] {
            if e.chapter != nil { break }
            labels.append(e.entry.label)
        }
        return labels
    }

    /// Every series in your library (cached for a few minutes).
    func allSeries(client: KavitaClient, force: Bool = false) async -> [Series] {
        _ = await libraryIndex(client: client, force: force)
        return library
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

    /// After a library scan, the next lookup reloads the series list.
    func invalidateLibrary() {
        libraryLoaded = nil
        lastResolved = [:]
    }

    /// Every series in the library, grouped by loose title. Reused for a few minutes.
    func libraryIndex(client: KavitaClient, force: Bool = false) async -> [String: [Series]] {
        if force || library.isEmpty || Date().timeIntervalSince(libraryLoaded ?? .distantPast) > 600 {
            var all: [Series] = []
            var page = 1
            while page < 200, let batch = try? await client.series(libraryId: nil, search: "", sort: .name, page: page) {
                all.append(contentsOf: batch)
                if batch.count < 60 { break }
                page += 1
            }
            if !all.isEmpty {
                library = all
                libraryLoaded = Date()
            }
        }
        var byKey: [String: [Series]] = [:]
        for s in library { byKey[TitleKey.make(s.name), default: []].append(s) }
        return byKey
    }

    /// Finds every entry in the library. Runs again at most every few minutes unless forced.
    func resolve(_ order: ReadingOrder, client: KavitaClient, force: Bool = false) async {
        if loading.contains(order.id) { return }
        if !force, let last = lastResolved[order.id], Date().timeIntervalSince(last) < 300 { return }
        loading.insert(order.id)
        defer { loading.remove(order.id) }

        // 1. Everything in the library, indexed by loose title.
        let byKey = await libraryIndex(client: client, force: force)
        guard !byKey.isEmpty else { return }

        var details: [Int: SeriesDetail] = [:]
        func fetch(_ ids: [Int]) async {
            let missing = Array(Set(ids)).filter { details[$0] == nil }
            var i = 0
            while i < missing.count {
                let batch = Array(missing[i..<min(i + 4, missing.count)])
                i += batch.count
                let results = await withTaskGroup(of: (Int, SeriesDetail?).self) { group -> [(Int, SeriesDetail?)] in
                    for id in batch { group.addTask { (id, try? await client.seriesDetail(id: id)) } }
                    var out: [(Int, SeriesDetail?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                for (id, d) in results { if let d { details[id] = d } }
            }
        }

        // 2. Pick the library series for each title in the order. When there are several with the same name,
        //    use the year or volume given, else the one that has the most of the issues the order wants.
        var yearCache: [Int: Int] = [:]
        func year(of s: Series) async -> Int? {
            if let y = TitleKey.year(in: s.name) { return y }
            if let y = yearCache[s.id] { return y }
            let y = (try? await client.metadata(seriesId: s.id))?.releaseYear
            if let y, y > 0 { yearCache[s.id] = y; return y }
            return nil
        }
        func groupKey(_ e: ReadingOrder.Entry) -> String {
            // One-shots get their own group, so "Brit (One-Shot)" and "Brit #1" can point at different series.
            "\(e.series)|\(e.section)|\(order.yearHint(e) ?? 0)|\(e.volume ?? 0)|\(e.number == nil ? "oneshot" : "issues")"
        }
        var wanted: [String: Set<Double>] = [:]
        for e in order.entries {
            if let n = TitleKey.number(e.number) { wanted[groupKey(e), default: []].insert(n) }
        }

        // Series named "X One-Shot" / "X (One Shot)", keyed by the title without those words.
        var oneShotSeries: [String: [Series]] = [:]
        for list in byKey.values {
            for series in list where series.name.range(of: "one[- ]?shot", options: [.regularExpression, .caseInsensitive]) != nil {
                let base = series.name.replacingOccurrences(of: "[(\\[]?\\s*one[- ]?shot\\s*[)\\]]?", with: " ",
                                                            options: [.regularExpression, .caseInsensitive])
                oneShotSeries[TitleKey.make(base), default: []].append(series)
            }
        }

        var chosen: [String: Series] = [:]
        for e in order.entries {
            let k = groupKey(e)
            if chosen[k] != nil { continue }
            // A one-shot can also live in its own series named like "Brit One-Shot"; prefer that.
            if e.number == nil, e.volume == nil, let own = oneShotSeries[TitleKey.make(e.series)]?.first {
                chosen[k] = own
                continue
            }
            guard let candidates = byKey[TitleKey.make(e.series)], !candidates.isEmpty else { continue }
            if candidates.count == 1 { chosen[k] = candidates[0]; continue }

            var dated: [(Series, Int?)] = []
            for c in candidates { dated.append((c, await year(of: c))) }
            let byYear = dated.sorted { ($0.1 ?? 0) < ($1.1 ?? 0) }

            if let hint = order.yearHint(e) {
                chosen[k] = dated.min { abs(($0.1 ?? 0) - hint) < abs(($1.1 ?? 0) - hint) }?.0
            } else if let v = e.volume {
                let named = candidates.first {
                    $0.name.range(of: "\\b(vol(ume)?\\.?\\s*|v)\(v)\\b", options: [.regularExpression, .caseInsensitive]) != nil
                }
                let byIndex: Series? = v - 1 < byYear.count ? byYear[max(v - 1, 0)].0 : byYear.last?.0
                chosen[k] = named ?? byIndex
            } else if e.section == "universe" {
                chosen[k] = byYear.last?.0
            } else if let need = wanted[k], !need.isEmpty {
                await fetch(candidates.map(\.id))
                func hits(_ s: Series) -> Int {
                    guard let d = details[s.id] else { return 0 }
                    let have = Set(d.allChapters.compactMap { TitleKey.number($0.number) ?? TitleKey.number($0.range) })
                    return need.intersection(have).count
                }
                func size(_ s: Series) -> Int { details[s.id]?.allChapters.count ?? 0 }
                // Most matching issues wins. On a tie, the bigger run (a one-shot also counts as "#1", so
                // "Brit #1" should land on the ongoing series, not the one-shot), then the oldest.
                chosen[k] = byYear.max { a, b in
                    let ha = hits(a.0), hb = hits(b.0)
                    if ha != hb { return ha < hb }
                    let sa = size(a.0), sb = size(b.0)
                    if sa != sb { return sa < sb }
                    return (a.1 ?? 0) > (b.1 ?? 0)
                }?.0
            } else if e.number == nil {
                // A one-shot: prefer a series that is just one issue, or is named as a one-shot.
                await fetch(candidates.map(\.id))
                let single = byYear.first { details[$0.0.id]?.allChapters.count == 1 }?.0
                let named = candidates.first {
                    $0.name.range(of: "one[- ]?shot", options: [.regularExpression, .caseInsensitive]) != nil
                }
                chosen[k] = named ?? single ?? byYear.first?.0
            } else {
                chosen[k] = byYear.first?.0
            }
        }

        // 3. Each chosen series' issues, by number.
        await fetch(chosen.values.map(\.id))

        // 4. Line them up. Numbered issues first, so a one-shot never takes an issue the order lists by number.
        var picked: [Int: Chapter] = [:]
        var used: Set<Int> = []
        for (index, e) in order.entries.enumerated() {
            guard let s = chosen[groupKey(e)], let d = details[s.id] else { continue }
            let chapters = d.allChapters.filter { !$0.isWholeVolume }
            var chapter: Chapter?
            if let n = TitleKey.number(e.number) {
                chapter = chapters.first { TitleKey.number($0.number) == n || TitleKey.number($0.range) == n }
            } else if let v = e.volume,
                      let volume = d.volumes.first(where: { $0.number == v || $0.minNumber == Double(v) }),
                      let first = volume.chapters?.first {
                chapter = first
            }
            if let chapter {
                picked[index] = chapter
                used.insert(chapter.id)
            }
        }
        for (index, e) in order.entries.enumerated() where picked[index] == nil && e.number == nil {
            guard let s = chosen[groupKey(e)], let d = details[s.id] else { continue }
            let all = d.allChapters
            let free = all.filter { !used.contains($0.id) }
            // Something marked as a one-shot or special, or with no real issue number, before any issue.
            let oneShotLike = free.first { c in
                let text = "\(c.title ?? "") \(c.titleName ?? "") \(c.range ?? "")"
                if text.range(of: "one[- ]?shot", options: [.regularExpression, .caseInsensitive]) != nil { return true }
                if c.isSpecial { return true }
                guard let n = TitleKey.number(c.number) ?? TitleKey.number(c.range) else { return true }
                return n <= 0
            }
            // Otherwise leave it as "not in your library" rather than guess an unrelated issue.
            if let chapter = oneShotLike ?? (all.count == 1 ? free.first : nil) {
                picked[index] = chapter
                used.insert(chapter.id)
            }
        }
        var out: [ResolvedEntry] = []
        for (index, e) in order.entries.enumerated() {
            let s = chosen[groupKey(e)]
            out.append(ResolvedEntry(index: index, entry: e, seriesId: s?.id, seriesName: s?.name, chapter: picked[index]))
        }
        resolved[order.id] = out
        lastResolved[order.id] = Date()
    }
}

// MARK: - Tab content

/// The Reading order tab on a series page: the whole order, your progress through it, and a Continue button.
/// When a series has several orders, a menu switches between them.
struct ReadingOrderSection: View {
    let orders: [ReadingOrder]
    let client: KavitaClient
    let hideRead: Bool
    let open: (Int, [Int]) -> Void   // chapter id, the order's chapter ids
    let addOrder: () -> Void

    @ObservedObject private var store = ReadingOrderStore.shared
    @EnvironmentObject private var downloads: Downloads
    @AppStorage("orderShowMissing") private var showMissing = false
    @AppStorage("selectedReadingOrders") private var selectedRaw = ""
    @State private var confirmRemove = false
    @State private var refreshing = false
    @State private var refreshError: String?

    let seriesKey: String

    init(orders: [ReadingOrder], seriesName: String, client: KavitaClient, hideRead: Bool,
         open: @escaping (Int, [Int]) -> Void, addOrder: @escaping () -> Void) {
        self.orders = orders
        self.client = client
        self.hideRead = hideRead
        self.open = open
        self.addOrder = addOrder
        self.seriesKey = TitleKey.make(seriesName)
    }

    /// The chosen order per series, remembered as "seriesKey=orderId" lines.
    private var selectedId: String? {
        selectedRaw.split(separator: "\n").first { $0.hasPrefix("\(seriesKey)=") }
            .map { String($0.dropFirst(seriesKey.count + 1)) }
    }

    private func select(_ id: String) {
        selectedRaw = Self.remembering(id, seriesKey: seriesKey, in: selectedRaw)
    }

    private static func remembering(_ id: String, seriesKey: String, in raw: String) -> String {
        var lines = raw.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("\(seriesKey)=") }
        lines.append("\(seriesKey)=\(id)")
        return lines.suffix(200).joined(separator: "\n")
    }

    /// Shows this order on the series page (used right after adding one).
    static func show(_ orderId: String, on seriesName: String) {
        let raw = UserDefaults.standard.string(forKey: "selectedReadingOrders") ?? ""
        UserDefaults.standard.set(remembering(orderId, seriesKey: TitleKey.make(seriesName), in: raw),
                                  forKey: "selectedReadingOrders")
    }

    private var order: ReadingOrder { orders.first { $0.id == selectedId } ?? orders[0] }

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
        .task(id: order.id) { await store.resolve(order, client: client) }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await store.resolve(order, client: client, force: true) }
        }
        .confirmationDialog("Remove \"\(order.title)\"?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove reading order", role: .destructive) { store.remove(order) }
        } message: {
            Text("Only the reading order is removed. Your comics and reading progress stay as they are.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if orders.count > 1 {
                    Menu {
                        ForEach(orders) { o in
                            Button {
                                select(o.id)
                            } label: {
                                if o.id == order.id { Label(o.title, systemImage: "checkmark") } else { Text(o.title) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(order.title).font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    Text(order.title).font(.headline).foregroundStyle(Theme.text)
                }
                Spacer()
                if refreshing { ProgressView().controlSize(.small) }
                Menu {
                    Toggle("Show issues not in my library", isOn: $showMissing)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.resolve(order, client: client, force: true) }
                    }
                    if order.source?.link != nil {
                        Button("Update from link", systemImage: "link") { refreshFromLink() }
                    }
                    Divider()
                    Button("Add a reading order…", systemImage: "plus") { addOrder() }
                    if order.isUserAdded {
                        Button("Remove this reading order", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
                }
            }
            Text(order.credit).font(.caption).foregroundStyle(Theme.muted)
            if let refreshError {
                Text(refreshError).font(.caption).foregroundStyle(Theme.danger)
            }
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

    /// Downloads the doc or sheet again and applies the same color and section choices.
    private func refreshFromLink() {
        let current = order
        refreshing = true
        refreshError = nil
        Task {
            do {
                let updated = try await ReadingOrderBuilder.refresh(current, client: client)
                try store.save(updated)
                await store.resolve(updated, client: client, force: true)
            } catch {
                refreshError = error.localizedDescription
            }
            refreshing = false
        }
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
