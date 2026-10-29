import SwiftUI

struct ReaderLaunch: Identifiable {
    let chapterId: Int
    var id: Int { chapterId }
}

struct SeriesDetailView: View {
    let seriesId: Int
    let title: String
    let client: KavitaClient

    @State private var series: Series?
    @State private var detail: SeriesDetail?
    @State private var continueChapter: Chapter?
    @State private var reader: ReaderLaunch?
    @State private var error: String?

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            if let detail {
                ForEach(sortedVolumes(detail.volumes)) { volume in
                    Section {
                        ForEach(volume.chapters ?? []) { chapter in
                            chapterRow(chapter, fallbackName: (volume.chapters?.count ?? 0) == 1 ? volume.displayName : nil)
                        }
                    } header: {
                        HStack {
                            Text(volume.displayName)
                            Spacer()
                            Menu {
                                Button("Mark volume as read", systemImage: "checkmark.circle") { markVolume(volume, read: true) }
                                Button("Mark volume as unread", systemImage: "circle") { markVolume(volume, read: false) }
                            } label: {
                                Image(systemName: volume.isRead ? "checkmark.circle.fill" : "ellipsis.circle")
                                    .foregroundStyle(volume.isRead ? Color.green : Color.secondary)
                            }
                        }
                    }
                }

                let loose = looseChapters(detail)
                if !loose.isEmpty {
                    Section(detail.volumes.isEmpty ? detail.chapterNoun : "More \(detail.chapterNoun.lowercased())") {
                        ForEach(loose) { chapterRow($0) }
                    }
                }

                if !detail.specials.isEmpty {
                    Section(detail.volumes.isEmpty && detail.chapters.isEmpty ? "Books" : "Specials") {
                        ForEach(detail.specials) { chapterRow($0) }
                    }
                }
            } else if error == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Mark all as read", systemImage: "checkmark.circle") { markSeries(read: true) }
                    Button("Mark all as unread", systemImage: "circle") { markSeries(read: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $reader, onDismiss: {
            Task { await load() }
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(url: client.seriesCoverURL(seriesId))
                .frame(width: 110)
                .shadow(radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(series?.name ?? title)
                    .font(.title3.bold())
                    .lineLimit(3)
                if let series {
                    if series.isRead {
                        Label("Finished", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                    } else if series.pagesRead > 0 {
                        ProgressView(value: series.progress).tint(.orange)
                        Text("\(Int(series.progress * 100))% read").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let detail, detail.totalCount > 0 {
                    Text("\(detail.unreadCount) of \(detail.totalCount) unread")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let continueChapter {
                    Button {
                        reader = ReaderLaunch(chapterId: continueChapter.id)
                    } label: {
                        Label(buttonTitle(continueChapter), systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func buttonTitle(_ chapter: Chapter) -> String {
        if chapter.isStarted { return "Continue \(name(for: chapter))" }
        if (series?.pagesRead ?? 0) == 0 { return "Start reading" }
        return "Read \(name(for: chapter))"
    }

    // MARK: Rows

    private func chapterRow(_ chapter: Chapter, fallbackName: String? = nil) -> some View {
        Button {
            reader = ReaderLaunch(chapterId: chapter.id)
        } label: {
            HStack(spacing: 12) {
                statusIcon(chapter)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fallbackName ?? name(for: chapter))
                        .foregroundStyle(chapter.isRead ? .secondary : .primary)
                        .lineLimit(2)
                    if chapter.isStarted {
                        Text("Page \(chapter.pagesRead + 1) of \(chapter.pages)")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("\(chapter.pages) pages").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if chapter.isRead || chapter.isStarted {
                Button("Unread", systemImage: "circle") { markChapter(chapter, read: false) }.tint(.gray)
            }
            if !chapter.isRead {
                Button("Read", systemImage: "checkmark") { markChapter(chapter, read: true) }.tint(.green)
            }
        }
        .contextMenu {
            Button("Mark as read", systemImage: "checkmark.circle") { markChapter(chapter, read: true) }
            Button("Mark as unread", systemImage: "circle") { markChapter(chapter, read: false) }
        }
    }

    @ViewBuilder
    private func statusIcon(_ chapter: Chapter) -> some View {
        if chapter.isRead {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if chapter.isStarted {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle().trim(from: 0, to: chapter.progress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    /// Kavita repeats volume chapters in its flat chapter list; show each chapter once.
    private func looseChapters(_ detail: SeriesDetail) -> [Chapter] {
        let inVolumes = Set(detail.volumes.flatMap { ($0.chapters ?? []).map(\.id) })
        return detail.chapters.filter { !inVolumes.contains($0.id) }
    }

    /// Name for a chapter, using its volume's name when the file is a whole volume.
    private func name(for chapter: Chapter) -> String {
        if chapter.isWholeVolume, let volume = detail?.volumes.first(where: { $0.id == chapter.volumeId }) {
            return volume.displayName
        }
        return chapter.displayName
    }

    private func sortedVolumes(_ volumes: [Volume]) -> [Volume] {
        volumes.sorted { ($0.minNumber ?? 0) < ($1.minNumber ?? 0) }
    }

    // MARK: Data

    private func load() async {
        do {
            async let s = client.series(id: seriesId)
            async let d = client.seriesDetail(id: seriesId)
            async let c = client.continuePoint(seriesId: seriesId)
            series = try await s
            detail = try await d
            continueChapter = try? await c
            error = nil
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshAfterChange() async {
        await load()
        NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
    }

    private func markChapter(_ chapter: Chapter, read: Bool) {
        Task {
            do { try await client.markChapter(seriesId: seriesId, chapter: chapter, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }

    private func markVolume(_ volume: Volume, read: Bool) {
        Task {
            do { try await client.markVolume(seriesId: seriesId, volumeId: volume.id, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }

    private func markSeries(read: Bool) {
        Task {
            do { try await client.markSeries(seriesId, read: read) }
            catch { self.error = error.localizedDescription }
            await refreshAfterChange()
        }
    }
}
