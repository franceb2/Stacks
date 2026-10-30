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
}

/// Full-screen reader shell: loads chapter info and saved progress (from the server, or from the phone
/// when offline), picks the right reader, saves progress as pages turn, and moves between chapters.
struct ReaderView: View {
    let client: KavitaClient
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss

    @State private var chapterId: Int
    @State private var context: ReaderContext?
    @State private var nextChapterId: Int?
    @State private var previousChapterId: Int?
    @State private var error: String?
    @State private var lastSaved: Int?
    @State private var moved = false

    init(client: KavitaClient, startChapterId: Int) {
        self.client = client
        _chapterId = State(initialValue: startChapterId)
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
            goToNext: { if let next = nextChapterId { chapterId = next } },
            goToPrevious: { if let prev = previousChapterId { chapterId = prev } },
            close: { dismiss() }
        )
    }

    private func load() async {
        context = nil
        error = nil
        nextChapterId = nil
        previousChapterId = nil
        lastSaved = nil
        moved = false

        var offline = false
        let info: ChapterInfo
        do {
            info = try await client.chapterInfo(chapterId: chapterId)
        } catch {
            if let item = downloads.items[chapterId] {
                info = item.info
                offline = true
            } else {
                self.error = KavitaClient.isOffline(error)
                    ? "Can't reach your server, and this isn't downloaded."
                    : error.localizedDescription
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
        let start = (saved >= info.pages || saved < 0) ? 0 : saved
        lastSaved = saved
        context = ReaderContext(chapterId: chapterId, info: info, startPage: start, offline: offline)

        if !offline {
            async let next = client.nextChapter(seriesId: info.seriesId, volumeId: info.volumeId, chapterId: chapterId)
            async let prev = client.previousChapter(seriesId: info.seriesId, volumeId: info.volumeId,
                                                    chapterId: chapterId)
            nextChapterId = (try? await next) ?? nil
            previousChapterId = (try? await prev) ?? nil
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
