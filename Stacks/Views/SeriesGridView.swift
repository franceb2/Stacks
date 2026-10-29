import SwiftUI

struct SeriesGridView: View {
    let library: Library
    let client: KavitaClient

    @State private var items: [Series] = []
    @State private var page = 1
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var search = ""
    @State private var error: String?
    @State private var generation = 0

    private let pageSize = 60
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { series in
                    NavigationLink(value: series) {
                        SeriesTile(series: series, client: client)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Mark all as read", systemImage: "checkmark.circle") { mark(series, read: true) }
                        Button("Mark all as unread", systemImage: "circle") { mark(series, read: false) }
                    }
                    .onAppear {
                        if series.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(16)

            if loading { ProgressView().padding() }
            if let error { Text(error).foregroundStyle(.red).padding() }
            if !loading && items.isEmpty && error == nil {
                Text(search.isEmpty ? "Nothing in this library yet." : "No matches.")
                    .foregroundStyle(.secondary).padding(.top, 40)
            }
        }
        .navigationTitle(library.name)
        .searchable(text: $search, prompt: "Search \(library.name)")
        .task(id: search) {
            // small debounce so typing doesn't fire a request per keystroke
            if !search.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        generation += 1 // any request still in flight from before is ignored
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
            let batch = try await client.series(libraryId: library.id, search: search, page: page, pageSize: pageSize)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: batch.filter { !known.contains($0.id) })
            reachedEnd = batch.count < pageSize
            page += 1
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func mark(_ series: Series, read: Bool) {
        Task {
            try? await client.markSeries(series.id, read: read)
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }
    }
}
