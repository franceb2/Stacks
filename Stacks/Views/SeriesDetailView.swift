import SwiftUI

struct ReaderLaunch: Identifiable {
    let chapterId: Int
    var readingListId: Int? = nil
    var id: Int { chapterId }
}

struct DownloadTarget: Identifiable {
    let chapter: Chapter
    let seriesId: Int
    let seriesName: String
    let title: String
    let isBook: Bool
    var id: Int { chapter.id }
}

private enum DetailTab: String, Hashable {
    case volumes = "Volumes", chapters, specials = "Specials", books = "Books"
}

/// Kavita's series page: cover, info, Continue button, then tabs of volume/chapter cards.
struct SeriesDetailView: View {
    let route: SeriesRoute
    let client: KavitaClient

    @EnvironmentObject private var downloads: Downloads
    @State private var series: Series?
    @State private var detail: SeriesDetail?
    @State private var metadata: SeriesMetadata?
    @State private var continueChapter: Chapter?
    @State private var tab: DetailTab?
    @State private var reader: ReaderLaunch?
    @State private var downloadTarget: DownloadTarget?
    @State private var summaryExpanded = false
    @State private var wantToRead: Bool?
    @State private var listTarget: ListSheetTarget?
    @State private var downloadsQueued = 0
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actionRow
                if let summary = metadata?.summary, !summary.isEmpty { summaryView(summary) }
                tags
                if let detail {
                    tabBar(detail)
                    cards(detail)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger).padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { seriesMenu }
        }
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $reader, onDismiss: {
            Task { await load() }
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId)
        }
        .sheet(item: $downloadTarget) { target in
            DownloadSheet(target: target, client: client)
        }
        .sheet(item: $listTarget) { item in
            AddToListSheet(target: item.target, title: item.title, client: client)
        }
        .sensoryFeedback(.selection, trigger: wantToRead)
        .sensoryFeedback(.success, trigger: downloadsQueued)
        .onReceive(NotificationCenter.default.publisher(for: .tourOpenReader)) { _ in
            if let chapter = continueChapter { reader = ReaderLaunch(chapterId: chapter.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tourDownloadSheet)) { _ in
            if let chapter = continueChapter ?? detail?.allChapters.first { askDownload(chapter) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tourCloseReader)) { _ in
            downloadTarget = nil
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Backdrop(url: client.seriesCoverURL(route.id))
                .frame(height: 300)
                .padding(.top, -120) // reach up under the navigation bar

            HStack(alignment: .bottom, spacing: 16) {
                CoverImage(url: client.seriesCoverURL(route.id))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 128)
                    .overlay(alignment: .bottom) {
                        if let series, series.progress > 0 && series.progress < 1 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.black.opacity(0.5))
                                    Rectangle().fill(Theme.primary).frame(width: geo.size.width * series.progress)
                                }
                            }
                            .frame(height: 5)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    .shadow(color: .black.opacity(0.55), radius: 16, y: 8)

                VStack(alignment: .leading, spacing: 7) {
                    Text(series?.name ?? route.name)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    if let writers = metadata?.writers, !writers.isEmpty {
                        Text(writers.map(\.name).joined(separator: ", "))
                            .font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    infoLine
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let continueChapter {
                Button {
                    reader = ReaderLaunch(chapterId: continueChapter.id)
                } label: {
                    Label(continueTitle(continueChapter), systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Button {
                toggleWantToRead()
            } label: {
                Image(systemName: wantToRead == true ? "heart.fill" : "heart")
                    .foregroundStyle(wantToRead == true ? Theme.primary : Theme.text)
                    .frame(width: 22)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(wantToRead == true ? "Remove from Want to Read" : "Add to Want to Read")
            Button {
                listTarget = ListSheetTarget(target: .series(route.id), title: series?.name ?? route.name)
            } label: {
                Image(systemName: "text.badge.plus").frame(width: 22)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Add to reading list")
        }
        .padding(.horizontal, 16)
    }

    private var infoLine: some View {
        var parts: [String] = []
        if let year = metadata?.releaseYear, year > 0 { parts.append(String(year)) }
        if let status = metadata?.statusText, (metadata?.publicationStatus ?? 0) != 0 { parts.append(status) }
        if let detail, detail.totalCount > 0 {
            parts.append(detail.unreadCount == 0 ? "All read" : "\(detail.unreadCount) unread")
        }
        if let series, series.pagesRead > 0, !series.isRead {
            parts.append("\(Int(series.progress * 100))% read")
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption).foregroundStyle(Theme.muted)
    }

    private func summaryView(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.strippingHTML)
                .font(.subheadline)
                .foregroundStyle(Theme.text.opacity(0.85))
                .lineLimit(summaryExpanded ? nil : 3)
            Button(summaryExpanded ? "Show less" : "Read more") {
                withAnimation { summaryExpanded.toggle() }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var tags: some View {
        let genres = (metadata?.genres ?? []).map(\.title)
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.primary.opacity(0.5)))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Tabs

    private func availableTabs(_ d: SeriesDetail) -> [DetailTab] {
        var tabs: [DetailTab] = []
        if !d.volumes.isEmpty { tabs.append(.volumes) }
        if !d.looseChapters.isEmpty { tabs.append(.chapters) }
        if !d.specials.isEmpty { tabs.append(d.volumes.isEmpty && d.looseChapters.isEmpty ? .books : .specials) }
        return tabs
    }

    private func tabLabel(_ t: DetailTab, _ d: SeriesDetail) -> String {
        t == .chapters ? d.chapterNoun : t.rawValue
    }

    private func tabBar(_ d: SeriesDetail) -> some View {
        let tabs = availableTabs(d)
        let selected = tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(tabs, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 6) {
                            Text(tabLabel(t, d))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected == t ? Theme.text : Theme.muted)
                            Rectangle()
                                .fill(selected == t ? Theme.primary : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    @ViewBuilder
    private func cards(_ d: SeriesDetail) -> some View {
        let tabs = availableTabs(d)
        let selected = tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first
        CardGrid {
            switch selected {
            case .volumes:
                ForEach(d.volumes.sorted { ($0.minNumber ?? 0) < ($1.minNumber ?? 0) }) { volumeCard($0, d) }
            case .chapters:
                ForEach(d.looseChapters) { chapterCard($0) }
            case .specials, .books:
                ForEach(d.specials) { chapterCard($0) }
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func volumeCard(_ volume: Volume, _ d: SeriesDetail) -> some View {
        let chapters = volume.chapters ?? []
        let card = KavitaCard(title: volume.displayName,
                              subtitle: "\(volume.pages) pages",
                              coverURL: client.volumeCoverURL(volume.id),
                              progress: volume.progress,
                              unread: volume.pagesRead == 0,
                              downloaded: downloads.badge(forChapters: chapters.map(\.id)))
        Group {
            if chapters.count == 1, let only = chapters.first {
                Button { reader = ReaderLaunch(chapterId: only.id) } label: { card }
                    .buttonStyle(PressableStyle())
            } else {
                NavigationLink(value: VolumeRoute(seriesId: route.id, seriesName: series?.name ?? route.name,
                                                  volume: volume, isComic: d.chapterNoun == "Issues")) { card }
                    .buttonStyle(PressableStyle())
            }
        }
        .contextMenu {
            if let first = chapters.first(where: { !$0.isRead }) ?? chapters.first {
                Button("Read", systemImage: "book") { reader = ReaderLaunch(chapterId: first.id) }
            }
            Button("Mark as read", systemImage: "checkmark.circle") { markVolume(volume, read: true) }
            Button("Mark as unread", systemImage: "circle") { markVolume(volume, read: false) }
            Divider()
            Button("Add to reading list…", systemImage: "text.badge.plus") {
                listTarget = ListSheetTarget(target: .volume(seriesId: route.id, volumeId: volume.id),
                                             title: volume.displayName)
            }
            Button("Download volume", systemImage: "arrow.down.circle") {
                for c in chapters { download(c, name: volume.displayName, range: .all) }
            }
            if chapters.count == 1, let only = chapters.first {
                Button("Download pages…", systemImage: "doc.on.doc") { askDownload(only, name: volume.displayName) }
            }
            if chapters.contains(where: { downloads.items[$0.id] != nil }) {
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    for c in chapters { downloads.delete(c.id) }
                }
            }
        }
    }

    private func chapterCard(_ chapter: Chapter) -> some View {
        Button {
            reader = ReaderLaunch(chapterId: chapter.id)
        } label: {
            KavitaCard(title: name(for: chapter),
                       subtitle: chapter.isStarted ? "Page \(chapter.pagesRead + 1) of \(chapter.pages)"
                                                   : "\(chapter.pages) pages",
                       coverURL: client.chapterCoverURL(chapter.id),
                       progress: chapter.progress,
                       unread: chapter.pagesRead == 0,
                       downloaded: downloads.badge(for: chapter.id))
        }
        .buttonStyle(PressableStyle())
        .contextMenu { chapterMenu(chapter) }
    }

    @ViewBuilder
    private func chapterMenu(_ chapter: Chapter) -> some View {
        Button("Read", systemImage: "book") { reader = ReaderLaunch(chapterId: chapter.id) }
        Button("Mark as read", systemImage: "checkmark.circle") { markChapter(chapter, read: true) }
        Button("Mark as unread", systemImage: "circle") { markChapter(chapter, read: false) }
        Button("Add to reading list…", systemImage: "text.badge.plus") {
            listTarget = ListSheetTarget(target: .chapter(seriesId: route.id, chapterId: chapter.id),
                                         title: name(for: chapter))
        }
        Divider()
        Button("Download", systemImage: "arrow.down.circle") { download(chapter, name: name(for: chapter), range: .all) }
        Button("Download pages…", systemImage: "doc.on.doc") { askDownload(chapter) }
        if downloads.items[chapter.id] != nil {
            Button("Remove download", systemImage: "trash", role: .destructive) { downloads.delete(chapter.id) }
        }
    }

    private var seriesMenu: some View {
        Menu {
            Button("Mark all as read", systemImage: "checkmark.circle") { markSeries(read: true) }
            Button("Mark all as unread", systemImage: "circle") { markSeries(read: false) }
            Button("Add to reading list…", systemImage: "text.badge.plus") {
                listTarget = ListSheetTarget(target: .series(route.id), title: series?.name ?? route.name)
            }
            Divider()
            Button("Download all", systemImage: "arrow.down.circle") {
                for c in detail?.allChapters ?? [] { download(c, name: name(for: c), range: .all) }
            }
            Button("Download unread", systemImage: "arrow.down.circle.dotted") {
                for c in (detail?.allChapters ?? []) where !c.isRead { download(c, name: name(for: c), range: .all) }
            }
            if (detail?.allChapters ?? []).contains(where: { downloads.items[$0.id] != nil }) {
                Button("Remove downloads", systemImage: "trash", role: .destructive) {
                    for c in detail?.allChapters ?? [] { downloads.delete(c.id) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: Helpers

    private func continueTitle(_ chapter: Chapter) -> String {
        if chapter.isStarted { return "Continue \(name(for: chapter))" }
        if (series?.pagesRead ?? 0) == 0 { return "Start reading" }
        return "Read \(name(for: chapter))"
    }

    private func name(for chapter: Chapter) -> String {
        if chapter.isWholeVolume, let volume = detail?.volumes.first(where: { $0.id == chapter.volumeId }) {
            return volume.displayName
        }
        return chapter.displayName
    }

    private var isBook: Bool { series?.format == MangaFormat.epub.rawValue }

    private func toggleWantToRead() {
        let newValue = !(wantToRead ?? false)
        wantToRead = newValue
        Task {
            do { try await client.setWantToRead(route.id, newValue) }
            catch { wantToRead = !newValue }
        }
    }

    private func download(_ chapter: Chapter, name: String, range: DownloadRange) {
        downloadsQueued += 1
        downloads.start(client: client, chapter: chapter, seriesId: route.id,
                        seriesName: series?.name ?? route.name, title: name, range: range)
    }

    private func askDownload(_ chapter: Chapter, name: String? = nil) {
        downloadTarget = DownloadTarget(chapter: chapter, seriesId: route.id, seriesName: series?.name ?? route.name,
                                        title: name ?? self.name(for: chapter), isBook: isBook)
    }

    private func load() async {
        do {
            async let s = client.series(id: route.id)
            async let d = client.seriesDetail(id: route.id)
            async let m = client.metadata(seriesId: route.id)
            async let c = client.continuePoint(seriesId: route.id)
            series = try await s
            detail = try await d
            metadata = try? await m
            continueChapter = try? await c
            wantToRead = try? await client.isWantToRead(route.id)
            error = nil
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = KavitaClient.isOffline(error)
                ? "Can't reach your server. Downloaded items are in the Downloads tab."
                : error.localizedDescription
        }
    }

    private func refreshAfterChange() async {
        await load()
        NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
    }

    private func markChapter(_ chapter: Chapter, read: Bool) {
        Task {
            do { try await client.markChapter(seriesId: route.id, chapter: chapter, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }

    private func markVolume(_ volume: Volume, read: Bool) {
        Task {
            do { try await client.markVolume(seriesId: route.id, volumeId: volume.id, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }

    private func markSeries(read: Bool) {
        Task {
            do { try await client.markSeries(route.id, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }
}

/// A volume that contains several chapters, shown as its own card grid.
struct VolumeView: View {
    let route: VolumeRoute
    let client: KavitaClient

    @EnvironmentObject private var downloads: Downloads
    @State private var reader: ReaderLaunch?
    @State private var downloadTarget: DownloadTarget?
    @State private var chapters: [Chapter]

    init(route: VolumeRoute, client: KavitaClient) {
        self.route = route
        self.client = client
        _chapters = State(initialValue: route.volume.chapters ?? [])
    }

    var body: some View {
        ScrollView {
            CardGrid {
                ForEach(chapters) { chapter in
                    Button {
                        reader = ReaderLaunch(chapterId: chapter.id)
                    } label: {
                        KavitaCard(title: chapter.displayName,
                                   subtitle: chapter.isStarted ? "Page \(chapter.pagesRead + 1) of \(chapter.pages)"
                                                               : "\(chapter.pages) pages",
                                   coverURL: client.chapterCoverURL(chapter.id),
                                   progress: chapter.progress,
                                   unread: chapter.pagesRead == 0,
                                   downloaded: downloads.badge(for: chapter.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Download", systemImage: "arrow.down.circle") {
                            downloads.start(client: client, chapter: chapter, seriesId: route.seriesId,
                                            seriesName: route.seriesName, title: chapter.displayName, range: .all)
                        }
                        Button("Download pages…", systemImage: "doc.on.doc") {
                            downloadTarget = DownloadTarget(chapter: chapter, seriesId: route.seriesId,
                                                            seriesName: route.seriesName, title: chapter.displayName,
                                                            isBook: false)
                        }
                        if downloads.items[chapter.id] != nil {
                            Button("Remove download", systemImage: "trash", role: .destructive) {
                                downloads.delete(chapter.id)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle(route.volume.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reader, onDismiss: {
            Task { await reload() }
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId)
        }
        .sheet(item: $downloadTarget) { DownloadSheet(target: $0, client: client) }
    }

    private func reload() async {
        if let detail = try? await client.seriesDetail(id: route.seriesId),
           let fresh = detail.volumes.first(where: { $0.id == route.volume.id }) {
            chapters = fresh.chapters ?? chapters
        }
    }
}

extension String {
    /// Kavita summaries can contain simple HTML.
    var strippingHTML: String {
        replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
