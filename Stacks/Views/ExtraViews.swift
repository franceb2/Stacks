import Charts
import SwiftUI

struct CollectionRoute: Hashable { let collection: KavitaCollection }
struct PersonRoute: Hashable { let person: Person }
struct SearchRoute: Hashable {}
struct StatsRoute: Hashable {}
struct BookmarksRoute: Hashable {}

// MARK: - Bookmarks

/// A grid of bookmarked pages. Tap one to open the reader on that page.
struct BookmarkGrid: View {
    let client: KavitaClient
    let bookmarks: [Bookmark]
    let showSeries: Bool
    let open: (Bookmark) -> Void
    let remove: (Bookmark) -> Void

    var body: some View {
        CardGrid {
            ForEach(bookmarks) { b in
                Button { open(b) } label: {
                    KavitaCard(title: showSeries ? (b.series?.name ?? "Bookmark") : "Page \(b.page + 1)",
                               subtitle: showSeries ? "\(b.chapterTitle ?? "Issue") · page \(b.page + 1)"
                                                    : b.chapterTitle,
                               coverURL: client.bookmarkImageURL(b))
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button("Open", systemImage: "book") { open(b) }
                    Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) { remove(b) }
                }
            }
        }
    }
}

/// Bookmarks for one series, from the series page.
struct BookmarksSheet: View {
    let client: KavitaClient
    let seriesId: Int
    let title: String
    let open: (Bookmark) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bookmarks: [Bookmark] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if loaded && bookmarks.isEmpty {
                    Text("No bookmarks yet. While reading, tap the menu and the bookmark button to save a page.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        .padding(40)
                }
                BookmarkGrid(client: client, bookmarks: bookmarks, showSeries: false, open: open) { b in
                    Task { await remove(b) }
                }
                .padding(.vertical, 16)
            }
            .kavitaBackground()
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                bookmarks = (try? await client.seriesBookmarks(seriesId)) ?? []
                loaded = true
            }
        }
        .preferredColorScheme(.dark)
    }

    private func remove(_ b: Bookmark) async {
        try? await client.setBookmark(false, page: b.page, chapterId: b.chapterId, volumeId: b.volumeId,
                                      seriesId: b.seriesId)
        bookmarks.removeAll { $0.id == b.id }
    }
}

/// Every bookmark, from the Lists tab.
struct AllBookmarksView: View {
    let client: KavitaClient
    @State private var bookmarks: [Bookmark] = []
    @State private var loaded = false
    @State private var reader: ReaderLaunch?

    var body: some View {
        ScrollView {
            if loaded && bookmarks.isEmpty {
                Text("No bookmarks yet. While reading a comic, open the menu and tap the bookmark button.")
                    .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .padding(40)
            }
            BookmarkGrid(client: client, bookmarks: bookmarks, showSeries: true,
                         open: { reader = ReaderLaunch(chapterId: $0.chapterId, page: $0.page) }) { b in
                Task {
                    try? await client.setBookmark(false, page: b.page, chapterId: b.chapterId, volumeId: b.volumeId,
                                                  seriesId: b.seriesId)
                    bookmarks.removeAll { $0.id == b.id }
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle("Bookmarks")
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $reader) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId, startPage: launch.page)
        }
    }

    private func load() async {
        bookmarks = (try? await client.allBookmarks()) ?? bookmarks
        loaded = true
    }
}

// MARK: - Collections

struct CollectionView: View {
    let route: CollectionRoute
    let client: KavitaClient
    @State private var series: [Series] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            CardGrid {
                ForEach(series) { s in
                    NavigationLink(value: SeriesRoute(id: s.id, name: s.name)) {
                        SeriesCard(series: s, client: client)
                    }
                    .buttonStyle(PressableStyle())
                    .zoomSource("series-\(s.id)")
                }
            }
            .padding(.vertical, 16)
            if loaded && series.isEmpty {
                Text("Nothing in this collection yet.").foregroundStyle(Theme.muted).padding(.top, 40)
            }
        }
        .kavitaBackground()
        .navigationTitle(route.collection.title)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        var all: [Series] = []
        var page = 1
        while page < 50, let batch = try? await client.seriesInCollection(route.collection.id, page: page) {
            all.append(contentsOf: batch)
            if batch.count < 60 { break }
            page += 1
        }
        series = all
        loaded = true
    }
}

struct AddToCollectionSheet: View {
    let client: KavitaClient
    let seriesId: Int
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var collections: [KavitaCollection] = []
    @State private var newTitle = ""
    @State private var busy = false
    @State private var error: String?
    @State private var added = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New collection name", text: $newTitle)
                        Button("Create") { Task { await add(id: 0, title: newTitle) } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                    .listRowBackground(Theme.card)
                }
                Section("Your collections") {
                    ForEach(collections) { c in
                        Button { Task { await add(id: c.id, title: c.title) } } label: {
                            HStack {
                                Text(c.title).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(c.itemCount)").foregroundStyle(Theme.muted)
                            }
                        }
                        .disabled(busy)
                        .listRowBackground(Theme.card)
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.danger).listRowBackground(Color.clear) }
            }
            .kavitaBackground()
            .navigationTitle("Add \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { collections = (try? await client.collections()) ?? [] }
            .sensoryFeedback(.success, trigger: added)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func add(id: Int, title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.addToCollection(seriesId: seriesId, collectionId: id, title: name)
            added += 1
            NotificationCenter.default.post(name: .readingListsChanged, object: nil)
            try? await Task.sleep(nanoseconds: 250_000_000)
            dismiss()
        } catch {
            if case KavitaError.http(let code, _) = error, code == 401 || code == 403 {
                self.error = "Only Kavita admins can change collections."
            } else {
                self.error = "Couldn't add it: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Search everything

struct SearchView: View {
    let client: KavitaClient
    @State private var text = ""
    @State private var results: SearchResults?
    @State private var searching = false

    var body: some View {
        List {
            if let results {
                if let series = results.series, !series.isEmpty {
                    Section("Series") {
                        ForEach(series.prefix(30)) { s in
                            NavigationLink(value: SeriesRoute(id: s.seriesId, name: s.name)) {
                                HStack(spacing: 12) {
                                    CoverImage(url: client.seriesCoverURL(s.seriesId))
                                        .clipShape(RoundedRectangle(cornerRadius: 4)).frame(width: 40)
                                    VStack(alignment: .leading) {
                                        Text(s.name).foregroundStyle(Theme.text)
                                        if let lib = s.libraryName {
                                            Text(lib).font(.caption).foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                if let persons = results.persons, !persons.isEmpty {
                    Section("People and characters") {
                        ForEach(persons.prefix(30)) { p in
                            NavigationLink(value: PersonRoute(person: p)) {
                                HStack(spacing: 12) {
                                    CachedImage(url: client.personCoverURL(p.id)) {
                                        Image(systemName: "person.fill").foregroundStyle(Theme.muted)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(Theme.background)
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    VStack(alignment: .leading) {
                                        Text(p.name).foregroundStyle(Theme.text)
                                        if !p.roleText.isEmpty {
                                            Text(p.roleText).font(.caption).foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                if let collections = results.collections, !collections.isEmpty {
                    Section("Collections") {
                        ForEach(collections) { c in
                            NavigationLink(value: CollectionRoute(collection: c)) {
                                Label(c.title, systemImage: "square.stack.3d.up")
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                if let lists = results.readingLists, !lists.isEmpty {
                    Section("Reading lists") {
                        ForEach(lists) { l in
                            NavigationLink(value: ReadingListRoute(list: l)) {
                                Label(l.title, systemImage: "list.bullet.rectangle")
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                if (results.series ?? []).isEmpty && (results.persons ?? []).isEmpty
                    && (results.collections ?? []).isEmpty && (results.readingLists ?? []).isEmpty {
                    Text("No matches.").foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
            } else if !searching {
                Text("Search series, writers, artists, characters, collections and reading lists.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .kavitaBackground()
        .navigationTitle("Search")
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Series, people, characters…")
        .overlay { if searching { ProgressView() } }
        .task(id: text) {
            let query = text.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else { results = nil; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            results = try? await client.search(query)
            searching = false
        }
    }
}

struct PersonView: View {
    let route: PersonRoute
    let client: KavitaClient
    @State private var series: [Series] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !route.person.roleText.isEmpty {
                    Text(route.person.roleText).font(.subheadline).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 16)
                }
                CardGrid {
                    ForEach(series) { s in
                        NavigationLink(value: SeriesRoute(id: s.id, name: s.name)) {
                            SeriesCard(series: s, client: client)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                if loaded && series.isEmpty {
                    Text("No series found.").foregroundStyle(Theme.muted).padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle(route.person.name)
        .task {
            series = (try? await client.seriesFor(personId: route.person.id)) ?? []
            loaded = true
        }
    }
}

// MARK: - Reading stats

struct StatsView: View {
    let client: KavitaClient
    @State private var read: UserReadStats?
    @State private var profile: ProfileStats?
    @State private var months: [MonthCount] = []
    @State private var sessions: [ReadingSession] = []
    @State private var authors: [FavoriteAuthor] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    tile("Pages read", value: (read?.totalPagesRead).map { $0.formatted() }, icon: "doc.text")
                    tile("Hours reading", value: (read?.timeSpentReading).map { $0.formatted() }, icon: "clock")
                    tile("Comics finished", value: (profile?.comicsRead).map { $0.formatted() },
                         icon: "bubble.left.and.bubble.right")
                    tile("Books finished", value: (profile?.booksRead).map { $0.formatted() }, icon: "books.vertical")
                    tile("Current streak", value: "\(streak) day\(streak == 1 ? "" : "s")", icon: "flame")
                    tile("Per week", value: read.map { String(format: "%.1f h", $0.avgHoursPerWeekSpentReading) },
                         icon: "calendar")
                }
                .padding(.horizontal, 16)

                if !months.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Finished by month")
                        Chart(months.suffix(12)) { m in
                            BarMark(x: .value("Month", m.date, unit: .month), y: .value("Finished", m.count))
                                .foregroundStyle(Theme.primary)
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .frame(height: 170)
                        .padding(.horizontal, 16)
                    }
                }

                if !topSeries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Most read lately")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(topSeries, id: \.id) { item in
                                    NavigationLink(value: SeriesRoute(id: item.id, name: item.name)) {
                                        KavitaCard(title: item.name, subtitle: "\(item.pages) pages",
                                                   coverURL: client.seriesCoverURL(item.id))
                                            .frame(width: 104)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                if !authors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Favorite writers")
                        ForEach(authors.prefix(5)) { a in
                            HStack {
                                Text(a.authorName).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(a.totalChaptersRead) read").foregroundStyle(Theme.muted).font(.footnote)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Recent reading")
                        ForEach(sessions.prefix(15)) { s in
                            HStack(alignment: .top, spacing: 12) {
                                CoverImage(url: client.seriesCoverURL(s.seriesId))
                                    .clipShape(RoundedRectangle(cornerRadius: 4)).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.seriesName ?? "").foregroundStyle(Theme.text).lineLimit(1)
                                    Text(sessionDetail(s)).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                                }
                                Spacer()
                                Text(s.day ?? "").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                if loaded && sessions.isEmpty && (read?.totalPagesRead ?? 0) == 0 {
                    Text(error ?? "No reading history yet. Kavita records a session about 10 minutes after you stop reading.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle("Reading stats")
        .refreshable { await load() }
        .task { await load() }
    }

    private func tile(_ label: String, value: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.primary)
            Text(value ?? "–").font(.title2.bold()).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Days in a row with reading, ending today or yesterday.
    private var streak: Int {
        let days = Set(sessions.compactMap(\.day))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var date = Date()
        if !days.contains(formatter.string(from: date)) {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var count = 0
        while days.contains(formatter.string(from: date)) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }

    private struct TopSeries { let id: Int; let name: String; let pages: Int }

    private var topSeries: [TopSeries] {
        var totals: [Int: (String, Int)] = [:]
        for s in sessions {
            let current = totals[s.seriesId] ?? (s.seriesName ?? "", 0)
            totals[s.seriesId] = (current.0, current.1 + s.pagesRead)
        }
        return totals.map { TopSeries(id: $0.key, name: $0.value.0, pages: $0.value.1) }
            .sorted { $0.pages > $1.pages }
            .prefix(10)
            .map { $0 }
    }

    private func sessionDetail(_ s: ReadingSession) -> String {
        let chapters = (s.chapters ?? []).compactMap(\.label).filter { !$0.isEmpty }
        let minutes = max(1, s.durationSeconds / 60)
        let what = chapters.isEmpty ? "" : chapters.prefix(2).joined(separator: ", ") + " · "
        return "\(what)\(s.pagesRead) pages · \(minutes) min"
    }

    private func load() async {
        do {
            let me = try await client.account()
            async let r = client.readStats(userId: me.id)
            async let p = client.profileStats(userId: me.id)
            async let m = client.readsByMonth(userId: me.id)
            async let h = client.readingHistory()
            async let a = client.favoriteAuthors(userId: me.id)
            read = try? await r
            profile = try? await p
            months = ((try? await m) ?? []).sorted { $0.date < $1.date }
            sessions = (try? await h) ?? []
            authors = (try? await a) ?? []
            error = nil
        } catch {
            self.error = ServerProblem.from(error)?.title ?? error.localizedDescription
        }
        loaded = true
    }
}
