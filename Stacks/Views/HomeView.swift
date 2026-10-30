import SwiftUI

/// Kavita's dashboard: On Deck, Recently Updated Series and Newly Added Series.
struct HomeView: View {
    let client: KavitaClient
    let openDownloads: () -> Void

    @EnvironmentObject private var downloads: Downloads
    @State private var onDeck: [Series] = []
    @State private var updated: [GroupedSeries] = []
    @State private var added: [Series] = []
    @State private var offline = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if offline {
                    OfflineBanner(hasDownloads: !downloads.items.isEmpty, openDownloads: openDownloads)
                        .padding(.horizontal, 16)
                }

                if !onDeck.isEmpty {
                    carousel("On Deck") {
                        ForEach(onDeck) { series in
                            NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                                SeriesCard(series: series, client: client).frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !updated.isEmpty {
                    carousel("Recently Updated Series") {
                        ForEach(updated) { item in
                            NavigationLink(value: SeriesRoute(id: item.seriesId, name: item.seriesName)) {
                                KavitaCard(title: item.seriesName,
                                           coverURL: client.seriesCoverURL(item.seriesId),
                                           badge: item.count > 1 ? "\(item.count)" : nil)
                                    .frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !added.isEmpty {
                    carousel("Newly Added Series") {
                        ForEach(added) { series in
                            NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                                SeriesCard(series: series, client: client).frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if loaded && !offline && onDeck.isEmpty && updated.isEmpty && added.isEmpty {
                    VStack(spacing: 8) {
                        Text("Nothing here yet").font(.headline).foregroundStyle(Theme.text)
                        Text(error ?? "Add a library in Kavita on your PC, then pull down to refresh.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .padding(.horizontal, 30)
                }
            }
            .padding(.vertical, 16)
        }
        .kavitaBackground()
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: LibraryRoute(library: nil)) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await load() }
        }
    }

    private func carousel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14, content: content)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func load() async {
        async let deck = client.onDeck()
        async let upd = client.recentlyUpdated()
        async let new = client.recentlyAdded()
        do {
            onDeck = try await deck
            offline = false
            error = nil
        } catch {
            if KavitaClient.isOffline(error) { offline = true } else { self.error = error.localizedDescription }
        }
        updated = (try? await upd) ?? updated
        added = (try? await new) ?? added
        loaded = true
        if !offline { await downloads.flush(client: client) }
    }
}

struct OfflineBanner: View {
    let hasDownloads: Bool
    let openDownloads: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.slash").font(.title3).foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Can't reach your server").font(.subheadline.bold()).foregroundStyle(Theme.text)
                Text(hasDownloads
                     ? "Your downloads still work. Reading progress syncs when you're back online."
                     : "Check that your PC and Kavita are on. Pull down to try again.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if hasDownloads {
                    Button("Open downloads", action: openDownloads)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
    }
}
