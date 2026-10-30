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

    var body: some View {
        Form {
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
