import SwiftUI
import UIKit

@main
struct StacksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var phase
    @StateObject private var downloads = Downloads.shared

    @AppStorage("appTheme") private var themeRaw = AppTheme.kavita.rawValue

    init() {
        // Tell Kavita what kind of device this is (shows in its device list and reading history).
        let screen = UIScreen.main.bounds.size
        KavitaClient.clientHeader = "web-app/1.0 (Stacks/1.0; Ios; Mobile; \(Int(screen.width))x\(Int(screen.height)); portrait)"

        // Bigger image cache so covers still show when the server is unreachable.
        URLCache.shared = URLCache(memoryCapacity: 40_000_000, diskCapacity: 300_000_000)
        // Theme rotation: pick the new theme before anything is drawn.
        if let next = ThemeRotation.due(launch: true) {
            AppTheme.select(next)
        }
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
            .overlay {
                if lock.locked { LockScreen(lock: lock) }
            }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .background {
                    lock.lockIfEnabled()
                    ThemeRotation.leftAt = Date()
                } else if newPhase == .active, let next = ThemeRotation.due(launch: false) {
                    AppTheme.select(next)
                }
            }
            .environmentObject(session)
            .environmentObject(downloads)
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .onChange(of: themeRaw) { _, raw in
                AppTheme.current = AppTheme.named(raw)
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
            .navigationDestination(for: CollectionRoute.self) { CollectionView(route: $0, client: client) }
            .navigationDestination(for: PersonRoute.self) { PersonView(route: $0, client: client) }
            .navigationDestination(for: SearchRoute.self) { _ in SearchView(client: client) }
            .navigationDestination(for: StatsRoute.self) { _ in StatsView(client: client) }
            .navigationDestination(for: BookmarksRoute.self) { _ in AllBookmarksView(client: client) }
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

    @State private var shortcutLaunch: ReaderLaunch?
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var listsPath = NavigationPath()
    @Namespace private var hero
    @StateObject private var updates = UpdateChecker.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $listsPath) {
                ReadingListsView(client: client)
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Lists", systemImage: "list.bullet.rectangle.fill") }
            .tag(AppTab.lists)

            NavigationStack(path: $libraryPath) {
                LibrariesView(client: client)
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            .tag(AppTab.library)

            NavigationStack(path: $homePath) {
                HomeView(client: client, openDownloads: { tab = .downloads })
                    .stacksDestinations(client: client)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

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
               isPresented: Binding(get: { updates.shouldAlert },
                                    set: { if !$0 { updates.dismissAlert() } })) {
            Button("Open Signulous (link copied)") {
                updates.dismissAlert()
                UpdateChecker.openSignulous()
            }
            Button("Copy download link") {
                UIPasteboard.general.string = UpdateChecker.downloadURL.absoluteString
                updates.dismissAlert()
            }
            Button("Later", role: .cancel) { updates.dismissAlert() }
        } message: {
            Text("A new version of Stacks is ready." + ((updates.available?.notes).map { $0.isEmpty ? "" : "\n\n\($0)" } ?? "")
                 + "\n\nOpen Signulous copies the download link and opens the upload page in Safari: tap the URL box and Paste.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFromShortcut)) { _ in
            shortcutLaunch = QuickActions.pending
            QuickActions.pending = nil
        }
        .onAppear {
            if let pending = QuickActions.pending {
                shortcutLaunch = pending
                QuickActions.pending = nil
            }
        }
        .fullScreenCover(item: $shortcutLaunch, onDismiss: {
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId, readingListId: launch.readingListId)
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
}
