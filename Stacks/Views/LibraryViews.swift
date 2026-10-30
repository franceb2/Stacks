import SwiftUI

/// Kavita's side-nav list of libraries, as a tab.
struct LibrariesView: View {
    let client: KavitaClient

    @State private var libraries: [Library] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: LibraryRoute(library: nil)) {
                    Label("All series", systemImage: "square.grid.2x2.fill")
                }
                .listRowBackground(Theme.card)
            }
            Section("Libraries") {
                ForEach(libraries) { library in
                    NavigationLink(value: LibraryRoute(library: library)) {
                        Label(library.name, systemImage: library.systemImage)
                    }
                    .listRowBackground(Theme.card)
                }
                if loaded && libraries.isEmpty {
                    Text(error ?? "No libraries yet. Add one in Kavita on your PC.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Theme.card)
                }
            }
        }
        .kavitaBackground()
        .navigationTitle("Library")
        .refreshable { await load() }
        .task { if !loaded { await load() } }
    }

    private func load() async {
        do {
            libraries = try await client.libraries()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            error = nil
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server right now." : error.localizedDescription
        }
        loaded = true
    }
}

/// A library (or all series) as a grid of Kavita cards, with search and sort.
struct SeriesGridView: View {
    let route: LibraryRoute
    let client: KavitaClient

    @AppStorage("librarySort") private var sortRaw = SeriesSort.name.rawValue
    @State private var items: [Series] = []
    @State private var page = 1
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var search = ""
    @State private var error: String?
    @State private var generation = 0
    @State private var listTarget: ListSheetTarget?

    private let pageSize = 60
    private var sort: SeriesSort { SeriesSort(rawValue: sortRaw) ?? .name }
    private var title: String { route.library?.name ?? "All series" }

    var body: some View {
        ScrollView {
            CardGrid {
                ForEach(items) { series in
                    NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                        SeriesCard(series: series, client: client)
                    }
                    .buttonStyle(PressableStyle())
                    .zoomSource("series-\(series.id)")
                    .contextMenu {
                        Button("Mark as read", systemImage: "checkmark.circle") { mark(series, read: true) }
                        Button("Mark as unread", systemImage: "circle") { mark(series, read: false) }
                        Button("Want to Read", systemImage: "heart") {
                            Task { try? await client.setWantToRead(series.id, true) }
                        }
                        Button("Add to reading list…", systemImage: "text.badge.plus") {
                            listTarget = ListSheetTarget(target: .series(series.id), title: series.name)
                        }
                    }
                    .onAppear {
                        if series.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(.vertical, 16)

            if loading { ProgressView().padding() }
            if let error { Text(error).foregroundStyle(Theme.danger).padding() }
            if !loading && items.isEmpty && error == nil {
                Text(search.isEmpty ? "Nothing here yet." : "No matches.")
                    .foregroundStyle(Theme.muted).padding(.top, 40)
            }
        }
        .kavitaBackground()
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Search \(title)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(SeriesSort.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: "\(search)|\(sortRaw)") {
            if !search.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await reload() }
        }
        .sheet(item: $listTarget) { item in
            AddToListSheet(target: item.target, title: item.title, client: client)
        }
    }

    private func reload() async {
        generation += 1
        page = 1
        reachedEnd = false
        loading = false
        items = []
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, !reachedEnd else { return }
        let gen = generation
        loading = true
        defer { if gen == generation { loading = false } }
        do {
            let batch = try await client.series(libraryId: route.library?.id, search: search, sort: sort,
                                                page: page, pageSize: pageSize)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: batch.filter { !known.contains($0.id) })
            reachedEnd = batch.count < pageSize
            page += 1
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = KavitaClient.isOffline(error) ? "Can't reach your server right now." : error.localizedDescription
        }
    }

    private func mark(_ series: Series, read: Bool) {
        Task {
            try? await client.markSeries(series.id, read: read)
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }
    }
}
