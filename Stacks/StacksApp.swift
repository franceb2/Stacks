import SwiftUI
import UIKit

@main
struct StacksApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var downloads = Downloads.shared

    @AppStorage("appTheme") private var themeRaw = AppTheme.kavita.rawValue

    init() {
        // Tell Kavita what kind of device this is (shows in its device list and reading history).
        let screen = UIScreen.main.bounds.size
        KavitaClient.clientHeader = "web-app/1.0 (Stacks/1.0; Ios; Mobile; \(Int(screen.width))x\(Int(screen.height)); portrait)"

        // Bigger image cache so covers still show when the server is unreachable.
        URLCache.shared = URLCache(memoryCapacity: 40_000_000, diskCapacity: 300_000_000)
        Self.applyBarAppearance()
    }

    /// Navigation and tab bars follow the current theme.
    static func applyBarAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.navBar)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.navBar)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let client = session.client {
                    RootView(client: client)
                } else {
                    LoginView()
                }
            }
            .id(themeRaw) // rebuild with the new colors when the theme changes
            .environmentObject(session)
            .environmentObject(downloads)
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .onChange(of: themeRaw) { _, raw in
                AppTheme.current = AppTheme(rawValue: raw) ?? .kavita
                Self.applyBarAppearance()
            }
        }
    }
}

// MARK: - Navigation

enum AppTab: String, Hashable { case home, library, lists, downloads, settings }

struct LibraryRoute: Hashable {
    var library: Library?          // nil = all series
}

struct SeriesRoute: Hashable {
    let id: Int
    let name: String
}

struct VolumeRoute: Hashable {
    let seriesId: Int
    let seriesName: String
    let volume: Volume
    let isComic: Bool
}

extension View {
    func stacksDestinations(client: KavitaClient) -> some View {
        self
            .navigationDestination(for: LibraryRoute.self) { SeriesGridView(route: $0, client: client) }
            .navigationDestination(for: SeriesRoute.self) { route in
                SeriesDetailView(route: route, client: client).zoomDestination("series-\(route.id)")
            }
            .navigationDestination(for: VolumeRoute.self) { VolumeView(route: $0, client: client) }
            .navigationDestination(for: ReadingListRoute.self) { ReadingListDetailView(route: $0, client: client) }
            .navigationDestination(for: WantToReadRoute.self) { _ in WantToReadView(client: client) }
    }
}

extension Notification.Name {
    /// Posted whenever read status or progress changes, so lists can refresh.
    static let readingProgressChanged = Notification.Name("readingProgressChanged")
}

struct RootView: View {
    let client: KavitaClient
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("selectedTab") private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var tourStarted = false
    @State private var listsPath = NavigationPath()
    @Namespace private var hero
    @StateObject private var updates = UpdateChecker.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(client: client, openDownloads: { tab = .downloads })
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack(path: $libraryPath) {
                LibrariesView(client: client)
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            .tag(AppTab.library)

            NavigationStack(path: $listsPath) {
                ReadingListsView(client: client)
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Lists", systemImage: "list.bullet.rectangle.fill") }
            .tag(AppTab.lists)

            NavigationStack {
                DownloadsView(client: client)
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
            .badge(downloads.jobs.count)
            .tag(AppTab.downloads)

            NavigationStack {
                SettingsView(client: client)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .environment(\.heroNamespace, hero)
        .alert(updates.available.map { "\($0.name) is available" } ?? "Update available",
               isPresented: Binding(get: { updates.shouldAlert && !DemoTour.enabled },
                                    set: { if !$0 { updates.dismissAlert() } })) {
            Button("Download") {
                openURL(UpdateChecker.downloadURL)
                updates.dismissAlert()
            }
            Button("Later", role: .cancel) { updates.dismissAlert() }
        } message: {
            Text("A new version of Stacks is ready." + ((updates.available?.notes).map { $0.isEmpty ? "" : "\n\n\($0)" } ?? "")
                 + "\n\nDownload it, then install it with Signulous like before.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkReturned)) { _ in
            Task {
                await downloads.flush(client: client)
                downloads.resumeIncomplete(client: client)
                await OfflineLibrary.shared.refresh(client: client)
            }
        }
        .task {
            downloads.removeOldFinished()
            await downloads.flush(client: client)
            if !ConnectionStatus.shared.offline { downloads.resumeIncomplete(client: client) }
            await updates.check()
            await OfflineLibrary.shared.refresh(client: client)
            if DemoTour.enabled && !tourStarted {
                tourStarted = true
                await runTour()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                downloads.removeOldFinished()
                Task {
                    await downloads.flush(client: client)
                    if !ConnectionStatus.shared.offline { downloads.resumeIncomplete(client: client) }
                    await updates.check()
                    await OfflineLibrary.shared.refresh(client: client)
                }
            }
        }
    }

    /// Preview-build only: steps through the main screens, saving a screenshot of each.
    private func runTour() async {
        await DemoTour.pause(5)
        DemoTour.snap("01-home")

        let libraries = (try? await client.libraries()) ?? []
        let comics = libraries.first(where: \.isComic)
        let manga = libraries.first(where: { $0.type == 0 })
        let books = libraries.first(where: { $0.type == 2 || $0.type == 4 })

        tab = .library
        await DemoTour.pause(1.5)
        if let comics, let first = try? await client.series(libraryId: comics.id, search: nil, page: 1).first {
            libraryPath.append(LibraryRoute(library: comics))
            await DemoTour.pause(4)
            DemoTour.snap("02-library")

            libraryPath.append(SeriesRoute(id: first.id, name: first.name))
            await DemoTour.pause(4)
            DemoTour.snap("03-series")

            NotificationCenter.default.post(name: .tourOpenReader, object: nil)
            await DemoTour.pause(5)
            DemoTour.snap("04-comic-reader")
            NotificationCenter.default.post(name: .tourShowMenu, object: nil)
            await DemoTour.pause(1.5)
            DemoTour.snap("05-reader-menu")
            NotificationCenter.default.post(name: .tourReaderSettings, object: nil)
            await DemoTour.pause(2)
            DemoTour.snap("06-reader-settings")
            NotificationCenter.default.post(name: .tourCloseReader, object: nil)
            await DemoTour.pause(2.5)

            NotificationCenter.default.post(name: .tourDownloadSheet, object: nil)
            await DemoTour.pause(2.5)
            DemoTour.snap("07-download-sheet")
            NotificationCenter.default.post(name: .tourCloseReader, object: nil)
            await DemoTour.pause(1.5)

            if let detail = try? await client.seriesDetail(id: first.id), let chapter = detail.allChapters.first {
                downloads.start(client: client, chapter: chapter, seriesId: first.id, seriesName: first.name,
                                title: chapter.displayName, range: .pages(0...5))
            }
        }

        if let manga, let series = try? await client.series(libraryId: manga.id, search: nil, page: 1).first {
            libraryPath = NavigationPath()
            await DemoTour.pause(1)
            libraryPath.append(LibraryRoute(library: manga))
            await DemoTour.pause(1.5)
            libraryPath.append(SeriesRoute(id: series.id, name: series.name))
            await DemoTour.pause(4)
            DemoTour.snap("08-manga-volumes")
        }

        if let books, let list = try? await client.series(libraryId: books.id, search: nil, page: 1),
           let novel = list.first(where: { $0.format == MangaFormat.epub.rawValue }) ?? list.first {
            libraryPath = NavigationPath()
            await DemoTour.pause(1)
            libraryPath.append(LibraryRoute(library: books))
            await DemoTour.pause(1.5)
            libraryPath.append(SeriesRoute(id: novel.id, name: novel.name))
            await DemoTour.pause(3)
            NotificationCenter.default.post(name: .tourOpenReader, object: nil)
            await DemoTour.pause(5)
            DemoTour.snap("09-book-reader")
            NotificationCenter.default.post(name: .tourShowMenu, object: nil)
            await DemoTour.pause(1.5)
            DemoTour.snap("10-book-menu")
            NotificationCenter.default.post(name: .tourCloseReader, object: nil)
            await DemoTour.pause(2.5)
        }

        tab = .downloads
        await DemoTour.pause(4)
        DemoTour.snap("11-downloads")

        tab = .settings
        await DemoTour.pause(2)
        DemoTour.snap("12-settings")

        tab = .home
        libraryPath = NavigationPath()
        await DemoTour.pause(2)
        DemoTour.finish()
    }
}
