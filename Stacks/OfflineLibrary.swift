import Foundation
import SwiftUI

/// Saves the whole library for offline browsing: every library list, the home rows, reading lists,
/// Want to Read, each series page, and the covers. Runs in the background when the server is reachable.
/// Series pages and covers for everything are only fetched on Wi-Fi; on cellular just the essentials.
@MainActor
final class OfflineLibrary: ObservableObject {
    static let shared = OfflineLibrary()

    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var seriesSaved = 0

    var lastSaved: Date? {
        get { UserDefaults.standard.object(forKey: "offlineLibrarySaved") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "offlineLibrarySaved") }
    }

    /// Refreshes at most every 6 hours unless forced.
    func refresh(client: KavitaClient, force: Bool = false) async {
        guard !running else { return }
        if !force, let lastSaved, Date().timeIntervalSince(lastSaved) < 6 * 3600 { return }
        running = true
        progress = 0
        defer { running = false }

        // Reachable at all? If not, try again later.
        guard let libraries = try? await client.libraries(), !ConnectionStatus.shared.offline else { return }
        let wifi = NetworkMonitor.shared.isUnmetered

        // Home rows, lists, Want to Read.
        _ = try? await client.onDeck()
        _ = try? await client.recentlyUpdated()
        _ = try? await client.recentlyAdded()
        _ = try? await client.wantToRead()
        if let lists = try? await client.readingLists() {
            for list in lists {
                _ = try? await client.readingListItems(list.id)
                await ImageCache.shared.warm(client.readingListCoverURL(list.id))
            }
        }

        // Every series, in the sort the Library tab uses (plus name order).
        let savedSort = SeriesSort(rawValue: UserDefaults.standard.integer(forKey: "librarySort")) ?? .name
        let sorts = Array(Set([savedSort, .name]))
        var allSeries: [Int: Series] = [:]
        for libraryId in [nil] + libraries.map({ Optional($0.id) }) {
            for sort in sorts {
                var page = 1
                while page < 100 {
                    guard let batch = try? await client.series(libraryId: libraryId, search: "", sort: sort,
                                                               page: page) else { break }
                    for s in batch { allSeries[s.id] = s }
                    if batch.count < 60 { break }
                    page += 1
                }
            }
        }

        // Series pages: everything on Wi-Fi; on cellular only what's on deck or downloaded.
        let downloadedSeries = Set(Downloads.shared.items.values.map(\.seriesId))
        let onDeck = Set(((try? await client.onDeck()) ?? []).map(\.id))
        let targets = wifi ? Array(allSeries.keys)
                           : Array(downloadedSeries.union(onDeck))
        let total = max(targets.count, 1)
        var done = 0
        var index = 0
        while index < targets.count {
            if ConnectionStatus.shared.offline { break }
            let batch = Array(targets[index..<min(index + 4, targets.count)])
            index += batch.count
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask {
                        _ = try? await client.series(id: id)
                        let detail = try? await client.seriesDetail(id: id)
                        _ = try? await client.metadata(seriesId: id)
                        _ = try? await client.continuePoint(seriesId: id)
                        _ = try? await client.isWantToRead(id)
                        guard wifi else { return }
                        await ImageCache.shared.warm(client.seriesCoverURL(id))
                        // Issue and volume covers for series you've downloaded from.
                        if downloadedSeries.contains(id), let detail {
                            for v in detail.volumes { await ImageCache.shared.warm(client.volumeCoverURL(v.id)) }
                            for c in detail.allChapters { await ImageCache.shared.warm(client.chapterCoverURL(c.id)) }
                        }
                    }
                }
            }
            done += batch.count
            progress = Double(done) / Double(total)
        }

        // Covers for every series in the lists (small, Wi-Fi only).
        if wifi {
            for id in allSeries.keys where !targets.contains(id) {
                await ImageCache.shared.warm(client.seriesCoverURL(id))
            }
        }

        seriesSaved = allSeries.count
        UserDefaults.standard.set(allSeries.count, forKey: "offlineLibraryCount")
        if !ConnectionStatus.shared.offline { lastSaved = Date() }
        progress = 1
    }

    var savedCount: Int { UserDefaults.standard.integer(forKey: "offlineLibraryCount") }
}
