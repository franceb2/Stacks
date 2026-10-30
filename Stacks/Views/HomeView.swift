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
    @State private var heroChapter: Chapter?
    @State private var reader: ReaderLaunch?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if offline {
                    OfflineBanner(hasDownloads: !downloads.items.isEmpty, openDownloads: openDownloads)
                        .padding(.horizontal, 16)
                }

                if let hero = onDeck.first {
                    heroCard(hero)
                }

                if !onDeck.isEmpty {
                    carousel("On Deck") {
                        ForEach(onDeck) { series in
                            NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                                SeriesCard(series: series, client: client).frame(width: 118)
                            }
                            .buttonStyle(PressableStyle())
                            .zoomSource("series-\(series.id)")
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
                            .buttonStyle(PressableStyle())
                            .zoomSource("series-\(item.seriesId)")
                        }
                    }
                }

                if !added.isEmpty {
                    carousel("Newly Added Series") {
                        ForEach(added) { series in
                            NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                                SeriesCard(series: series, client: client).frame(width: 118)
                            }
                            .buttonStyle(PressableStyle())
                            .zoomSource("series-\(series.id)")
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
        .fullScreenCover(item: $reader, onDismiss: {
            Task { await load() }
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingProgressChanged)) { _ in
            Task { await load() }
        }
    }

    /// The big "pick up where you left off" card at the top, Kavita-cinematic.
    private func heroCard(_ series: Series) -> some View {
        ZStack(alignment: .bottomLeading) {
            Backdrop(url: client.seriesCoverURL(series.id))
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                NavigationLink(value: SeriesRoute(id: series.id, name: series.name)) {
                    CoverImage(url: client.seriesCoverURL(series.id))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: 104)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                }
                .buttonStyle(PressableStyle())
                .zoomSource("series-\(series.id)")

                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE READING")
                        .font(.caption2.weight(.bold)).kerning(1.2)
                        .foregroundStyle(Theme.primary)
                    Text(series.name)
                        .font(.title3.bold()).foregroundStyle(Theme.text).lineLimit(2)
                    if let heroChapter {
                        Text(heroChapter.isStarted
                             ? "\(heroChapter.displayName) · page \(heroChapter.pagesRead + 1) of \(heroChapter.pages)"
                             : heroChapter.displayName)
                            .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    ProgressView(value: series.progress).tint(Theme.primary)
                    Button {
                        if let heroChapter { reader = ReaderLaunch(chapterId: heroChapter.id) }
                    } label: {
                        Label("Continue", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(heroChapter == nil)
                }
            }
            .padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
        .padding(.horizontal, 16)
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
        if let hero = onDeck.first {
            heroChapter = try? await client.continuePoint(seriesId: hero.id)
        } else {
            heroChapter = nil
        }
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
