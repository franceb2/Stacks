import SwiftUI
import UIKit

/// Kavita-style reader for comics, manga and PDFs: left-to-right or right-to-left paging,
/// up-to-down paging, or continuous webtoon scrolling. Tap the left or right side to turn pages,
/// tap the middle to show the menu.
struct ComicReaderView: View {
    let context: ReaderContext
    let client: KavitaClient
    let actions: ReaderActions

    @State private var prefs: ComicPrefs
    @State private var page: Int
    @State private var scrubPage: Double
    @State private var showChrome = false
    @State private var showSettings = false
    @State private var spreadActive = false
    @StateObject private var store: PageImageStore

    init(context: ReaderContext, client: KavitaClient, actions: ReaderActions) {
        self.context = context
        self.client = client
        self.actions = actions
        _prefs = State(initialValue: ReaderPrefsStore.comic(seriesId: context.info.seriesId,
                                                             libraryType: context.info.libraryType))
        _page = State(initialValue: context.startPage)
        _scrubPage = State(initialValue: Double(context.startPage))
        _store = StateObject(wrappedValue: PageImageStore(client: client, chapterId: context.chapterId,
                                                          offline: context.offline))
    }

    private var pageCount: Int { max(context.info.pages, 1) }
    private var shownPage: Int { min(page, pageCount - 1) }

    /// Binding used by the vertical scroll modes.
    private var scrollBinding: Binding<Int?> {
        Binding(get: { page }, set: { if let value = $0 { page = value } })
    }

    var body: some View {
        ZStack {
            prefs.background.color.ignoresSafeArea()

            switch prefs.mode {
            case .leftRight: horizontalPager
            case .upDown: verticalPager
            case .webtoon: webtoon
            }

            if showChrome { chrome.transition(.opacity) }
        }
        .statusBarHidden(!showChrome)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: page) { _, _ in prefs.mode != .webtoon }
        .onChange(of: page) { _, newPage in
            scrubPage = Double(min(newPage, pageCount - 1))
            if newPage < pageCount { actions.pageChanged(newPage) }
            store.prefetch(around: newPage, count: pageCount)
        }
        .onChange(of: prefs) { _, value in ReaderPrefsStore.setComic(value, seriesId: context.info.seriesId) }
        .onAppear { store.prefetch(around: page, count: pageCount) }
        .sheet(isPresented: $showSettings) {
            ComicSettingsSheet(prefs: $prefs)
                .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .tourShowMenu)) { _ in showChrome = true }
        .onReceive(NotificationCenter.default.publisher(for: .tourReaderSettings)) { _ in showSettings = true }
        .onReceive(NotificationCenter.default.publisher(for: .tourCloseReader)) { _ in showSettings = false }
    }

    // MARK: Modes

    private var horizontalPager: some View {
        GeometryReader { geo in
            let sideways = geo.size.width > geo.size.height
            Group {
                if prefs.doublePage && sideways && pageCount > 2 {
                    spreadPager
                } else {
                    singlePager
                }
            }
            .onAppear { spreadActive = prefs.doublePage && sideways && pageCount > 2 }
            .onChange(of: sideways) { _, value in spreadActive = prefs.doublePage && value && pageCount > 2 }
            .onChange(of: prefs.doublePage) { _, value in spreadActive = value && sideways && pageCount > 2 }
        }
        .ignoresSafeArea()
    }

    /// Cover on its own, then pages in pairs.
    private var spreads: [[Int]] {
        var out: [[Int]] = [[0]]
        var i = 1
        while i < pageCount {
            out.append(i + 1 < pageCount ? [i, i + 1] : [i])
            i += 2
        }
        return out
    }

    private func spreadIndex(for page: Int) -> Int {
        if page >= pageCount { return spreads.count }
        return page == 0 ? 0 : (page + 1) / 2
    }

    private var spreadPager: some View {
        let list = spreads
        let selection = Binding<Int>(
            get: { spreadIndex(for: page) },
            set: { i in page = i >= list.count ? pageCount : (list[i].last ?? 0) }
        )
        return TabView(selection: selection) {
            ForEach(list.indices, id: \.self) { i in
                SpreadPage(pages: list[i], store: store, rightToLeft: prefs.rightToLeft, offline: context.offline,
                           onTap: handleTap)
                    .environment(\.layoutDirection, .leftToRight)
                    .tag(i)
            }
            EndOfChapterView(actions: actions)
                .environment(\.layoutDirection, .leftToRight)
                .tag(list.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, prefs.rightToLeft ? .rightToLeft : .leftToRight)
    }

    private var singlePager: some View {
        TabView(selection: $page) {
            ForEach(0..<pageCount, id: \.self) { index in
                ComicPage(index: index, store: store, scaling: prefs.scaling, offline: context.offline,
                          onTap: handleTap)
                    .environment(\.layoutDirection, .leftToRight) // never mirror the art
                    .tag(index)
            }
            EndOfChapterView(actions: actions)
                .environment(\.layoutDirection, .leftToRight)
                .tag(pageCount)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, prefs.rightToLeft ? .rightToLeft : .leftToRight)
        .ignoresSafeArea()
    }

    private var verticalPager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    ComicPage(index: index, store: store, scaling: prefs.scaling, offline: context.offline,
                              onTap: handleTap)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
                EndOfChapterView(actions: actions)
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(pageCount)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: scrollBinding)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    private var webtoon: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    WebtoonPage(index: index, store: store, offline: context.offline)
                        .id(index)
                }
                EndOfChapterView(actions: actions)
                    .frame(height: 420)
                    .id(pageCount)
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: scrollBinding, anchor: .top)
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showChrome.toggle() } }
        .ignoresSafeArea()
    }

    // MARK: Taps

    /// `x` is where the tap landed, from 0 (left edge) to 1 (right edge).
    private func handleTap(_ x: CGFloat) {
        if !prefs.tapToTurn || (x > 0.3 && x < 0.7) {
            withAnimation(.easeOut(duration: 0.15)) { showChrome.toggle() }
            return
        }
        if showChrome {
            withAnimation(.easeOut(duration: 0.15)) { showChrome = false }
            return
        }
        let leftSide = x <= 0.3
        let forward = (prefs.mode == .leftRight && prefs.rightToLeft) ? leftSide : !leftSide
        withAnimation(.easeInOut(duration: 0.2)) {
            if spreadActive && prefs.mode == .leftRight {
                let list = spreads
                let i = spreadIndex(for: page) + (forward ? 1 : -1)
                if i < 0 { return }
                page = i >= list.count ? pageCount : (list[i].last ?? 0)
            } else if forward {
                page = min(page + 1, pageCount)
            } else {
                page = max(page - 1, 0)
            }
        }
    }

    // MARK: Menu

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { actions.close() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.seriesName).font(.headline).lineLimit(1)
                    if !context.chapterTitle.isEmpty {
                        Text(context.chapterTitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if context.offline {
                    Image(systemName: "wifi.slash").foregroundStyle(Theme.muted)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.headline).frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.black.opacity(0.88))

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Button { actions.goToPrevious() } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(actions.previousChapterId == nil)

                    if pageCount > 1 {
                        Slider(value: $scrubPage, in: 0...Double(pageCount - 1), step: 1,
                               onEditingChanged: { editing in
                                   if !editing { page = Int(scrubPage) }
                               })
                            .environment(\.layoutDirection,
                                         prefs.mode == .leftRight && prefs.rightToLeft ? .rightToLeft : .leftToRight)
                    } else {
                        Spacer()
                    }

                    Button { actions.goToNext() } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(actions.nextChapterId == nil)
                }
                Text("\(Int(scrubPage) + 1) / \(pageCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(Color.black.opacity(0.88))
        }
        .foregroundStyle(.white)
        .tint(Theme.primary)
    }
}

/// Kavita's reader settings, remembered per series.
struct ComicSettingsSheet: View {
    @Binding var prefs: ComicPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var savedDefault = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading mode") {
                    Picker("Reading mode", selection: $prefs.mode) {
                        ForEach(ReadingMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Right to left (manga)", isOn: $prefs.rightToLeft)
                        .disabled(prefs.mode != .leftRight)
                    Toggle("Two pages when sideways", isOn: $prefs.doublePage)
                        .disabled(prefs.mode != .leftRight)
                    Toggle("Tap sides to turn pages", isOn: $prefs.tapToTurn)
                        .disabled(prefs.mode == .webtoon)
                    Picker("Image scaling", selection: $prefs.scaling) {
                        ForEach(ScalingMode.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(prefs.mode == .webtoon)
                    Picker("Background", selection: $prefs.background) {
                        ForEach(ReaderBackground.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button(savedDefault ? "Saved as default" : "Use these for every series") {
                        ReaderPrefsStore.defaultComic = prefs
                        savedDefault = true
                    }
                    .disabled(savedDefault)
                } footer: {
                    Text("Changes here are remembered for this series.")
                }
                .listRowBackground(Theme.card)
            }
            .kavitaBackground()
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pages

/// One page for the paged modes: zoomable, with tap zones.
private struct ComicPage: View {
    let index: Int
    @ObservedObject var store: PageImageStore
    let scaling: ScalingMode
    let offline: Bool
    let onTap: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            if let image = store.images[index] {
                ZoomableImage(image: image, scaling: scaling, onTap: onTap) // handles its own taps
            } else if store.failed.contains(index) {
                PageProblem(index: index, offline: offline) { store.load(index, force: true) }
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        onTap(geo.size.width > 0 ? location.x / geo.size.width : 0.5)
                    }
            }
        }
        .onAppear { store.load(index) }
    }
}

/// Two pages side by side (or the cover alone), for sideways reading.
private struct SpreadPage: View {
    let pages: [Int]
    @ObservedObject var store: PageImageStore
    let rightToLeft: Bool
    let offline: Bool
    let onTap: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                let ordered = rightToLeft ? Array(pages.reversed()) : pages
                ForEach(ordered.indices, id: \.self) { position in
                    half(ordered[position],
                         alignment: pages.count == 1 ? .center : (position == 0 ? .trailing : .leading))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                onTap(geo.size.width > 0 ? location.x / geo.size.width : 0.5)
            }
        }
        .onAppear { for i in pages { store.load(i) } }
    }

    @ViewBuilder
    private func half(_ index: Int, alignment: Alignment) -> some View {
        Group {
            if let image = store.images[index] {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if store.failed.contains(index) {
                PageProblem(index: index, offline: offline) { store.load(index, force: true) }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// One page in webtoon mode: full width, natural height.
private struct WebtoonPage: View {
    let index: Int
    @ObservedObject var store: PageImageStore
    let offline: Bool

    var body: some View {
        Group {
            if let image = store.images[index] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Color.clear
                    if store.failed.contains(index) {
                        PageProblem(index: index, offline: offline) { store.load(index, force: true) }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(store.aspect(index), contentMode: .fit)
            }
        }
        .onAppear { store.load(index) }
    }
}

private struct PageProblem: View {
    let index: Int
    let offline: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: offline ? "arrow.down.circle" : "exclamationmark.triangle").font(.title2)
            Text(offline ? "Page \(index + 1) isn't downloaded" : "Couldn't load page \(index + 1)")
            Button("Try again", action: retry).buttonStyle(SecondaryButtonStyle())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image loading

/// Loads page images from the phone when downloaded, otherwise from Kavita, a few pages ahead.
@MainActor
final class PageImageStore: ObservableObject {
    @Published var images: [Int: UIImage] = [:]
    @Published var failed: Set<Int> = []

    private let client: KavitaClient
    private let chapterId: Int
    private let offline: Bool
    private var inFlight: Set<Int> = []
    private var sizes: [Int: CGSize] = [:]

    init(client: KavitaClient, chapterId: Int, offline: Bool) {
        self.client = client
        self.chapterId = chapterId
        self.offline = offline
    }

    /// Width / height of a page, once known; used to size placeholders in webtoon mode.
    func aspect(_ index: Int) -> CGFloat {
        guard let size = sizes[index] ?? sizes.values.first, size.height > 0 else { return 2.0 / 3.0 }
        return size.width / size.height
    }

    func load(_ index: Int, force: Bool = false) {
        if force { failed.remove(index) }
        guard images[index] == nil, !inFlight.contains(index), !failed.contains(index) else { return }
        inFlight.insert(index)
        let chapterId = chapterId
        let client = client
        let offline = offline
        let local = Downloads.shared.imageURL(chapterId: chapterId, page: index)
        Task {
            defer { inFlight.remove(index) }
            let image: UIImage? = await Task.detached(priority: .userInitiated) {
                if let local, let data = try? Data(contentsOf: local), let img = UIImage(data: data) {
                    return img.preparingForDisplay() ?? img
                }
                if offline { return nil }
                guard let data = try? await client.pageImageData(chapterId: chapterId, page: index),
                      let img = UIImage(data: data) else { return nil }
                return img.preparingForDisplay() ?? img
            }.value
            if let image {
                images[index] = image
                sizes[index] = image.size
            } else {
                failed.insert(index)
            }
        }
    }

    /// Keeps nearby pages ready and drops far-away pages to save memory.
    func prefetch(around page: Int, count: Int) {
        let start = min(max(page, 0), count)
        for i in start..<min(start + 4, count) { load(i) }
        if start > 0 { load(start - 1) }
        for key in images.keys where abs(key - page) > 8 { images[key] = nil }
    }
}

// MARK: - Zoomable page

/// UIScrollView-backed page: pinch and double-tap zoom, Kavita's scaling options, and tap zones.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let scaling: ScalingMode
    let onTap: (CGFloat) -> Void

    func makeUIView(context: Context) -> PageScrollView {
        let view = PageScrollView()
        view.onTap = onTap
        view.scaling = scaling
        view.image = image
        return view
    }

    func updateUIView(_ view: PageScrollView, context: Context) {
        view.onTap = onTap
        view.scaling = scaling
        if view.image !== image { view.image = image }
    }
}

final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    var onTap: ((CGFloat) -> Void)?
    private var needsBaseLayout = true
    private var laidOutFor = CGSize.zero

    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            needsBaseLayout = true
            setNeedsLayout()
        }
    }

    var scaling: ScalingMode = .automatic {
        didSet {
            if oldValue != scaling {
                needsBaseLayout = true
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        semanticContentAttribute = .forceLeftToRight
        imageView.contentMode = .scaleToFill
        imageView.semanticContentAttribute = .forceLeftToRight
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsBaseLayout || laidOutFor != bounds.size { layoutBase() }
    }

    private func layoutBase() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        needsBaseLayout = false
        laidOutFor = bounds.size
        zoomScale = 1
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }

        let b = bounds.size
        let s = image.size
        let size: CGSize
        switch scaling {
        case .automatic:
            let r = min(b.width / s.width, b.height / s.height)
            size = CGSize(width: s.width * r, height: s.height * r)
        case .fitWidth:
            size = CGSize(width: b.width, height: s.height * b.width / s.width)
        case .fitHeight:
            size = CGSize(width: s.width * b.height / s.height, height: b.height)
        case .original:
            size = CGSize(width: s.width * image.scale / UIScreen.main.scale,
                          height: s.height * image.scale / UIScreen.main.scale)
        }
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    private func centerContent() {
        let b = bounds.size
        let c = imageView.frame.size
        let x = max(0, (b.width - c.width) / 2)
        let y = max(0, (b.height - c.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x - contentOffset.x
        onTap?(bounds.width > 0 ? x / bounds.width : 0.5)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}
