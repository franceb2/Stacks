import SwiftUI

// MARK: - Model

/// A group of series you make on the phone, like "Daredevil" or "Spawn". Series join automatically when
/// their name contains one of the shelf's words; you can add or remove any series by hand.
struct Shelf: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Series whose names contain any of these join automatically.
    var keywords: [String]
    var added: [Int] = []
    var removed: [Int] = []

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func matchesWords(_ name: String) -> Bool {
        let n = Self.normalized(name)
        return keywords.contains { k in
            let key = Self.normalized(k)
            return !key.isEmpty && n.contains(key)
        }
    }

    func includes(_ s: Series) -> Bool {
        if removed.contains(s.id) { return false }
        if added.contains(s.id) { return true }
        return matchesWords(s.name)
    }

    func members(in all: [Series]) -> [Series] {
        all.filter(includes).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Host id used to attach reading orders to the shelf.
    var host: String { "shelf:\(id)" }
}

struct ShelfRoute: Hashable { let id: String }

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var shelves: [Shelf] = []

    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shelves.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([Shelf].self, from: data) {
            shelves = saved
        }
    }

    func shelf(_ id: String) -> Shelf? { shelves.first { $0.id == id } }

    func save(_ shelf: Shelf) {
        if let i = shelves.firstIndex(where: { $0.id == shelf.id }) { shelves[i] = shelf } else { shelves.append(shelf) }
        persist()
    }

    func delete(_ shelf: Shelf) {
        shelves.removeAll { $0.id == shelf.id }
        for order in ReadingOrderStore.shared.orders where order.hosts == [shelf.host] {
            ReadingOrderStore.shared.remove(order)
        }
        persist()
    }

    func move(from: IndexSet, to: Int) {
        shelves.move(fromOffsets: from, toOffset: to)
        persist()
    }

    private func persist() {
        try? JSONEncoder().encode(shelves).write(to: Self.file, options: .atomic)
    }
}

// MARK: - Home row

/// "Your shelves" on Home: one big cover per shelf, plus a New shelf card.
struct ShelvesRow: View {
    let client: KavitaClient

    @ObservedObject private var store = ShelfStore.shared
    @State private var all: [Series] = []
    @State private var editing: ShelfEditTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Your shelves")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(store.shelves) { shelf in
                        let members = shelf.members(in: all)
                        NavigationLink(value: ShelfRoute(id: shelf.id)) {
                            ShelfCard(shelf: shelf, members: members, client: client)
                                .frame(width: 118)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button("Edit shelf", systemImage: "pencil") { editing = ShelfEditTarget(shelf: shelf) }
                        }
                    }
                    Button {
                        editing = ShelfEditTarget(shelf: nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.card)
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus").font(.title2.weight(.semibold))
                                        Text("New shelf").font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(Theme.primary)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            Text(store.shelves.isEmpty ? "Group a character's series" : " ")
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        .frame(width: 118)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 16)
            }
        }
        .task { all = await ReadingOrderStore.shared.allSeries(client: client) }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { all = await ReadingOrderStore.shared.allSeries(client: client) }
        }
        .sheet(item: $editing) { target in
            ShelfEditor(client: client, shelf: target.shelf)
        }
    }
}

struct ShelfEditTarget: Identifiable {
    let shelf: Shelf?
    let id = UUID()
}

/// A shelf's cover: its first series' cover, with the shelf name and how much of it you've read.
struct ShelfCard: View {
    let shelf: Shelf
    let members: [Series]
    let client: KavitaClient

    private var progress: Double {
        let pages = members.reduce(0) { $0 + $1.pages }
        return pages > 0 ? Double(members.reduce(0) { $0 + $1.pagesRead }) / Double(pages) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: members.first.flatMap { client.seriesCoverURL($0.id) })
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if members.count > 1 {
                    Text("\(members.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.primary, in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.5))
                            Rectangle().fill(Theme.primary).frame(width: geo.size.width * min(progress, 1))
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            Text(shelf.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(members.count == 1 ? "1 series" : "\(members.count) series")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Shelf page

struct ShelfView: View {
    let route: ShelfRoute
    let client: KavitaClient

    private enum Tab: String { case series = "Series", order = "Reading order" }

    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var orderStore = ReadingOrderStore.shared
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hideReadIssues") private var hideRead = false

    @State private var members: [Series] = []
    @State private var details: [Int: SeriesDetail] = [:]
    @State private var loaded = false
    @State private var tab: Tab?
    @State private var editing: ShelfEditTarget?
    @State private var showImport = false
    @State private var confirmDelete = false
    @State private var reader: ReaderLaunch?
    @State private var queued = 0

    private var shelf: Shelf? { store.shelf(route.id) }

    private var orders: [ReadingOrder] {
        guard let shelf else { return [] }
        return orderStore.orders(forShelf: shelf.id, seriesNames: members.map(\.name))
    }

    private var chapters: [Chapter] { members.flatMap { details[$0.id]?.allChapters ?? [] } }
    private var readCount: Int { chapters.filter(\.isRead).count }

    private var currentTab: Tab { tab ?? (orders.isEmpty ? .series : .order) }

    var body: some View {
        ScrollView {
            if let shelf {
                VStack(alignment: .leading, spacing: 18) {
                    header(shelf)
                    tabBar
                    switch currentTab {
                    case .series: seriesGrid
                    case .order: orderTab(shelf)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .kavitaBackground()
        .navigationTitle(shelf?.name ?? "Shelf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit shelf", systemImage: "pencil") { editing = ShelfEditTarget(shelf: shelf) }
                    Button("Add reading order…", systemImage: "list.number") { showImport = true }
                    Divider()
                    Button("Download all unread", systemImage: "arrow.down.circle.dotted") { downloadUnread() }
                        .disabled(chapters.allSatisfy(\.isRead))
                    Divider()
                    Button("Delete shelf", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: shelf) { await load() }
        .refreshable { await load(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await load() }
        }
        .sheet(item: $editing) { target in ShelfEditor(client: client, shelf: target.shelf) }
        .sheet(isPresented: $showImport) {
            if let shelf {
                ImportReadingOrderView(client: client, seriesName: shelf.name, hostId: shelf.host) { order in
                    ReadingOrderSection.show(order.id, on: shelf.host)
                    tab = .order
                }
            }
        }
        .fullScreenCover(item: $reader, onDismiss: {
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId, readingListId: launch.readingListId,
                       startPage: launch.page, order: launch.order)
        }
        .confirmationDialog("Delete this shelf?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete shelf", role: .destructive) {
                if let shelf { store.delete(shelf) }
                dismiss()
            }
        } message: {
            Text("Your comics, downloads and reading progress stay as they are. Reading orders added to this shelf are removed.")
        }
        .sensoryFeedback(.success, trigger: queued)
    }

    private func header(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                CoverImage(url: members.first.flatMap { client.seriesCoverURL($0.id) })
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 96)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(shelf.name).font(.title2.bold()).foregroundStyle(Theme.text)
                    Text(members.count == 1 ? "1 series" : "\(members.count) series")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    if !chapters.isEmpty {
                        Text("\(readCount) of \(chapters.count) issues read")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        ProgressView(value: Double(readCount), total: Double(max(chapters.count, 1)))
                            .tint(Theme.primary)
                    } else if !loaded {
                        ProgressView().tint(Theme.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach([Tab.series, Tab.order], id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 6) {
                            Text(t.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(currentTab == t ? Theme.text : Theme.muted)
                            Rectangle().fill(currentTab == t ? Theme.primary : Color.clear).frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) { hideRead.toggle() }
            } label: {
                Label(hideRead ? "Unread" : "All", systemImage: hideRead ? "eye.slash" : "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hideRead ? Theme.primary : Theme.muted)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    @ViewBuilder
    private var seriesGrid: some View {
        let shown = members.filter { !hideRead || !$0.isRead }
        if loaded && members.isEmpty {
            Text("No series on this shelf yet. Tap ⋯ → Edit shelf to add some.")
                .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 16)
        }
        CardGrid {
            ForEach(shown) { series in
                let ids = (details[series.id]?.allChapters ?? []).map(\.id)
                NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                    KavitaCard(title: series.name, subtitle: subtitle(series),
                               coverURL: client.seriesCoverURL(series.id),
                               progress: series.progress, unread: series.isUnread,
                               downloaded: ids.isEmpty ? nil : downloads.badge(forChapters: ids))
                }
                .buttonStyle(PressableStyle())
                .zoomSource("series-\(series.id)")
            }
        }
    }

    private func subtitle(_ s: Series) -> String {
        guard let d = details[s.id] else { return s.libraryName ?? "" }
        let all = d.allChapters
        let read = all.filter(\.isRead).count
        return read == all.count && !all.isEmpty ? "All read" : "\(read) of \(all.count) read"
    }

    @ViewBuilder
    private func orderTab(_ shelf: Shelf) -> some View {
        if orders.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "list.number").font(.largeTitle).foregroundStyle(Theme.muted)
                Text("No reading order yet").font(.headline).foregroundStyle(Theme.text)
                Text("Add one from a Google Doc or Sheet, an Excel, CSV or Word file, a web page, or pasted text. It can mix every series on this shelf.")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button {
                    showImport = true
                } label: {
                    Label("Add reading order", systemImage: "plus").frame(minWidth: 200)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.top, 20)
        } else {
            ReadingOrderSection(orders: orders, seriesName: shelf.host, client: client, hideRead: hideRead,
                                open: { chapterId, ids in reader = ReaderLaunch(chapterId: chapterId, order: ids) },
                                addOrder: { showImport = true })
        }
    }

    private func load(force: Bool = false) async {
        guard let shelf else { return }
        let all = await ReadingOrderStore.shared.allSeries(client: client, force: force)
        members = shelf.members(in: all)
        var found: [Int: SeriesDetail] = force ? [:] : details
        let ids = members.map(\.id)
        var i = 0
        while i < ids.count {
            let batch = Array(ids[i..<min(i + 4, ids.count)])
            i += batch.count
            let results = await withTaskGroup(of: (Int, SeriesDetail?).self) { group -> [(Int, SeriesDetail?)] in
                for id in batch { group.addTask { (id, try? await client.seriesDetail(id: id)) } }
                var out: [(Int, SeriesDetail?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, d) in results { if let d { found[id] = d } }
        }
        details = found
        loaded = true
    }

    private func downloadUnread() {
        for series in members {
            for c in details[series.id]?.allChapters ?? [] where !c.isRead && downloads.items[c.id] == nil {
                downloads.start(client: client, chapter: c, seriesId: series.id, seriesName: series.name,
                                title: c.displayName, range: .all)
            }
        }
        queued += 1
    }
}

// MARK: - Editor

/// Create or edit a shelf: its name, the words that pull series in, and any series added or removed by hand.
struct ShelfEditor: View {
    let client: KavitaClient
    let original: Shelf?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Shelf
    @State private var wordsText: String
    @State private var wordsEdited: Bool
    @State private var all: [Series] = []
    @State private var search = ""
    @State private var loaded = false

    init(client: KavitaClient, shelf: Shelf?) {
        self.client = client
        self.original = shelf
        let start = shelf ?? Shelf(id: UUID().uuidString, name: "", keywords: [])
        _draft = State(initialValue: start)
        _wordsText = State(initialValue: start.keywords.joined(separator: ", "))
        _wordsEdited = State(initialValue: shelf != nil)
    }

    private var members: [Series] { draft.members(in: all) }

    private var listed: [Series] {
        let q = Shelf.normalized(search)
        let filtered = q.isEmpty ? all : all.filter { Shelf.normalized($0.name).contains(q) }
        let inShelf = filtered.filter(draft.includes)
        let others = filtered.filter { !draft.includes($0) }
        return inShelf + (q.isEmpty ? [] : others)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Daredevil", text: $draft.name)
                        .onChange(of: draft.name) { _, name in
                            if !wordsEdited {
                                wordsText = name
                                applyWords()
                            }
                        }
                    TextField("Words to match", text: $wordsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: wordsText) { _, text in
                            if text != draft.name { wordsEdited = true }
                            applyWords()
                        }
                } footer: {
                    Text("Series whose names contain any of these words join automatically, now and when you add new ones. Separate words with commas, like \"spawn, sam and twitch, haunt\".")
                }
                .listRowBackground(Theme.card)

                Section {
                    if !loaded {
                        HStack(spacing: 10) { ProgressView(); Text("Loading your library…").foregroundStyle(Theme.muted) }
                    } else if listed.isEmpty {
                        Text(search.isEmpty ? "Type a name or words above, or search below to add series."
                                            : "No series match \"\(search)\".")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(listed) { series in
                        Button {
                            toggle(series)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: client.seriesCoverURL(series.id))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(series.name).foregroundStyle(Theme.text).lineLimit(2)
                                    if draft.added.contains(series.id) {
                                        Text("Added by hand").font(.caption2).foregroundStyle(Theme.muted)
                                    }
                                }
                                Spacer()
                                Image(systemName: draft.includes(series) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draft.includes(series) ? Theme.primary : Theme.muted)
                                    .font(.title3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(search.isEmpty ? "On this shelf (\(members.count))" : "Search results")
                } footer: {
                    Text("Tap to add or remove. Search to find series without the words in their name, like Hellspawn on a Spawn shelf.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .kavitaBackground()
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Add any series")
            .navigationTitle(original == nil ? "New shelf" : "Edit shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        ShelfStore.shared.save(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                all = await ReadingOrderStore.shared.allSeries(client: client)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                loaded = true
            }
        }
    }

    private func applyWords() {
        draft.keywords = wordsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func toggle(_ s: Series) {
        if draft.includes(s) {
            draft.added.removeAll { $0 == s.id }
            if draft.matchesWords(s.name) && !draft.removed.contains(s.id) { draft.removed.append(s.id) }
        } else {
            draft.removed.removeAll { $0 == s.id }
            if !draft.matchesWords(s.name) && !draft.added.contains(s.id) { draft.added.append(s.id) }
        }
    }
}
