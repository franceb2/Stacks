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
    @State private var path = NavigationPath()
    @State private var tourStarted = false

    var body: some View {
        NavigationStack(path: $path) {
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
            .task {
                if !loaded { await load() }
                if DemoTour.enabled && !tourStarted {
                    tourStarted = true
                    await runTour()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
                Task { await load() }
            }
        }
    }

    /// Preview-build only: steps through the main screens, saving a screenshot of each.
    private func runTour() async {
        await DemoTour.pause(4)
        DemoTour.snap("1-home")

        if let comics = libraries.first(where: { $0.type == 1 || $0.type == 5 }) ?? libraries.first {
            path.append(comics)
            await DemoTour.pause(4)
            DemoTour.snap("2-library")

            if let series = try? await client.series(libraryId: comics.id, search: nil, page: 1).first {
                path.append(series)
                await DemoTour.pause(4)
                DemoTour.snap("3-series")

                NotificationCenter.default.post(name: .tourOpenReader, object: nil)
                await DemoTour.pause(5)
                DemoTour.snap("4-comic-reader")
                NotificationCenter.default.post(name: .tourCloseReader, object: nil)
                await DemoTour.pause(2)
            }
        }

        if let manga = libraries.first(where: { $0.type == 0 }),
           let series = try? await client.series(libraryId: manga.id, search: nil, page: 1).first {
            path = NavigationPath()
            await DemoTour.pause(1)
            path.append(manga)
            await DemoTour.pause(1.5)
            path.append(series)
            await DemoTour.pause(4)
            DemoTour.snap("5-manga-volumes")
        }

        if let books = libraries.first(where: { $0.type == 2 || $0.type == 4 }),
           let list = try? await client.series(libraryId: books.id, search: nil, page: 1),
           let novel = list.first(where: { $0.format == MangaFormat.epub.rawValue }) ?? list.first {
            path = NavigationPath()
            await DemoTour.pause(1)
            path.append(books)
            await DemoTour.pause(3)
            DemoTour.snap("6-books")
            path.append(novel)
            await DemoTour.pause(3)
            NotificationCenter.default.post(name: .tourOpenReader, object: nil)
            await DemoTour.pause(5)
            DemoTour.snap("7-book-reader")
            NotificationCenter.default.post(name: .tourCloseReader, object: nil)
            await DemoTour.pause(2)
        }

        path = NavigationPath()
        await DemoTour.pause(2)
        DemoTour.finish()
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
