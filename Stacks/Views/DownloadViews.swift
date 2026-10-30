import SwiftUI

/// Pick what to download: everything, the next N pages from where you are, or a custom page range.
struct DownloadSheet: View {
    let target: DownloadTarget
    let client: KavitaClient

    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss

    private enum Choice: Hashable { case all, next, custom }

    @State private var choice: Choice = .next
    @State private var count = 50
    @State private var from = 1
    @State private var to = 1

    private var total: Int { max(target.chapter.pages, 1) }
    private var noun: String { target.isBook ? "sections" : "pages" }
    private var nounOne: String { target.isBook ? "section" : "page" }
    private var current: Int { min(max(target.chapter.isRead ? 0 : target.chapter.pagesRead, 0), total - 1) }
    private var already: Int { downloads.items[target.chapter.id]?.pages.count ?? 0 }

    /// 0-based inclusive range for the current choice.
    private var range: ClosedRange<Int> {
        switch choice {
        case .all:
            return 0...(total - 1)
        case .next:
            return current...min(total - 1, current + max(count, 1) - 1)
        case .custom:
            let a = min(max(from, 1), total) - 1
            let b = min(max(to, 1), total) - 1
            return min(a, b)...max(a, b)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.title).font(.headline)
                        Text(target.seriesName).font(.subheadline).foregroundStyle(Theme.muted)
                        Text("\(total) \(noun)" + (already > 0 ? " · \(already) already on this phone" : ""))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("What to download") {
                    Picker("What to download", selection: $choice) {
                        Text("Next \(noun) from where you are").tag(Choice.next)
                        Text("A \(nounOne) range").tag(Choice.custom)
                        Text("Everything").tag(Choice.all)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .listRowBackground(Theme.card)

                    if choice == .next {
                        Stepper(value: $count, in: 10...max(10, total), step: 10) {
                            Text("\(min(count, total - current)) \(noun)")
                        }
                        .listRowBackground(Theme.card)
                        HStack(spacing: 8) {
                            ForEach([25, 50, 100, 200], id: \.self) { n in
                                Button("\(n)") { count = n }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(n > total)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }

                    if choice == .custom {
                        HStack {
                            Text("From")
                            TextField("1", value: $from, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)
                                .textFieldStyle(.roundedBorder)
                            Text("to")
                            TextField("\(total)", value: $to, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)
                                .textFieldStyle(.roundedBorder)
                            Text("of \(total)").foregroundStyle(Theme.muted)
                        }
                        .listRowBackground(Theme.card)
                    }
                }

                Section {
                    Button {
                        downloads.start(client: client, chapter: target.chapter, seriesId: target.seriesId,
                                        seriesName: target.seriesName, title: target.title, range: .pages(range))
                        dismiss()
                    } label: {
                        Text("Download \(nounOne)s \(range.lowerBound + 1)–\(range.upperBound + 1)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Downloads go to the Downloads tab and can be read without a connection. Pages you already have are skipped.")
                }
            }
            .kavitaBackground()
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            from = current + 1
            to = total
            if total <= 60 { choice = .all }
        }
    }
}

/// Everything saved on the phone, grouped by series.
struct DownloadsView: View {
    let client: KavitaClient

    @EnvironmentObject private var downloads: Downloads
    @State private var reader: ReaderLaunch?
    @State private var confirmDeleteAll = false
    @State private var collapsed: Set<String> = []
    @State private var shown: [String: Int] = [:]
    @State private var confirmDeleteSeries: String?

    private static let pageSize = 5

    private struct SeriesGroup: Identifiable {
        let series: String
        let items: [DownloadedChapter]
        var id: String { series }
    }

    private struct WaitingJob: Identifiable {
        let id: Int
        let job: Downloads.Job
    }

    private var groups: [SeriesGroup] {
        Dictionary(grouping: downloads.sortedItems, by: { $0.seriesName })
            .map { SeriesGroup(series: $0.key, items: $0.value) }
            .sorted { $0.series.localizedStandardCompare($1.series) == .orderedAscending }
    }

    private var waitingJobs: [WaitingJob] {
        downloads.jobs.filter { downloads.items[$0.key] == nil }
            .map { WaitingJob(id: $0.key, job: $0.value) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        List {
            if downloads.items.isEmpty && downloads.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 44)).foregroundStyle(Theme.primary)
                    Text("No downloads yet").font(.headline)
                    Text("Long-press any issue, volume or book and choose Download, or Download pages… for part of an omnibus.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }

            if !waitingJobs.isEmpty {
                Section("Starting") {
                    ForEach(waitingJobs) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.job.title)
                                Text(entry.job.seriesName).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("Waiting").font(.caption).foregroundStyle(Theme.muted)
                            Button { downloads.cancel(entry.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }

            ForEach(groups) { group in
                let isCollapsed = collapsed.contains(group.series)
                let limit = shown[group.series] ?? Self.pageSize
                let visible = Array(group.items.prefix(limit))
                Section {
                    if !isCollapsed {
                        ForEach(visible) { item in
                            row(item).listRowBackground(Theme.card)
                        }
                        .onDelete { offsets in
                            for i in offsets { downloads.delete(visible[i].chapterId) }
                        }
                        if group.items.count > Self.pageSize {
                            HStack {
                                if limit < group.items.count {
                                    Button("Show \(min(Self.pageSize, group.items.count - limit)) more") {
                                        withAnimation { shown[group.series] = limit + Self.pageSize }
                                    }
                                    Spacer()
                                    Button("Show all \(group.items.count)") {
                                        withAnimation { shown[group.series] = group.items.count }
                                    }
                                } else {
                                    Button("Show less") {
                                        withAnimation { shown[group.series] = Self.pageSize }
                                    }
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                            .listRowBackground(Theme.card)
                        }
                    }
                } header: {
                    Button {
                        withAnimation {
                            if isCollapsed { collapsed.remove(group.series) } else { collapsed.insert(group.series) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            Text(group.series).lineLimit(1)
                            Spacer()
                            Text("\(group.items.count) · \(group.items.reduce(Int64(0)) { $0 + $1.bytes }.fileSizeText)")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(Theme.text)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete \(group.series) downloads", systemImage: "trash", role: .destructive) {
                            confirmDeleteSeries = group.series
                        }
                    }
                }
            }

            if !downloads.items.isEmpty {
                Section {
                    LabeledContent("Space used", value: downloads.totalBytes.fileSizeText)
                        .listRowBackground(Theme.card)
                    if !downloads.pending.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(downloads.pending.count) reading position\(downloads.pending.count == 1 ? "" : "s") waiting to sync to Kavita",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote).foregroundStyle(Theme.muted)
                            Button("Sync now") { Task { await downloads.flush(client: client) } }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                        .listRowBackground(Theme.card)
                    }
                    Button("Delete all downloads", role: .destructive) { confirmDeleteAll = true }
                        .listRowBackground(Theme.card)
                }
            }
        }
        .kavitaBackground()
        .navigationTitle("Downloads")
        .confirmationDialog("Delete all downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { downloads.deleteAll() }
        }
        .confirmationDialog("Delete these downloads?",
                            isPresented: Binding(get: { confirmDeleteSeries != nil },
                                                 set: { if !$0 { confirmDeleteSeries = nil } }),
                            titleVisibility: .visible) {
            Button("Delete \(confirmDeleteSeries ?? "")", role: .destructive) {
                if let name = confirmDeleteSeries {
                    for item in downloads.items.values where item.seriesName == name { downloads.delete(item.chapterId) }
                }
                confirmDeleteSeries = nil
            }
        }
        .toolbar {
            if groups.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(collapsed.count == groups.count ? "Expand all" : "Collapse all") {
                        withAnimation {
                            collapsed = collapsed.count == groups.count ? [] : Set(groups.map(\.series))
                        }
                    }
                }
            }
        }
        .alert("Download problem", isPresented: Binding(get: { downloads.lastError != nil },
                                                        set: { if !$0 { downloads.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.lastError ?? "")
        }
        .fullScreenCover(item: $reader, onDismiss: {
            NotificationCenter.default.post(name: .readingProgressChanged, object: nil)
        }) { launch in
            ReaderView(client: client, startChapterId: launch.chapterId)
        }
    }

    private func row(_ item: DownloadedChapter) -> some View {
        Button {
            reader = ReaderLaunch(chapterId: item.chapterId)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: client.chapterCoverURL(item.chapterId),
                           localFile: downloads.coverURL(chapterId: item.chapterId))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).foregroundStyle(Theme.text).lineLimit(2)
                    Text("\(item.rangeText) · \(item.bytes.fileSizeText)")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let last = item.lastPage {
                        Text("Read to \(item.isBook ? "section" : "page") \(last + 1)")
                            .font(.caption).foregroundStyle(Theme.primary)
                    }
                    if downloads.jobs[item.chapterId] == nil, !item.missing.isEmpty {
                        HStack(spacing: 8) {
                            Label("\(item.missing.count) \(item.isBook ? "section" : "page")\(item.missing.count == 1 ? "" : "s") missing",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("Finish") {
                                downloads.start(client: client, chapterId: item.chapterId, seriesId: item.seriesId,
                                                seriesName: item.seriesName, title: item.title,
                                                range: .list(item.missing))
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                        }
                    }
                    if let job = downloads.jobs[item.chapterId] {
                        HStack {
                            ProgressView(value: job.fraction).tint(Theme.primary)
                            Text("\(job.done)/\(job.total)").font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.muted)
                            Button { downloads.cancel(item.chapterId) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
