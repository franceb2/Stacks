import SwiftUI

struct ReadingListRoute: Hashable { let list: ReadingList }
struct WantToReadRoute: Hashable {}

/// Lists tab: Want to Read plus your Kavita reading lists.
struct ReadingListsView: View {
    let client: KavitaClient

    @State private var lists: [ReadingList] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var creating = false
    @State private var newTitle = ""
    @State private var created = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NavigationLink(value: WantToReadRoute()) {
                    HStack(spacing: 14) {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.onPrimary)
                            .frame(width: 44, height: 44)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Want to Read").font(.headline).foregroundStyle(Theme.text)
                            Text("Series you've saved for later").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16)

                SectionHeader("Reading lists") {
                    Button { creating = true } label: { Label("New", systemImage: "plus") }
                        .font(.subheadline.weight(.semibold))
                }

                if loaded && lists.isEmpty {
                    VStack(spacing: 8) {
                        Text(error ?? "No reading lists yet").foregroundStyle(Theme.text)
                        if error == nil {
                            Text("Tap New, or long-press any series, volume or issue and choose Add to reading list.")
                                .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                }

                CardGrid {
                    ForEach(lists) { list in
                        NavigationLink(value: ReadingListRoute(list: list)) {
                            KavitaCard(title: list.title,
                                       subtitle: "\(list.itemCount) item\(list.itemCount == 1 ? "" : "s")",
                                       coverURL: client.readingListCoverURL(list.id))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle("Lists")
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .readingListsChanged)) { _ in Task { await load() } }
        .alert("New reading list", isPresented: $creating) {
            TextField("Name", text: $newTitle)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .sensoryFeedback(.success, trigger: created)
    }

    private func load() async {
        do {
            lists = try await client.readingLists()
            error = nil
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server." : error.localizedDescription
        }
        loaded = true
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newTitle = ""
        guard !title.isEmpty else { return }
        do {
            _ = try await client.createReadingList(title: title)
            created += 1
            await load()
        } catch {
            self.error = "Couldn't create the list: \(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let readingListsChanged = Notification.Name("readingListsChanged")
}

/// One reading list: items in order, read through in order, reorder, remove, download.
struct ReadingListDetailView: View {
    let route: ReadingListRoute
    let client: KavitaClient

    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReadingListItem] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var reader: ReaderLaunch?
    @State private var confirmDelete = false

    private var list: ReadingList { route.list }
    private var nextUp: ReadingListItem? { items.first { !$0.isRead } ?? items.first }
    private var readCount: Int { items.filter(\.isRead).count }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(items) { item in
                    row(item).listRowBackground(Theme.card)
                }
                .onDelete { offsets in
                    let removed = offsets.map { items[$0] }
                    items.remove(atOffsets: offsets)
                    Task {
                        for item in removed { try? await client.removeFromReadingList(item) }
                        await load()
                    }
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    let item = items[source]
                    let target = to > source ? to - 1 : to
                    items.move(fromOffsets: from, toOffset: to)
                    Task {
                        try? await client.moveInReadingList(item, to: target)
                        await load()
                    }
                }
            }

            if let error {
                Text(error).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
            }
        }
        .kavitaBackground()
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    Button("Download unread", systemImage: "arrow.down.circle") {
                        for item in items where !item.isRead { download(item) }
                    }
                    Button("Remove read items", systemImage: "checkmark.circle") {
                        Task {
                            try? await client.removeReadItems(list.id)
                            await load()
                        }
                    }
                    Divider()
                    Button("Delete list", systemImage: "trash", role: .destructive) { confirmDelete = true }
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
            ReaderView(client: client, startChapterId: launch.chapterId, readingListId: launch.readingListId)
        }
        .confirmationDialog("Delete \(list.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task {
                    try? await client.deleteReadingList(list.id)
                    NotificationCenter.default.post(name: .readingListsChanged, object: nil)
                    dismiss()
                }
            }
        } message: {
            Text("This removes the list from Kavita. Your books and progress aren't affected.")
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Backdrop(url: client.readingListCoverURL(list.id))
                .frame(height: 230)
            HStack(alignment: .bottom, spacing: 16) {
                CoverImage(url: client.readingListCoverURL(list.id))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 104)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(list.title).font(.title2.bold()).foregroundStyle(Theme.text).lineLimit(2)
                    Text("\(items.count) items · \(readCount) read")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let next = nextUp {
                        Button {
                            reader = ReaderLaunch(chapterId: next.chapterId, readingListId: list.id)
                        } label: {
                            Label(readCount == 0 ? "Start" : "Continue", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .padding(16)
        }
    }

    private func row(_ item: ReadingListItem) -> some View {
        Button {
            reader = ReaderLaunch(chapterId: item.chapterId, readingListId: list.id)
        } label: {
            HStack(spacing: 12) {
                Text("\(item.order + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22)
                CoverImage(url: client.chapterCoverURL(item.chapterId),
                           localFile: downloads.coverURL(chapterId: item.chapterId))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if let badge = downloads.badge(for: item.chapterId) {
                            Image(systemName: { if case .full = badge { return "arrow.down.circle.fill" } else { return "arrow.down.circle" } }())
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                                .background(Circle().fill(Color.black))
                                .offset(x: 4, y: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.seriesName ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(item.title ?? "Chapter").foregroundStyle(item.isRead ? Theme.muted : Theme.text).lineLimit(2)
                    if item.isStarted {
                        ProgressView(value: item.progress).tint(Theme.primary)
                    }
                }
                Spacer(minLength: 0)
                if item.isRead {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Read", systemImage: "book") {
                reader = ReaderLaunch(chapterId: item.chapterId, readingListId: list.id)
            }
            Button("Download", systemImage: "arrow.down.circle") { download(item) }
            if downloads.items[item.chapterId] != nil {
                Button("Remove download", systemImage: "trash") { downloads.delete(item.chapterId) }
            }
            Button("Remove from list", systemImage: "minus.circle", role: .destructive) {
                Task {
                    try? await client.removeFromReadingList(item)
                    await load()
                }
            }
        }
    }

    private func download(_ item: ReadingListItem) {
        downloads.start(client: client, chapterId: item.chapterId, seriesId: item.seriesId,
                        seriesName: item.seriesName ?? "", title: item.title ?? "", range: .all)
    }

    private func load() async {
        do {
            items = try await client.readingListItems(list.id).sorted { $0.order < $1.order }
            error = nil
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server." : error.localizedDescription
        }
        loaded = true
    }
}

/// Kavita's Want to Read list.
struct WantToReadView: View {
    let client: KavitaClient
    @State private var series: [Series] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            CardGrid {
                ForEach(series) { s in
                    NavigationLink(value: SeriesRoute(id: s.id, name: s.name)) {
                        SeriesCard(series: s, client: client)
                    }
                    .buttonStyle(PressableStyle())
                    .zoomSource("series-\(s.id)")
                    .contextMenu {
                        Button("Remove from Want to Read", systemImage: "heart.slash") {
                            Task {
                                try? await client.setWantToRead(s.id, false)
                                await load()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 16)

            if loaded && series.isEmpty {
                VStack(spacing: 8) {
                    Text(error ?? "Nothing saved yet").foregroundStyle(Theme.text)
                    if error == nil {
                        Text("Tap the heart on any series page to save it here.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 60)
            }
        }
        .kavitaBackground()
        .navigationTitle("Want to Read")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            series = try await client.wantToRead()
            error = nil
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server." : error.localizedDescription
        }
        loaded = true
    }
}

/// Pick a reading list (or make a new one) to add a series, volume or issue to.
struct AddToListSheet: View {
    let target: ListTarget
    let title: String
    let client: KavitaClient

    @Environment(\.dismiss) private var dismiss
    @State private var lists: [ReadingList] = []
    @State private var newTitle = ""
    @State private var busy = false
    @State private var error: String?
    @State private var added = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New list name", text: $newTitle)
                            .submitLabel(.done)
                            .onSubmit { Task { await createAndAdd() } }
                        Button("Create") { Task { await createAndAdd() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                    .listRowBackground(Theme.card)
                }
                Section("Your lists") {
                    ForEach(lists) { list in
                        Button {
                            Task { await add(to: list.id) }
                        } label: {
                            HStack {
                                Text(list.title).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(list.itemCount)").foregroundStyle(Theme.muted)
                            }
                        }
                        .disabled(busy)
                        .listRowBackground(Theme.card)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
            }
            .kavitaBackground()
            .navigationTitle("Add \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { lists = (try? await client.readingLists()) ?? [] }
            .sensoryFeedback(.success, trigger: added)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func add(to listId: Int) async {
        busy = true
        defer { busy = false }
        do {
            try await client.addToReadingList(listId, target)
            added += 1
            NotificationCenter.default.post(name: .readingListsChanged, object: nil)
            try? await Task.sleep(nanoseconds: 250_000_000)
            dismiss()
        } catch {
            self.error = "Couldn't add it: \(error.localizedDescription)"
        }
    }

    private func createAndAdd() async {
        let name = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true
        do {
            let list = try await client.createReadingList(title: name)
            busy = false
            await add(to: list.id)
        } catch {
            busy = false
            self.error = "Couldn't create the list: \(error.localizedDescription)"
        }
    }
}

/// What the add-to-list sheet is adding.
struct ListSheetTarget: Identifiable {
    let target: ListTarget
    let title: String
    var id: String { "\(target)" }
}
