import SwiftUI

struct SettingsView: View {
    let client: KavitaClient

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var downloads: Downloads
    @State private var comic = ReaderPrefsStore.defaultComic
    @State private var book = ReaderPrefsStore.book
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var resetDone = false
    @State private var linkCopied = false
    @State private var rotation = ThemeRotation.current
    @AppStorage("themesOpen") private var themesOpen = false
    @State private var coversReloaded = false
    @State private var autoCount = AutoDownload.count
    @State private var autoWifiOnly = AutoDownload.wifiOnly
    @State private var mangaRTL = ReaderPrefsStore.mangaRightToLeft
    @State private var autoDelete = AutoDelete.enabled
    @State private var autoDeleteDays = AutoDelete.days
    @AppStorage("appTheme") private var themeRaw = AppTheme.kavita.rawValue
    @StateObject private var updates = UpdateChecker.shared
    @StateObject private var offlineLibrary = OfflineLibrary.shared
    @State private var faceID = AppLock.enabled
    @State private var faceIDProblem = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                DisclosureGroup(isExpanded: $themesOpen) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 12)], spacing: 14) {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                AppTheme.select(theme)
                            } label: {
                                VStack(spacing: 6) {
                                    ThemeSwatch(theme: theme, selected: AppTheme.named(themeRaw) == theme)
                                        .frame(width: 46, height: 46)
                                    Text(theme.name)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.named(themeRaw) == theme ? Theme.text : Theme.muted)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    HStack(spacing: 12) {
                        ThemeSwatch(theme: AppTheme.named(themeRaw), selected: false)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((AppTheme.named(themeRaw)).name).foregroundStyle(Theme.text)
                            Text("\(AppTheme.allCases.count) themes").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .tint(Theme.primary)

                Picker("Change theme", selection: $rotation) {
                    ForEach(ThemeRotation.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Theme")
            } footer: {
                if rotation != .off {
                    Text("Switches to a random different theme when you open or come back to the app, never while you're reading.")
                }
            }
            .listRowBackground(Theme.card)
            .onChange(of: rotation) { _, value in ThemeRotation.current = value }

            Section("Updates") {
                LabeledContent("Installed", value: "\(updates.installedVersion) (build \(updates.installedBuild))")
                if let release = updates.available {
                    Menu {
                        Button("Download IPA", systemImage: "arrow.down.circle") { openURL(UpdateChecker.downloadURL) }
                        Button("Copy download link", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = UpdateChecker.downloadURL.absoluteString
                            linkCopied = true
                        }
                    } label: {
                        Label(linkCopied ? "Link copied" : "Download \(release.name)",
                              systemImage: linkCopied ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    }
                    if !release.notes.isEmpty {
                        Text(release.notes).font(.footnote).foregroundStyle(Theme.muted)
                    }
                } else {
                    Button {
                        Task { await updates.check(force: true) }
                    } label: {
                        HStack {
                            Text(updates.lastChecked == nil ? "Check for updates" : "You're up to date · check again")
                            Spacer()
                            if updates.checking { ProgressView() }
                        }
                    }
                }
                if let problem = updates.problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Toggle("Lock with \(AppLock.biometryName)", isOn: $faceID)
            } header: {
                Text("Privacy")
            } footer: {
                Text(faceIDProblem
                     ? "Couldn't turn it on. Check that \(AppLock.biometryName) or a passcode is set up on this iPhone."
                     : "Asks for \(AppLock.biometryName) (or your passcode) each time you open Stacks, and hides it in the app switcher.")
            }
            .listRowBackground(Theme.card)

            Section {
                LabeledContent("Address", value: session.serverAddress)
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } header: {
                Text("Server")
            } footer: {
                Text("To find comics you just added on your PC, scan from the Library tab (↻).")
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Reading mode", selection: $comic.mode) {
                    ForEach(ReadingMode.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                Toggle("Two pages when sideways", isOn: $comic.doublePage)
                    .disabled(comic.mode != .leftRight)
                Toggle("Tap sides to turn pages", isOn: $comic.tapToTurn)
                    .disabled(comic.mode == .webtoon)
                Toggle("Panel by panel", isOn: $comic.panelView)
                    .disabled(comic.mode == .webtoon)
                Toggle("Manga reads right to left", isOn: $mangaRTL)
                Picker("Image scaling", selection: $comic.scaling) {
                    ForEach(ScalingMode.allCases) { Text($0.label).tag($0) }
                }
                .disabled(comic.mode == .webtoon)
                Picker("Background", selection: $comic.background) {
                    ForEach(ReaderBackground.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Reset per-series settings") {
                    ReaderPrefsStore.clearSeriesOverrides()
                    resetDone = true
                }
            } header: {
                Text("Comic and manga reader")
            } footer: {
                Text(resetDone
                     ? "Every series now uses these defaults."
                     : "These are the defaults. Changes you make inside the reader are remembered for that series.")
            }
            .listRowBackground(Theme.card)

            Section("Book reader") {
                Picker("Layout", selection: $book.paged) {
                    Text("Pages").tag(true)
                    Text("Scroll").tag(false)
                }
                Picker("Theme", selection: $book.theme) {
                    ForEach(BookTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("Font", selection: $book.font) {
                    ForEach(BookFont.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Text size \(book.fontSize)%", value: $book.fontSize, in: 60...250, step: 10)
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Download next", selection: $autoCount) {
                    Text("Off").tag(0)
                    ForEach(AutoDownload.choices, id: \.self) { Text("\($0) issues").tag($0) }
                }
                Toggle("Only on Wi-Fi", isOn: $autoWifiOnly)
                    .disabled(autoCount == 0)
            } header: {
                Text("Auto-download")
            } footer: {
                Text("When you finish an issue or chapter, the next ones download quietly so they're ready offline. They follow the reading order the issue is in (or the reading list you're reading from); otherwise the next issues of that series.")
            }
            .listRowBackground(Theme.card)

            Section {
                if offlineLibrary.running {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saving your library…")
                        ProgressView(value: offlineLibrary.progress).tint(Theme.primary)
                    }
                } else {
                    LabeledContent("Saved", value: offlineLibrary.lastSaved.map {
                        "\(offlineLibrary.savedCount) series · \($0.formatted(.relative(presentation: .named)))"
                    } ?? "Not yet")
                    Button("Save library now") {
                        Task { await offlineLibrary.refresh(client: client, force: true) }
                    }
                    Button("Reload all covers") {
                        ImageCache.shared.clearAll()
                        coversReloaded = true
                        Task { await offlineLibrary.refresh(client: client, force: true) }
                    }
                }
            } header: {
                Text("Offline library")
            } footer: {
                Text(coversReloaded
                     ? "Saved covers cleared. They'll load fresh from Kavita as you browse."
                     : "Your libraries, series pages, lists and covers are saved in the background so you can browse with no connection. No pages are downloaded. Covers check Kavita for changes every few hours; \"Reload all covers\" does it now.")
            }
            .listRowBackground(Theme.card)

            Section {
                Toggle("Delete finished downloads", isOn: $autoDelete)
                Picker("After", selection: $autoDeleteDays) {
                    ForEach([3, 7, 10, 14, 30], id: \.self) { Text("\($0) days").tag($0) }
                }
                .disabled(!autoDelete)
            } header: {
                Text("Clean up")
            } footer: {
                Text("Removes a download this many days after you finish reading all of it. Anything not yet synced to Kavita is kept until it syncs.")
            }
            .listRowBackground(Theme.card)

            Section("Storage") {
                LabeledContent("Downloads", value: downloads.totalBytes.fileSizeText)
                Button("Delete all downloads", role: .destructive) { confirmDelete = true }
                    .disabled(downloads.items.isEmpty)
            }
            .listRowBackground(Theme.card)

        }
        .kavitaBackground()
        .navigationTitle("Settings")
        .onChange(of: comic) { _, value in
            ReaderPrefsStore.defaultComic = value
            resetDone = false
        }
        .onChange(of: book) { _, value in ReaderPrefsStore.book = value }
        .onChange(of: autoCount) { _, value in AutoDownload.count = value }
        .onChange(of: autoWifiOnly) { _, value in AutoDownload.wifiOnly = value }
        .onChange(of: mangaRTL) { _, value in ReaderPrefsStore.mangaRightToLeft = value }
        .onChange(of: faceID) { _, value in
            guard value != AppLock.enabled else { return }
            Task {
                let ok = await AppLock.shared.enable(value)
                faceIDProblem = value && !ok
                if !ok { faceID = AppLock.enabled }
            }
        }
        .onChange(of: autoDelete) { _, value in
            AutoDelete.enabled = value
            downloads.removeOldFinished()
        }
        .onChange(of: autoDeleteDays) { _, value in
            AutoDelete.days = value
            downloads.removeOldFinished()
        }
        .task { await updates.check() }
        .confirmationDialog("Delete all downloads?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { downloads.deleteAll() }
        }
        .confirmationDialog("Sign out of this server?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.signOut() }
        } message: {
            Text("Your downloads stay on the phone.")
        }
    }
}

/// A theme's preview: its background with its trim color, and a ring when it's the one in use.
struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: theme.background))
            Circle().inset(by: 7).fill(Color(hex: theme.card))
            Circle().trim(from: 0, to: 0.5)
                .fill(Color(hex: theme.accent))
                .rotationEffect(.degrees(-45))
                .padding(10)
            Circle().stroke(selected ? Color.white : Color.white.opacity(0.15), lineWidth: selected ? 3 : 1)
        }
    }
}
