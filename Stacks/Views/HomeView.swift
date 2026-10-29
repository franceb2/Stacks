import SwiftUI

extension Notification.Name {
    /// Posted whenever read status or progress changes, so lists can refresh.
    static let readingProgressChanged = Notification.Name("readingProgressChanged")
}

struct HomeView: View {
    let client: KavitaClient
    @EnvironmentObject private var session: AppSession

    @State private var libraries: [Library] = []
    @State private var onDeck: [Series] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if !onDeck.isEmpty {
                    Section("Continue reading") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(onDeck) { series in
                                    NavigationLink(value: series) {
                                        SeriesTile(series: series, client: client)
                                            .frame(width: 110)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                Section("Libraries") {
                    ForEach(libraries) { library in
                        NavigationLink(value: library) {
                            Label(library.name, systemImage: library.systemImage)
                        }
                    }
                    if loaded && libraries.isEmpty && error == nil {
                        Text("No libraries yet. Add one in Kavita's web page on your PC.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Stacks")
            .navigationDestination(for: Library.self) { SeriesGridView(library: $0, client: client) }
            .navigationDestination(for: Series.self) { SeriesDetailView(seriesId: $0.id, title: $0.name, client: client) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text(session.serverAddress)
                        Button("Sign out", role: .destructive) { session.signOut() }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .refreshable { await load() }
            .task { if !loaded { await load() } }
            .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
                Task { await load() }
            }
        }
    }

    private func load() async {
        do {
            async let libs = client.libraries()
            async let deck = client.onDeck()
            libraries = try await libs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            onDeck = (try? await deck) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

// MARK: - Shared pieces

struct CoverImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "book.closed").foregroundStyle(.tertiary))
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SeriesTile: View {
    let series: Series
    let client: KavitaClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: client.seriesCoverURL(series.id))
                .overlay(alignment: .topTrailing) {
                    if series.isRead {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .padding(5)
                    }
                }
            if series.pagesRead > 0 && !series.isRead {
                ProgressView(value: series.progress).tint(.orange)
            }
            Text(series.name)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}
