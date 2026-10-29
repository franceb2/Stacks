import SwiftUI
import UIKit

/// Page-by-page reader for CBZ/CBR/image chapters (comics and manga).
struct ComicReaderView: View {
    let context: ReaderContext
    let client: KavitaClient
    let actions: ReaderActions

    @AppStorage("readRightToLeft") private var rightToLeft = false
    @State private var page: Int
    @State private var scrubPage: Double
    @State private var showChrome = false
    @StateObject private var store: PageImageStore

    init(context: ReaderContext, client: KavitaClient, actions: ReaderActions) {
        self.context = context
        self.client = client
        self.actions = actions
        _page = State(initialValue: context.startPage)
        _scrubPage = State(initialValue: Double(context.startPage))
        _store = StateObject(wrappedValue: PageImageStore(client: client, chapterId: context.chapterId))
    }

    private var pageCount: Int { max(context.info.pages, 1) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(0..<pageCount, id: \.self) { index in
                    ComicPage(index: index, store: store, onTap: { withAnimation { showChrome.toggle() } })
                        .environment(\.layoutDirection, .leftToRight) // never mirror the art
                        .tag(index)
                }
                EndOfChapterView(actions: actions)
                    .environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(.white)
                    .tag(pageCount)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            .ignoresSafeArea()

            if showChrome { chrome.transition(.opacity) }
        }
        .statusBarHidden(!showChrome)
        .onChange(of: page) { _, newPage in
            scrubPage = Double(min(newPage, pageCount - 1))
            if newPage < pageCount { actions.pageChanged(newPage) }
            store.prefetch(around: newPage, count: pageCount)
        }
        .onAppear { store.prefetch(around: page, count: pageCount) }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { actions.close() } label: {
                    Image(systemName: "xmark").font(.headline).padding(10)
                }
                Text(context.title).font(.headline).lineLimit(1)
                Spacer()
                Menu {
                    Toggle("Right to left (manga)", isOn: $rightToLeft)
                } label: {
                    Image(systemName: "arrow.left.arrow.right").padding(10)
                }
            }
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 6) {
                Text("Page \(min(page, pageCount - 1) + 1) of \(pageCount)")
                    .font(.footnote.monospacedDigit())
                if pageCount > 1 {
                    Slider(value: $scrubPage, in: 0...Double(pageCount - 1), step: 1,
                           onEditingChanged: { editing in
                               if !editing { page = Int(scrubPage) }
                           })
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// One page: loads its image from the store and shows it in a zoomable view.
private struct ComicPage: View {
    let index: Int
    @ObservedObject var store: PageImageStore
    let onTap: () -> Void

    var body: some View {
        Group {
            if let image = store.images[index] {
                ZoomableImage(image: image, onSingleTap: onTap)
            } else if store.failed.contains(index) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Couldn't load page \(index + 1)")
                    Button("Retry") { store.load(index, force: true) }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            }
        }
        .onAppear { store.load(index) }
    }
}

/// Downloads and caches page images, a few pages ahead of the reader.
@MainActor
final class PageImageStore: ObservableObject {
    @Published var images: [Int: UIImage] = [:]
    @Published var failed: Set<Int> = []

    private let client: KavitaClient
    private let chapterId: Int
    private var inFlight: Set<Int> = []

    init(client: KavitaClient, chapterId: Int) {
        self.client = client
        self.chapterId = chapterId
    }

    func load(_ index: Int, force: Bool = false) {
        if force { failed.remove(index) }
        guard images[index] == nil, !inFlight.contains(index), !failed.contains(index) else { return }
        inFlight.insert(index)
        Task {
            defer { inFlight.remove(index) }
            do {
                let data = try await client.pageImageData(chapterId: chapterId, page: index)
                guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                images[index] = image
            } catch {
                failed.insert(index)
            }
        }
    }

    /// Keeps the next few pages ready and drops far-away pages to save memory.
    func prefetch(around page: Int, count: Int) {
        let start = min(max(page, 0), count) // the "Finished" page sits at index == count
        for i in start..<min(start + 3, count) { load(i) }
        if start > 0 { load(start - 1) }
        for key in images.keys where abs(key - page) > 6 { images[key] = nil }
    }
}

/// UIScrollView-backed image with pinch zoom, double-tap zoom and a single-tap callback.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.semanticContentAttribute = .forceLeftToRight
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.semanticContentAttribute = .forceLeftToRight
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scroll.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) { self.onSingleTap = onSingleTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func singleTapped() { onSingleTap() }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}
