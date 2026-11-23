import SwiftUI

/// Everything a format-specific reader needs about the open chapter.
struct ReaderContext: Equatable {
    let chapterId: Int
    let info: ChapterInfo
    /// 0-based page (or EPUB section) to open at.
    let startPage: Int
    /// True when the server couldn't be reached and only downloaded pages are available.
    let offline: Bool

    static func == (a: ReaderContext, b: ReaderContext) -> Bool { a.chapterId == b.chapterId }

    var seriesName: String { info.seriesName ?? "" }

    var chapterTitle: String {
        if let sub = info.subtitle, !sub.isEmpty, sub != seriesName { return sub }
        if let title = info.title, !title.isEmpty, title != seriesName {
            return title.replacingOccurrences(of: "\(seriesName) - ", with: "")
        }
        return ""
    }
}

struct ReaderActions {
    /// Call with the 0-based page the reader is showing.
    let pageChanged: (Int) -> Void
    /// Call when the reader knows the user reached the end.
    let finished: () -> Void
    let nextChapterId: Int?
    let previousChapterId: Int?
    let goToNext: () -> Void
    let goToPrevious: () -> Void
    let close: () -> Void
    /// Reading-order issues between this one and the next that aren't in your library.
    var missingBeforeNext: [String] = []
}

/// Full-screen reader shell: loads chapter info and saved progress (from the server, or from the phone
/// when offline), picks the right reader, saves progress as pages turn, and moves between chapters.
struct ReaderView: View {
    let client: KavitaClient
    /// When set, next and previous follow this reading list instead of the series.
    var readingListId: Int? = nil
    /// When set, next and previous follow this order of chapter ids (a bundled reading order like Spawn's).
    var order: [Int]? = nil
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss

    @State private var chapterId: Int
    @State private var context: ReaderContext?
    @State private var nextChapterId: Int?
    @State private var previousChapterId: Int?
    @State private var error: String?
    @State private var lastSaved: Int?
    @State private var moved = false
    @State private var autoDownloaded: Set<Int> = []
    @State private var missingBeforeNext: [String] = []
    @State private var confirmSkip = false

    /// Open the first chapter at this page instead of the saved spot (used by bookmarks).
    @State private var pageOverride: Int?

    init(client: KavitaClient, startChapterId: Int, readingListId: Int? = nil, startPage: Int? = nil,
         order: [Int]? = nil) {
        self.client = client
        self.readingListId = readingListId
        self.order = order
        _chapterId = State(initialValue: startChapterId)
        _pageOverride = State(initialValue: startPage)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let context {
                if context.info.seriesFormat == MangaFormat.epub.rawValue {
                    EPUBReaderView(context: context, client: client, actions: actions)
                        .id(context.chapterId)
                } else {
                    ComicReaderView(context: context, client: client, actions: actions)
                        .id(context.chapterId)
                }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
                .foregroundStyle(.white)
                .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: chapterId) { await load() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }   // keep the screen on while reading
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert(missingBeforeNext.count == 1 ? "You don't have the next issue yet"
                                            : "You don't have the next \(missingBeforeNext.count) issues yet",
               isPresented: $confirmSkip) {
            Button("Skip to the next one I have") { if let next = nextChapterId { chapterId = next } }
            Button("Stay here", role: .cancel) {}
        } message: {
            Text(missingMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tourCloseReader)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
        }
    }

    private var actions: ReaderActions {
        ReaderActions(
            pageChanged: { page in save(page: page) },
            finished: { markFinished() },
            nextChapterId: nextChapterId,
            previousChapterId: previousChapterId,
            goToNext: {
                guard let next = nextChapterId else { return }
                // Warn before jumping over reading-order issues you don't have yet.
                if missingBeforeNext.isEmpty { chapterId = next } else { confirmSkip = true }
            },
            goToPrevious: { if let prev = previousChapterId { chapterId = prev } },
            close: { dismiss() },
            missingBeforeNext: missingBeforeNext
        )
    }

    private func load() async {
        context = nil
        error = nil
        nextChapterId = nil
        previousChapterId = nil
        missingBeforeNext = []
        lastSaved = nil
        moved = false

        var offline = false
        let info: ChapterInfo
        do {
            info = try await client.chapterInfo(chapterId: chapterId)
            downloads.replaceIfChanged(client: client, chapterId: chapterId, serverPages: info.pages)
        } catch {
            if let item = downloads.items[chapterId] {
                info = item.info
                offline = true
            } else {
                if let problem = ServerProblem.from(error) {
                    self.error = "This isn't downloaded, and the server can't be reached.\n\n\(problem.title). \(problem.detail)"
                } else {
                    self.error = error.localizedDescription
                }
                return
            }
        }

        // Unsynced progress on this phone wins, then the server, then the last page read offline.
        var saved = 0
        if let pending = downloads.pending[chapterId] {
            saved = pending.pageNum
        } else if !offline, let server = try? await client.progress(chapterId: chapterId) {
            saved = server.pageNum
        } else if let last = downloads.items[chapterId]?.lastPage {
            saved = last
        }
        // A finished chapter re-opens from the start; otherwise resume where you left off.
        var start = (saved >= info.pages || saved < 0) ? 0 : saved
        if let override = pageOverride {
            start = min(max(override, 0), max(info.pages - 1, 0))
            pageOverride = nil
        }
        lastSaved = saved
        context = ReaderContext(chapterId: chapterId, info: info, startPage: start, offline: offline)
        QuickActions.setContinue(chapterId: chapterId, readingListId: readingListId,
                                 seriesName: info.seriesName ?? "", chapterTitle: context?.chapterTitle ?? "")

        if let order, let i = order.firstIndex(of: chapterId) {
            // Works offline too: the order is already known.
            nextChapterId = i + 1 < order.count ? order[i + 1] : nil
            previousChapterId = i > 0 ? order[i - 1] : nil
            missingBeforeNext = ReadingOrderStore.shared.missingAfter(chapterId, orderIds: order)
        } else if !offline {
            nextChapterId = await next(after: chapterId, info: info)
            if let listId = readingListId {
                previousChapterId = (try? await client.previousInList(chapterId: chapterId, listId: listId)) ?? nil
            } else {
                previousChapterId = (try? await client.previousChapter(seriesId: info.seriesId, volumeId: info.volumeId,
                                                                       chapterId: chapterId)) ?? nil
            }
        }
    }

    private var missingMessage: String {
        let shown = missingBeforeNext.prefix(6).joined(separator: "\n")
        let more = missingBeforeNext.count > 6 ? "\nand \(missingBeforeNext.count - 6) more" : ""
        return "Next in the reading order:\n\(shown)\(more)\n\nThey aren't in your library. Add them on your PC, then scan."
    }

    /// The chapter after this one: next in the reading list, or next in the series.
    private func next(after id: Int, info: ChapterInfo) async -> Int? {
        if let order, let i = order.firstIndex(of: id) {
            return i + 1 < order.count ? order[i + 1] : nil
        }
        if let listId = readingListId {
            return (try? await client.nextInList(chapterId: id, listId: listId)) ?? nil
        }
        return (try? await client.nextChapter(seriesId: info.seriesId, volumeId: info.volumeId, chapterId: id)) ?? nil
    }

    /// After finishing, quietly download the next few chapters for offline reading.
    private func autoDownloadNext(from context: ReaderContext) {
        guard !context.offline, AutoDownload.allowedNow, !autoDownloaded.contains(context.chapterId) else { return }
        autoDownloaded.insert(context.chapterId)
        let count = AutoDownload.count
        let client = client
        Task {
            // Follow a reading order when this issue is in one (even if opened from the series page),
            // or the reading list you're reading from; otherwise the next issues of this series.
            var ids = order
            if ids == nil, readingListId == nil {
                ids = await ReadingOrderStore.shared.orderIds(containing: context.chapterId,
                                                              seriesName: context.seriesName, client: client)
            }
            if let ids, let i = ids.firstIndex(of: context.chapterId) {
                for nextId in ids.dropFirst(i + 1).prefix(count) {
                    guard downloads.items[nextId]?.isComplete != true,
                          let nextInfo = try? await client.chapterInfo(chapterId: nextId) else { continue }
                    downloads.start(client: client, chapterId: nextId, seriesId: nextInfo.seriesId,
                                    seriesName: nextInfo.seriesName ?? "", title: "", range: .all)
                }
                return
            }
            var current = context.chapterId
            var info = context.info
            for _ in 0..<count {
                guard let nextId = await next(after: current, info: info) else { break }
                guard let nextInfo = try? await client.chapterInfo(chapterId: nextId) else { break }
                if downloads.items[nextId]?.isComplete != true {
                    downloads.start(client: client, chapterId: nextId, seriesId: nextInfo.seriesId,
                                    seriesName: nextInfo.seriesName ?? "", title: "", range: .all)
                }
                current = nextId
                info = nextInfo
            }
        }
    }

    private func save(page: Int) {
        guard let context else { return }
        let info = context.info
        // Opening a chapter shouldn't change its status; only real page turns are saved.
        if !moved {
            guard page != context.startPage else { return }
            moved = true
        }
        // For comics and PDFs, landing on the last page counts as finishing.
        // EPUB sections are long, so the EPUB reader reports finishing itself.
        let isEPUB = info.seriesFormat == MangaFormat.epub.rawValue
        let lastPageFinishes = !isEPUB && page >= info.pages - 1
        let pageNum = (lastPageFinishes || page >= info.pages) ? info.pages : max(0, page)
        guard pageNum != lastSaved else { return }
        lastSaved = pageNum
        downloads.rememberPage(min(pageNum, info.pages - 1), chapterId: context.chapterId)
        if pageNum >= info.pages { autoDownloadNext(from: context) }

        let body = ProgressBody(volumeId: info.volumeId, chapterId: context.chapterId, pageNum: pageNum,
                                seriesId: info.seriesId, libraryId: info.libraryId, bookScrollId: nil)
        Task {
            do {
                try await client.saveProgress(body)
                downloads.clearPending(body.chapterId)
            } catch {
                downloads.queue(body) // sent automatically when the server is reachable again
            }
        }
    }

    private func markFinished() {
        guard let context else { return }
        moved = true
        save(page: context.info.pages)
        autoDownloadNext(from: context)
    }
}

/// Shown at the end of a chapter.
struct EndOfChapterView: View {
    let actions: ReaderActions

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.primary)
            Text("Finished").font(.title2.bold()).foregroundStyle(.white)
            if !actions.missingBeforeNext.isEmpty {
                VStack(spacing: 4) {
                    Label(actions.missingBeforeNext.count == 1 ? "Next issue isn't in your library"
                                                                : "Next \(actions.missingBeforeNext.count) issues aren't in your library",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    Text(actions.missingBeforeNext.prefix(3).joined(separator: " · ")
                         + (actions.missingBeforeNext.count > 3 ? " · …" : ""))
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
            }
            if actions.nextChapterId != nil {
                Button {
                    actions.goToNext()
                } label: {
                    Label("Next", systemImage: "arrow.right").frame(minWidth: 160)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Button("Close") { actions.close() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { actions.finished() }
    }
}
