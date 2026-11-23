import SwiftUI

/// Your favorite series, kept as a "Favorites" collection in Kavita so it matches Kavita's website.
/// The star on a series page adds or removes it; Home shows them in a row.
@MainActor
final class Favorites: ObservableObject {
    static let shared = Favorites()
    static let title = "Favorites"

    @Published private(set) var series: [Series] = []
    @Published private(set) var ids: Set<Int> = []
    @Published private(set) var collection: KavitaCollection?
    @Published private(set) var loaded = false

    func contains(_ seriesId: Int) -> Bool { ids.contains(seriesId) }

    func refresh(client: KavitaClient) async {
        guard let all = try? await client.collections() else { return }
        collection = all.first { $0.title.caseInsensitiveCompare(Self.title) == .orderedSame }
        guard let collection else {
            series = []
            ids = []
            loaded = true
            return
        }
        var list: [Series] = []
        var page = 1
        while page < 50, let batch = try? await client.seriesInCollection(collection.id, page: page) {
            list.append(contentsOf: batch)
            if batch.count < 60 { break }
            page += 1
        }
        series = list
        ids = Set(list.map(\.id))
        loaded = true
    }

    /// Adds or removes a series. Updates right away, then confirms with Kavita.
    func toggle(seriesId: Int, client: KavitaClient) async throws {
        if ids.contains(seriesId) {
            ids.remove(seriesId)
            series.removeAll { $0.id == seriesId }
            if let collection { try await client.removeFromCollection(collection, seriesIds: [seriesId]) }
        } else {
            ids.insert(seriesId)
            // Id 0 makes Kavita create the "Favorites" collection the first time.
            try await client.addToCollection(seriesId: seriesId, collectionId: collection?.id ?? 0, title: Self.title)
        }
        await refresh(client: client)
    }
}

/// "Favorites" on Home: your starred series.
struct FavoritesRow: View {
    let client: KavitaClient
    @ObservedObject private var favorites = Favorites.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Favorites") {
                if let collection = favorites.collection, favorites.series.count > 3 {
                    NavigationLink("See all", value: CollectionRoute(collection: collection))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            if favorites.series.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "star").foregroundStyle(Theme.primary)
                    Text(favorites.loaded ? "Tap the star on any series to add it here." : "Loading…")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(favorites.series) { s in
                            NavigationLink(value: SeriesRoute(id: s.id, name: s.name)) {
                                SeriesCard(series: s, client: client).frame(width: 118)
                            }
                            .buttonStyle(PressableStyle())
                            .zoomSource("series-\(s.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await favorites.refresh(client: client) }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await favorites.refresh(client: client) }
        }
    }
}
