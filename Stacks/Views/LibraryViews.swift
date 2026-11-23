import SwiftUI

/// Kavita's side-nav list of libraries, as a tab.
struct LibrariesView: View {
    let client: KavitaClient

    @State private var libraries: [Library] = []
    @State private var error: String?
    @State private var loaded = false
    @ObservedObject private var scanner = LibraryScanner.shared

    var body: some View {
        List {
            if scanner.message != nil {
                Section {
                    ScanBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
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
                    .contextMenu {
                        Button("Scan library", systemImage: "arrow.triangle.2.circlepath") {
                            scanner.scan(client: client, library: library)
                        }
                        Button("Force scan (re-read every folder)", systemImage: "arrow.clockwise.circle") {
                            scanner.scan(client: client, library: library, force: true)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Scan", systemImage: "arrow.triangle.2.circlepath") {
                            scanner.scan(client: client, library: library)
                        }
                        .tint(Theme.primary)
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Scan all libraries", systemImage: "arrow.triangle.2.circlepath") {
                        scanner.scan(client: client, library: nil)
                    }
                    Button("Force scan all (re-read every folder)", systemImage: "arrow.clockwise.circle") {
                        scanner.scan(client: client, library: nil, force: true)
                    }
                    if !libraries.isEmpty {
                        Section("Scan one library") {
                            ForEach(libraries) { library in
                                Button(library.name) { scanner.scan(client: client, library: library) }
                            }
                        }
                    }
                } label: {
                    if scanner.scanning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(scanner.scanning)
                .accessibilityLabel("Scan for new files")
            }
        }
        .animation(.easeOut(duration: 0.2), value: scanner.message)
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await load() }
        }
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
    @ObservedObject private var scanner = LibraryScanner.shared

    private let pageSize = 60
    private var sort: SeriesSort { SeriesSort(rawValue: sortRaw) ?? .name }
    private var title: String { route.library?.name ?? "All series" }

    var body: some View {
        ScrollView {
            if scanner.message != nil {
                ScanBanner().padding(.horizontal, 16).padding(.top, 12)
            }
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
                    Divider()
                    Button(route.library == nil ? "Scan all libraries" : "Scan this library",
                           systemImage: "arrow.triangle.2.circlepath") {
                        scanner.scan(client: client, library: route.library)
                    }
                    .disabled(scanner.scanning)
                    Button("Force scan (re-read every folder)", systemImage: "arrow.clockwise.circle") {
                        scanner.scan(client: client, library: route.library, force: true)
                    }
                    .disabled(scanner.scanning)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: "\(search)|\(sortRaw)") {
            if !search.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable {
            ImageCache.shared.markAllStale()
            await reload()
        }
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
