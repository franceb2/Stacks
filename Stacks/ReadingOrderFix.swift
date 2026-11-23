import SwiftUI

/// "Fix match": point one reading-order entry at the right series and issue yourself. For collected
/// editions (an omnibus), set the page the issue starts on, and optionally place the following issues
/// of that series in the same book.
struct OrderFixSheet: View {
    let order: ReadingOrder
    let target: ResolvedEntry
    let entries: [ResolvedEntry]
    let client: KavitaClient

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ReadingOrderStore.shared

    @State private var all: [Series] = []
    @State private var search = ""
    @State private var series: Series?
    @State private var detail: SeriesDetail?
    @State private var loadingDetail = false
    @State private var chapterId: Int?
    @State private var inBook = false
    @State private var page = 1            // 1-based, as shown
    @State private var preview: UIImage?
    @State private var fillNext = false
    @State private var fillThrough: Int?   // entry index of the last issue to place
    @State private var pagesEach = 24

    private var chapters: [Chapter] { detail?.allChapters ?? [] }
    private var chapter: Chapter? { chapters.first { $0.id == chapterId } }
    private var bookPages: Int { chapter?.pages ?? 0 }

    /// Later entries of the same series, which can be placed in the same book.
    private var following: [ResolvedEntry] {
        let key = TitleKey.make(target.entry.series)
        return Array(entries.filter { $0.index > target.index && $0.entry.number != nil
            && TitleKey.make($0.entry.series) == key }.prefix(150))
    }

    private var fillCount: Int {
        guard fillNext, let through = fillThrough else { return 0 }
        return following.filter { $0.index <= through }.count
    }

    private var suggestions: [Series] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let n = Shelf.normalized(q)
            return Array(all.filter { Shelf.normalized($0.name).contains(n) }.prefix(40))
        }
        // Nothing typed: series that share words with the entry's title.
        let words = Set(TitleKey.make(target.entry.series).split(separator: " ").map(String.init)).subtracting(["and", "of"])
        return Array(all.filter { s in
            !words.isDisjoint(with: TitleKey.make(s.name).split(separator: " ").map(String.init))
        }.prefix(25))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.entry.label).font(.headline).foregroundStyle(Theme.text)
                } header: {
                    Text("Reading order entry \(target.index + 1)")
                }
                .listRowBackground(Theme.card)

                seriesSection
                if series != nil { issueSection }
                if chapter != nil { bookSection }
            }
            .scrollContentBackground(.hidden)
            .kavitaBackground()
            .navigationTitle("Fix match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(chapter == nil)
                }
            }
            .task { await start() }
            .task(id: "\(chapterId ?? 0)-\(page)-\(inBook)") { await loadPreview() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var seriesSection: some View {
        Section {
            if let series {
                HStack {
                    CoverImage(url: client.seriesCoverURL(series.id))
                        .clipShape(RoundedRectangle(cornerRadius: 3)).frame(width: 30)
                    Text(series.name).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Change") {
                        self.series = nil
                        detail = nil
                        chapterId = nil
                    }
                    .font(.footnote)
                }
            } else {
                TextField("Search your library", text: $search)
                    .autocorrectionDisabled()
                if all.isEmpty {
                    HStack(spacing: 10) { ProgressView(); Text("Loading your library…").foregroundStyle(Theme.muted) }
                }
                ForEach(suggestions) { s in
                    Button {
                        choose(s)
                    } label: {
                        HStack(spacing: 10) {
                            CoverImage(url: client.seriesCoverURL(s.id))
                                .clipShape(RoundedRectangle(cornerRadius: 3)).frame(width: 30)
                            Text(s.name).foregroundStyle(Theme.text).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Series")
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private var issueSection: some View {
        Section {
            if loadingDetail {
                ProgressView()
            }
            ForEach(chapters) { c in
                Button {
                    chapterId = c.id
                    if c.pages > 150 { inBook = true }   // big books are usually collected editions
                } label: {
                    HStack {
                        Text(c.displayName).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text("\(c.pages) pages").font(.caption).foregroundStyle(Theme.muted)
                        Image(systemName: chapterId == c.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chapterId == c.id ? Theme.primary : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Issue or book")
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private var bookSection: some View {
        Section {
            Toggle("It's inside this book (omnibus)", isOn: $inBook).tint(Theme.primary)
            if inBook {
                Stepper(value: $page, in: 1...max(bookPages, 1)) {
                    HStack {
                        Text("Starts on page")
                        TextField("1", value: $page, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .foregroundStyle(Theme.primary)
                        Text("of \(bookPages)").foregroundStyle(Theme.muted)
                    }
                }
                HStack {
                    Spacer()
                    Group {
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit()
                        } else {
                            Rectangle().fill(Color.black.opacity(0.3)).overlay(ProgressView())
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                if !following.isEmpty {
                    Toggle("Also place the next \(target.entry.series) issues in this book", isOn: $fillNext)
                        .tint(Theme.primary)
                    if fillNext {
                        Picker("Through", selection: $fillThrough) {
                            ForEach(following) { e in
                                Text(e.entry.label.components(separatedBy: ",").first ?? e.entry.label)
                                    .tag(Optional(e.index))
                            }
                        }
                        Stepper("About \(pagesEach) pages per issue", value: $pagesEach, in: 8...200)
                    }
                }
            }
        } header: {
            Text("Where it starts")
        } footer: {
            if inBook {
                Text(fillNext && fillCount > 0
                     ? "Places \(fillCount) more issues every \(pagesEach) pages from here. Those are estimates; fix any that land on the wrong page the same way."
                     : "Page through to the issue's cover. Reading from this entry opens the book on that page, and it counts as read once you're past the next issue's first page.")
            } else {
                Text("Turn this on when the issue is part of a bigger book, like an omnibus or trade.")
            }
        }
        .listRowBackground(Theme.card)
        .onChange(of: fillNext) { _, on in
            if on, fillThrough == nil { fillThrough = following.last?.index; estimatePagesEach() }
        }
        .onChange(of: fillThrough) { _, _ in estimatePagesEach() }
    }

    // MARK: Actions

    private func start() async {
        all = await store.allSeries(client: client)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let id = target.seriesId, let s = all.first(where: { $0.id == id }) {
            choose(s, keepChapter: target.chapter?.id)
        }
        if let start = target.startPage {
            inBook = true
            page = start + 1
        }
    }

    private func choose(_ s: Series, keepChapter: Int? = nil) {
        series = s
        chapterId = keepChapter
        detail = nil
        loadingDetail = true
        Task {
            detail = try? await client.seriesDetail(id: s.id)
            loadingDetail = false
            if chapterId == nil, chapters.count == 1 { chapterId = chapters.first?.id }
        }
    }

    private func estimatePagesEach() {
        let count = fillCount + 1
        guard bookPages > 0, count > 0 else { return }
        pagesEach = min(200, max(8, (bookPages - (page - 1)) / count))
    }

    private func loadPreview() async {
        preview = nil
        guard inBook, let chapterId else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)   // wait for typing to settle
        if Task.isCancelled { return }
        let index = min(max(page - 1, 0), max(bookPages - 1, 0))
        if let data = try? await client.pageImageData(chapterId: chapterId, page: index), let img = UIImage(data: data) {
            let thumb = await img.byPreparingThumbnail(ofSize: CGSize(width: 320, height: 480)) ?? img
            if !Task.isCancelled { preview = thumb }
        }
    }

    private func save() {
        guard let series, let chapterId else { return }
        let first = inBook ? min(max(page - 1, 0), max(bookPages - 1, 0)) : nil
        var changes: [(index: Int, entry: ReadingOrder.Entry, fix: OrderFix?)] = [
            (target.index, target.entry, OrderFix(seriesId: series.id, seriesName: series.name, chapterId: chapterId, page: first))
        ]
        if let first, fillNext, let through = fillThrough {
            for (k, e) in following.filter({ $0.index <= through }).enumerated() {
                let p = first + (k + 1) * pagesEach
                guard p < bookPages else { break }
                changes.append((e.index, e.entry,
                                OrderFix(seriesId: series.id, seriesName: series.name, chapterId: chapterId, page: p)))
            }
        }
        store.setFixes(order, changes)
        let currentOrder = self.order
        let kavita = self.client
        Task { await ReadingOrderStore.shared.resolve(currentOrder, client: kavita, force: true) }
        dismiss()
    }
}

/// Everything in a reading order that isn't in your library, grouped by series, with a Copy button.
struct MissingIssuesSheet: View {
    let order: ReadingOrder
    let missing: [ResolvedEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var groups: [(series: String, text: String, count: Int)] {
        var orderSeen: [String] = []
        var numbers: [String: [String]] = [:]
        var oneShots: [String] = []
        for e in missing {
            if let n = e.entry.number {
                if numbers[e.entry.series] == nil { orderSeen.append(e.entry.series) }
                numbers[e.entry.series, default: []].append(n)
            } else {
                oneShots.append(e.entry.label)
            }
        }
        var out = orderSeen.map { s in (s, Self.ranges(numbers[s] ?? []), numbers[s]?.count ?? 0) }
        if !oneShots.isEmpty { out.append(("One-shots", oneShots.joined(separator: "\n"), oneShots.count)) }
        return out
    }

    private var plainText: String {
        "\(order.title) — not in my library\n\n" + groups.map { g in
            g.series == "One-shots" ? "One-shots:\n\(g.text)" : "\(g.series) \(g.text)"
        }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(missing.count) issues in \(order.title) aren't in your library.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)
                ForEach(groups, id: \.series) { g in
                    Section {
                        Text(g.text).font(.subheadline).foregroundStyle(Theme.text).textSelection(.enabled)
                    } header: {
                        Text("\(g.series) (\(g.count))")
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .kavitaBackground()
            .navigationTitle("Missing issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copied ? "Copied" : "Copy list") {
                        UIPasteboard.general.string = plainText
                        copied = true
                    }
                }
            }
        }
    }

    /// ["1","2","3","5","7","8"] -> "#1–3, 5, 7–8"
    static func ranges(_ numbers: [String]) -> String {
        let whole = numbers.compactMap { Int($0) }
        let others = numbers.filter { Int($0) == nil }
        let sorted = Array(Set(whole)).sorted()
        var parts: [String] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
            parts.append(i == j ? "\(sorted[i])" : "\(sorted[i])–\(sorted[j])")
            i = j + 1
        }
        parts += others
        return parts.isEmpty ? "" : "#" + parts.joined(separator: ", ")
    }
}
