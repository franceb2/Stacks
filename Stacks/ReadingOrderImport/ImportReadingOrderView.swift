import SwiftUI
import UniformTypeIdentifiers

extension ReadingOrderBuilder {
    /// Downloads the link again and keeps the same colors and parts.
    @MainActor
    static func refresh(_ order: ReadingOrder, client: KavitaClient) async throws -> ReadingOrder {
        guard let source = order.source, let link = source.link else { return order }
        let doc = try await ReadingOrderImporter.fetch(link: link)
        let x = OrderExtractor.extract(doc)
        let keys = Set(await ReadingOrderStore.shared.libraryIndex(client: client).keys)
        var sections = Set(x.sections.filter { source.sections.contains($0.name) }.map(\.id))
        if sections.isEmpty { sections = defaultSections(x) }
        let list = entries(x, colors: Set(source.colors), sections: sections, libraryKeys: keys,
                           hostName: order.hosts.first ?? "")
        guard !list.isEmpty else { throw ImportError.empty }
        var updated = order
        updated.entries = list
        updated.source?.added = Date()
        return updated
    }
}

/// "Add reading order": from a link (Google Docs, Sheets, Drive, Dropbox, any web page), a file
/// (Excel, CSV, Word, web page, text) or pasted text. Shows what was found before saving.
struct ImportReadingOrderView: View {
    let client: KavitaClient
    let seriesName: String
    let onSaved: (ReadingOrder) -> Void

    private enum Source: String, CaseIterable, Identifiable {
        case link = "Link", file = "File", paste = "Paste"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .link
    @State private var link = ""
    @State private var pasted = ""
    @State private var showPicker = false
    @State private var loading = false
    @State private var error: String?

    @State private var extracted: ExtractedOrder?
    @State private var origin: (link: String?, fileName: String?) = (nil, nil)
    @State private var libraryKeys: Set<String> = []
    @State private var keptColors: Set<String> = []
    @State private var keptSections: Set<Int> = []
    @State private var title = ""
    @State private var showUnmatched = false

    private static let fileTypes: [UTType] = {
        let list: [UTType?] = [.commaSeparatedText, .tabSeparatedText, .plainText, .html, .spreadsheet, .text,
                               UTType("org.openxmlformats.spreadsheetml.sheet"),
                               UTType("org.openxmlformats.wordprocessingml.document"),
                               UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "docx"), .data]
        return list.compactMap { $0 }
    }()

    private var entries: [ReadingOrder.Entry] {
        guard let extracted else { return [] }
        return ReadingOrderBuilder.entries(extracted, colors: keptColors, sections: keptSections,
                                           libraryKeys: libraryKeys, hostName: seriesName)
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if loading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading…").foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.card)
                }
                if let extracted { preview(extracted) }
            }
            .scrollContentBackground(.hidden)
            .kavitaBackground()
            .navigationTitle("Add reading order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(entries.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.fileTypes) { result in
                switch result {
                case .success(let url): loadFile(url)
                case .failure(let err): error = err.localizedDescription
                }
            }
            .task {
                libraryKeys = Set(await ReadingOrderStore.shared.libraryIndex(client: client).keys)
            }
        }
    }

    // MARK: Source

    private var sourceSection: some View {
        Section {
            Picker("From", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            switch source {
            case .link:
                TextField("Paste a link", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { loadLink() }
                Button("Load") { loadLink() }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            case .file:
                Button {
                    showPicker = true
                } label: {
                    Label("Choose a file…", systemImage: "folder")
                }
                .disabled(loading)
            case .paste:
                TextEditor(text: $pasted)
                    .frame(minHeight: 150)
                    .font(.footnote.monospaced())
                    .scrollContentBackground(.hidden)
                Button("Read text") { loadPasted() }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
            }
        } header: {
            Text("Where's the reading order?")
        } footer: {
            switch source {
            case .link:
                Text("Google Docs, Google Sheets, a file in Google Drive or Dropbox, or any web page with the list. Google files need sharing set to \"Anyone with the link\".")
            case .file:
                Text("Excel (.xlsx), CSV, Word (.docx), a saved web page (.html) or a text file, from Files, iCloud Drive or Google Drive. Colors are kept from Excel and Word files.")
            case .paste:
                Text("One issue per line works best, like \"Spawn #1\" or \"Batman (2016) #5-10\". You can paste a whole table copied from a doc or spreadsheet.")
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: Preview

    @ViewBuilder
    private func preview(_ x: ExtractedOrder) -> some View {
        Section("Name") {
            TextField("Name", text: $title)
        }
        .listRowBackground(Theme.card)

        if x.colors.count > 1 || x.colors.contains(where: { $0.color != nil }) {
            Section {
                ForEach(x.colors) { group in
                    Toggle(isOn: binding(for: group.id, in: $keptColors)) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(group.color.map { Color(cssHex: $0) } ?? Color.clear)
                                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.name)
                                Text(sample(of: group, in: x)).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text("\(group.count)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.primary)
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Turn off the colors you want to skip. Gray starts off, since reading-order docs usually use gray for optional issues. Check the doc's legend to be sure.")
            }
            .listRowBackground(Theme.card)
        }

        if x.sections.count > 1 {
            Section {
                ForEach(x.sections) { part in
                    Toggle(isOn: binding(for: part.id, in: $keptSections)) {
                        HStack {
                            Text(part.name).lineLimit(2)
                            Spacer()
                            Text("\(part.count)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.primary)
                }
            } header: {
                Text("Parts of the document")
            } footer: {
                Text("Parts that mostly repeat earlier issues, like a release-order list, start off.")
            }
            .listRowBackground(Theme.card)
        }

        let list = entries
        let found = list.filter { libraryKeys.contains(TitleKey.make($0.series)) }.count
        Section {
            if list.isEmpty {
                Text("Nothing selected. Turn on at least one color and part.").foregroundStyle(Theme.muted)
            } else {
                Text("\(list.count) issues · \(found) from series in your library")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(list.prefix(12).enumerated()), id: \.offset) { i, e in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                            .frame(width: 22, alignment: .trailing)
                        Text(e.label).font(.footnote).lineLimit(1)
                            .foregroundStyle(libraryKeys.contains(TitleKey.make(e.series)) ? Theme.text : Theme.muted)
                    }
                }
                if list.count > 12 {
                    Text("and \(list.count - 12) more").font(.footnote).foregroundStyle(Theme.muted)
                }
                let missing = unmatchedSeries(list)
                if !missing.isEmpty && !libraryKeys.isEmpty {
                    DisclosureGroup(isExpanded: $showUnmatched) {
                        ForEach(missing.prefix(40), id: \.self) { name in
                            Text(name).font(.footnote).foregroundStyle(Theme.muted)
                        }
                    } label: {
                        Text("Not in your library (\(missing.count) series)").font(.footnote)
                    }
                }
            }
        } header: {
            Text("What will be added")
        } footer: {
            Text("Series are matched by name. If something you own shows as missing, its name in Kavita is probably different. Issues you don't have stay hidden unless you turn on \"Show issues not in my library\".")
        }
        .listRowBackground(Theme.card)
    }

    private func sample(of group: ImportColorGroup, in x: ExtractedOrder) -> String {
        var names: [String] = []
        for c in x.candidates where (c.color ?? "none") == group.id && !c.titleOnly {
            if !names.contains(c.series) { names.append(c.series) }
            if names.count == 3 { break }
        }
        return names.joined(separator: ", ")
    }

    private func unmatchedSeries(_ list: [ReadingOrder.Entry]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for e in list where !libraryKeys.contains(TitleKey.make(e.series)) {
            if seen.insert(TitleKey.make(e.series)).inserted { out.append(e.series) }
        }
        return out
    }

    private func binding<T: Hashable>(for id: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(id) },
                set: { on in if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } })
    }

    // MARK: Loading

    private func loadLink() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        run(origin: (text, nil)) { try await ReadingOrderImporter.fetch(link: text) }
    }

    private func loadFile(_ url: URL) {
        run(origin: (nil, url.lastPathComponent)) {
            try await Task.detached { try ReadingOrderImporter.load(file: url) }.value
        }
    }

    private func loadPasted() {
        let text = pasted
        run(origin: (nil, nil)) {
            try await Task.detached {
                // Copied tables arrive tab-separated.
                let rows = text.contains("\t") ? CSVParser.parse(text) : TextParser.parse(text)
                return ImportedDocument(title: nil, rows: rows)
            }.value
        }
    }

    private func run(origin: (link: String?, fileName: String?), _ load: @escaping () async throws -> ImportedDocument) {
        loading = true
        error = nil
        extracted = nil
        Task {
            do {
                let doc = try await load()
                let x = await Task.detached { OrderExtractor.extract(doc) }.value
                guard !x.candidates.isEmpty else { throw ImportError.empty }
                if libraryKeys.isEmpty {
                    libraryKeys = Set(await ReadingOrderStore.shared.libraryIndex(client: client).keys)
                }
                self.origin = origin
                keptColors = ReadingOrderBuilder.defaultColors(x)
                keptSections = ReadingOrderBuilder.defaultSections(x)
                extracted = x
                if entries.isEmpty && x.candidates.allSatisfy(\.titleOnly) {
                    extracted = nil
                    throw ImportError.empty
                }
                if title.isEmpty {
                    title = doc.title?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "\(seriesName) reading order"
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func save() {
        guard let extracted else { return }
        let list = entries
        guard !list.isEmpty else { return }
        let credit: String
        if let link = origin.link {
            let host = ReadingOrderImporter.downloadURL(for: link)?.host?.replacingOccurrences(of: "www.", with: "") ?? "a link"
            credit = "Added from \(host)"
        } else if let file = origin.fileName {
            credit = "Added from \(file)"
        } else {
            credit = "Added from pasted text"
        }
        let names = Dictionary(uniqueKeysWithValues: extracted.sections.map { ($0.id, $0.name) })
        let order = ReadingOrder(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            credit: credit,
            note: nil,
            hosts: [seriesName],
            entries: list,
            years: nil,
            source: ReadingOrder.Source(link: origin.link, fileName: origin.fileName, colors: Array(keptColors),
                                        sections: keptSections.compactMap { names[$0] }, added: Date())
        )
        do {
            try ReadingOrderStore.shared.save(order)
            onSaved(order)
            dismiss()
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
