import SwiftUI

/// Everything a format-specific reader needs about the open chapter.
struct ReaderContext: Equatable {
    let chapterId: Int
    let info: ChapterInfo
    /// 0-based page to open at.
    let startPage: Int

    static func == (a: ReaderContext, b: ReaderContext) -> Bool { a.chapterId == b.chapterId }

    var title: String {
        let name = info.seriesName ?? ""
        if let sub = info.subtitle, !sub.isEmpty, sub != name { return sub }
        return name
    }
}

/// Full-screen reader shell: loads chapter info and saved progress, picks the right reader,
/// saves progress as pages turn, and can move on to the next chapter.
struct ReaderView: View {
    let client: KavitaClient
    @Environment(\.dismiss) private var dismiss

    @State private var chapterId: Int
    @State private var context: ReaderContext?
    @State private var nextChapterId: Int?
    @State private var error: String?
    @State private var lastSaved: Int?
    @State private var moved = false

    init(client: KavitaClient, startChapterId: Int) {
        self.client = client
        _chapterId = State(initialValue: startChapterId)
    }

    var body: some View {
        ZStack {
            if let context {
                switch MangaFormat(rawValue: context.info.seriesFormat) ?? .unknown {
                case .pdf:
                    PDFReaderView(context: context, client: client, actions: actions)
                        .id(context.chapterId)
                case .epub:
                    EPUBReaderView(context: context, client: client, actions: actions)
                        .id(context.chapterId)
                case .image, .archive, .unknown:
                    ComicReaderView(context: context, client: client, actions: actions)
                        .id(context.chapterId)
                }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView("Opening…")
            }
        }
        .task(id: chapterId) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .tourCloseReader)) { _ in dismiss() }
    }

    private var actions: ReaderActions {
        ReaderActions(
            pageChanged: { page in save(page: page) },
            finished: { markFinished() },
            nextChapterId: nextChapterId,
            goToNext: { if let next = nextChapterId { chapterId = next } },
            close: { dismiss() }
        )
    }

    private func load() async {
        context = nil
        error = nil
        nextChapterId = nil
        lastSaved = nil
        moved = false
        do {
            let info = try await client.chapterInfo(chapterId: chapterId)
            let saved = (try? await client.progress(chapterId: chapterId))?.pageNum ?? 0
            // A finished chapter re-opens from the start; otherwise resume where you left off.
            let start = (saved >= info.pages || saved < 0) ? 0 : saved
            lastSaved = saved
            context = ReaderContext(chapterId: chapterId, info: info, startPage: start)
            nextChapterId = try? await client.nextChapter(seriesId: info.seriesId, volumeId: info.volumeId,
                                                          chapterId: chapterId)
        } catch {
            self.error = error.localizedDescription
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
        let body = ProgressBody(volumeId: info.volumeId, chapterId: context.chapterId, pageNum: pageNum,
                                seriesId: info.seriesId, libraryId: info.libraryId, bookScrollId: nil)
        Task { try? await client.saveProgress(body) }
    }

    private func markFinished() {
        guard let context else { return }
        save(page: context.info.pages)
    }
}

struct ReaderActions {
    /// Call with the 0-based page the reader is showing.
    let pageChanged: (Int) -> Void
    /// Call when the reader knows the user reached the end.
    let finished: () -> Void
    let nextChapterId: Int?
    let goToNext: () -> Void
    let close: () -> Void
}

/// Shown at the end of a chapter.
struct EndOfChapterView: View {
    let actions: ReaderActions

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Finished").font(.title2.bold())
            if actions.nextChapterId != nil {
                Button {
                    actions.goToNext()
                } label: {
                    Label("Next", systemImage: "arrow.right").frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Close") { actions.close() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { actions.finished() }
    }
}
