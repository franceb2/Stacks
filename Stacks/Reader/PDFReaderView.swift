import PDFKit
import SwiftUI

/// PDF reader built on Apple's PDFKit. Downloads the file once, then pages horizontally.
struct PDFReaderView: View {
    let context: ReaderContext
    let client: KavitaClient
    let actions: ReaderActions

    @State private var document: PDFDocument?
    @State private var page: Int
    @State private var error: String?
    @State private var reachedEnd = false

    init(context: ReaderContext, client: KavitaClient, actions: ReaderActions) {
        self.context = context
        self.client = client
        self.actions = actions
        _page = State(initialValue: context.startPage)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    PDFKitView(document: document, startPage: context.startPage) { newPage in
                        page = newPage
                        actions.pageChanged(newPage)
                        if newPage >= document.pageCount - 1 { reachedEnd = true }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    Text(error).foregroundStyle(.red).padding()
                } else {
                    ProgressView("Downloading PDF…")
                }
            }
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { actions.close() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .principal) {
                    if let document {
                        Text("Page \(page + 1) of \(document.pageCount)").font(.footnote.monospacedDigit())
                    }
                }
                if reachedEnd && actions.nextChapterId != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") { actions.goToNext() }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await client.pdfData(chapterId: context.chapterId)
            guard let doc = PDFDocument(data: data) else {
                error = "This PDF couldn't be opened."
                return
            }
            document = doc
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let startPage: Int
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChange: onPageChange) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.autoScales = true
        view.backgroundColor = .systemBackground

        context.coordinator.observe(view)
        if let page = document.page(at: min(max(startPage, 0), max(document.pageCount - 1, 0))) {
            view.go(to: page)
            // The page controller may not be laid out yet; repeat once it is.
            DispatchQueue.main.async { [weak view] in view?.go(to: page) }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
    }

    final class Coordinator: NSObject {
        var onPageChange: (Int) -> Void
        private var token: NSObjectProtocol?

        init(onPageChange: @escaping (Int) -> Void) { self.onPageChange = onPageChange }

        func observe(_ view: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view,
                                                           queue: .main) { [weak self, weak view] _ in
                guard let view, let page = view.currentPage, let doc = view.document else { return }
                self?.onPageChange(doc.index(for: page))
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
