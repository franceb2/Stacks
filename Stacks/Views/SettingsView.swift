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
    @State private var autoCount = AutoDownload.count
    @State private var autoWifiOnly = AutoDownload.wifiOnly
    @State private var mangaRTL = ReaderPrefsStore.mangaRightToLeft
    @State private var autoDelete = AutoDelete.enabled
    @State private var autoDeleteDays = AutoDelete.days
    @AppStorage("appTheme") private var themeRaw = AppTheme.kavita.rawValue
    @StateObject private var updates = UpdateChecker.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 12)], spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            AppTheme.select(theme)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(Color(hex: theme.background))
                                    Circle().trim(from: 0, to: 0.5)
                                        .fill(Color(hex: theme.accent))
                                        .rotationEffect(.degrees(-45))
                                    Circle().stroke(themeRaw == theme.rawValue ? Color.white : Color.white.opacity(0.15),
                                                    lineWidth: themeRaw == theme.rawValue ? 3 : 1)
                                }
                                .frame(width: 46, height: 46)
                                Text(theme.name)
                                    .font(.caption2)
                                    .foregroundStyle(themeRaw == theme.rawValue ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Theme.card)

            Section("Updates") {
                LabeledContent("Installed", value: "\(updates.installedVersion) (build \(updates.installedBuild))")
                if let release = updates.available {
                    Button {
                        openURL(UpdateChecker.downloadURL)
                    } label: {
                        Label("Download \(release.name)", systemImage: "arrow.down.circle.fill")
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

            Section("Server") {
                LabeledContent("Address", value: session.serverAddress)
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Reading mode", selection: $comic.mode) {
                    ForEach(ReadingMode.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                Toggle("Right to left (manga)", isOn: $comic.rightToLeft)
                    .disabled(comic.mode != .leftRight)
                Toggle("Two pages when sideways", isOn: $comic.doublePage)
                    .disabled(comic.mode != .leftRight)
                Toggle("Tap sides to turn pages", isOn: $comic.tapToTurn)
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
                    Text("1 issue").tag(1)
                    Text("2 issues").tag(2)
                    Text("3 issues").tag(3)
                }
                Toggle("Only on Wi-Fi", isOn: $autoWifiOnly)
                    .disabled(autoCount == 0)
            } header: {
                Text("Auto-download")
            } footer: {
                Text("When you finish an issue or chapter, the next ones download quietly so they're ready offline. Follows your reading list when you're reading from one.")
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

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                                as? String ?? "1.0")
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
