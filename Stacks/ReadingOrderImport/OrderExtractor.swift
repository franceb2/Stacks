import Foundation

/// One issue (or one-shot) found in an imported document, before you choose which colors and sections to keep.
struct ImportCandidate: Identifiable {
    let id: Int
    var series: String
    let number: String?
    var label: String
    let year: Int?
    let volume: Int?
    let color: String?
    let section: Int
    /// A title with no issue number. Kept only if a series with that name is in your library.
    let titleOnly: Bool
    /// A whole collected volume ("Vol. 1: Power and Responsibility"), with the issues it collects ("#1–7").
    var volumeName: String? = nil
    var volumeIssues: String? = nil
    var isVolume: Bool { volumeIssues != nil }
}

struct ImportSection: Identifiable {
    let id: Int
    let name: String
    var count = 0
    /// Most of its issues already appeared earlier (like a "release order" list after the reading order).
    var mostlyRepeats = false
}

struct ImportColorGroup: Identifiable {
    let color: String?
    let count: Int
    var id: String { color ?? "none" }
    var name: String { ImportColor.name(color) }
    var isGray: Bool { color.map(ImportColor.isGray) ?? false }
}

struct ExtractedOrder {
    var candidates: [ImportCandidate]
    var sections: [ImportSection]
    var colors: [ImportColorGroup]
}

enum OrderExtractor {
    private static let maxEntries = 6000
    private static let maxRange = 500

    // "Spawn #12", "Batman (2016) #4-7, 9", "Daredevil Vol. 2 #5"
    private static let itemRegex = try! NSRegularExpression(
        pattern: #"([A-Z][^#|\n]*?)\s*#\s*(\d+(?:\.\d+)?)(?:\s*[-–—]\s*#?\s*(\d+(?:\.\d+)?)(?!\d))?((?:\s*[,&]\s*#?\s*\d+(?:\s*[-–—]\s*\d+)?(?![\d/]))*)(.*?)(?=(?:[A-Z][^#|\n]*?\s*#\s*\d)|\n|$)"#)
    private static let issueWords = try! NSRegularExpression(
        pattern: #"(?i)\b(?:issues?|iss\.?|no\.|nos\.|nº|n°|ch\.|chapter)\s*(?=\d)"#)
    private static let numberCell = try! NSRegularExpression(
        pattern: #"^(?i:(?:issues?|no\.?|#|ch\.?|chapter)\s*)?(\d+(?:\.\d+)?)(?:\s*[-–—]\s*#?\s*(\d+(?:\.\d+)?))?$"#)
    private static let yearRegex = try! NSRegularExpression(pattern: #"\((?:vol(?:ume)?\.?\s*\d+\s*,?\s*)?((?:19|20)\d\d)(?:\s*[-–]\s*(?:(?:19|20)\d\d|present|now)?)?\)"#,
                                                            options: .caseInsensitive)
    private static let volumeRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:vol(?:ume)?\.?\s*|v)(\d{1,3})\b"#)

    private static let skipStarts = ["note", "notes", "begins", "after ", "post", "set ", "see ", "read ", "optional",
                                     "skip", "then ", "also ", "between", "before ", "during", "takes place", "continued",
                                     "collected", "reprint", "tpb", "trade"]
    private static let headerWords: [String: String] = [
        "title": "title", "titles": "title", "series": "title", "series name": "title", "comic": "title",
        "comics": "title", "book": "title", "name": "title", "title / arc": "title", "title/arc": "title",
        "story": "title", "series title": "title", "comic title": "title",
        "issue": "issue", "issues": "issue", "#": "issue", "no": "issue", "no.": "issue", "number": "issue",
        "issue #": "issue", "issue number": "issue", "issue no.": "issue", "chapter": "issue", "ch": "issue",
        "ch.": "issue", "iss": "issue", "iss.": "issue",
        "vol": "volume", "vol.": "volume", "volume": "volume",
        "year": "year", "start year": "year", "release year": "year", "published": "year", "pub year": "year",
        "notes": "skip", "note": "skip", "comments": "skip", "arc": "skip", "story arc": "skip", "order": "skip",
        "date": "skip", "release date": "skip", "cover date": "skip", "read": "skip", "status": "skip", "writer": "skip",
        "artist": "skip", "publisher": "skip", "format": "skip", "pages": "skip"
    ]

    static func extract(_ doc: ImportedDocument) -> ExtractedOrder {
        var candidates: [ImportCandidate] = []
        var sections: [ImportSection] = [ImportSection(id: 0, name: "Start")]
        var seenInSection: Set<String> = []
        var seenBefore: Set<String> = []
        var repeatsInSection = 0

        var roles: [String: Int] = [:]     // column roles from a header row
        var rolesTable: Int?

        func startSection(_ name: String) {
            finishSection()
            sections.append(ImportSection(id: sections.count, name: name))
            seenInSection = []
            repeatsInSection = 0
        }
        func finishSection() {
            guard var last = sections.popLast() else { return }
            last.mostlyRepeats = last.count >= 5 && repeatsInSection * 10 >= last.count * 8
            sections.append(last)
            for key in seenInSection { seenBefore.insert(key) }
        }

        func add(series rawSeries: String, number: String?, rest: String, color: String?, titleOnly: Bool = false,
                 yearHint: Int? = nil, volumeHint: Int? = nil) {
            guard candidates.count < maxEntries else { return }
            var (series, year, volume) = splitSeries(rawSeries)
            year = year ?? yearHint
            volume = volume ?? volumeHint
            series = series.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—|·•*").union(.whitespaces))
            guard series.count >= 1, series.count <= 90, series.contains(where: \.isLetter) else { return }
            let lower = series.lowercased()
            if skipStarts.contains(where: { lower.hasPrefix($0) }) { return }

            let numberKey = number.flatMap { TitleKey.number($0) }.map { String($0) } ?? "-"
            let key = "\(TitleKey.make(series))|\(year ?? 0)|\(volume ?? 0)|\(numberKey)"
            if seenInSection.contains(key) { return }
            seenInSection.insert(key)
            if seenBefore.contains(key) { repeatsInSection += 1 }

            var label = number.map { "\(series) #\($0)" } ?? series
            if let year, number != nil, rawSeries.contains("\(year)") { label = number.map { "\(series) (\(year)) #\($0)" } ?? label }
            let extra = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—|()").union(.whitespacesAndNewlines))
            if !extra.isEmpty, extra.count <= 70, extra.contains(where: \.isLetter),
               !extra.lowercased().hasPrefix("note") {
                label += ", \(extra)"
            }
            candidates.append(ImportCandidate(id: candidates.count, series: series, number: number, label: label,
                                              year: year, volume: volume, color: color,
                                              section: sections.count - 1, titleOnly: titleOnly))
            sections[sections.count - 1].count += 1
        }

        /// Every "Title #N" in a piece of text. Returns false when there were none.
        @discardableResult
        func addMatches(in rawText: String, color: String?) -> Bool {
            let text = normalize(rawText)
            let ns = text as NSString
            var found = false
            for m in itemRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let series = ns.substring(with: m.range(at: 1))
                let first = ns.substring(with: m.range(at: 2))
                let rest = m.range(at: 5).location != NSNotFound ? ns.substring(with: m.range(at: 5)) : ""
                var numbers: [String] = []
                if m.range(at: 3).location != NSNotFound {
                    numbers += expand(first, ns.substring(with: m.range(at: 3)))
                } else {
                    numbers.append(first)
                }
                if m.range(at: 4).location != NSNotFound {
                    let list = ns.substring(with: m.range(at: 4))
                    for part in list.components(separatedBy: CharacterSet(charactersIn: ",&")) {
                        let p = part.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                        if p.isEmpty { continue }
                        let bounds = p.components(separatedBy: CharacterSet(charactersIn: "-–—"))
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        numbers += bounds.count == 2 ? expand(bounds[0], bounds[1]) : [bounds[0]]
                    }
                }
                let single = numbers.count == 1
                for n in numbers {
                    add(series: series, number: n, rest: single ? rest : "", color: color)
                    found = true
                }
            }
            return found
        }

        for row in doc.rows {
            let cells = row.cells
            let joined = cells.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
            if joined.isEmpty { continue }

            if row.table != rolesTable { roles = [:]; rolesTable = row.table }

            // Header row: remember which column is which.
            let headerHits = cells.enumerated().compactMap { i, c -> (String, Int)? in
                headerWords[c.text.lowercased().trimmingCharacters(in: .whitespaces)].map { ($0, i) }
            }
            if headerHits.count >= 2 {
                // When several columns could be the issue, "Issue" beats "No." beats "#" (often just a row count).
                func rank(_ i: Int) -> Int {
                    switch cells[i].text.lowercased().trimmingCharacters(in: .whitespaces) {
                    case "#": return 0
                    case "no", "no.", "number": return 1
                    default: return 2
                    }
                }
                var r: [String: Int] = [:]
                for (role, i) in headerHits where role != "skip" {
                    if let existing = r[role], role != "issue" || rank(existing) >= rank(i) { continue }
                    r[role] = i
                }
                if r["title"] != nil || r["issue"] != nil { roles = r; continue }
            }

            // Headings start a new section.
            if isHeading(row) {
                startSection(clean(joined))
                continue
            }

            // 1. Columns from a header row, when the issue column holds a plain number.
            if let titleCol = roles["title"], titleCol < cells.count, let issueCol = roles["issue"], issueCol < cells.count,
               !cells[titleCol].text.contains("#"), let range = isNumberCell(cells[issueCol].text) {
                let titleCell = cells[titleCol]
                let color = titleCell.color ?? cells.first(where: { $0.color != nil })?.color
                let yearHint = roles["year"].flatMap { $0 < cells.count ? Int(cells[$0].text.prefix(4)) : nil }
                let volumeHint = roles["volume"].flatMap { $0 < cells.count ? leadingInt(cells[$0].text) : nil }
                for n in range {
                    add(series: titleCell.text, number: n, rest: "", color: color, yearHint: yearHint, volumeHint: volumeHint)
                }
                continue
            }

            // 1b. A collected volume: "Vol. 1: Power and Responsibility" | "Ultimate Spider-Man #1–7".
            //     One entry for the whole volume, matched to that volume in your library.
            if let volCell = cells.first(where: { volumeTitle($0.text) != nil }), let vol = volumeTitle(volCell.text),
               let issueCell = cells.first(where: { $0.text != volCell.text && firstItem(in: $0.text) != nil }),
               let item = firstItem(in: issueCell.text) {
                let before = candidates.count
                add(series: item.series, number: nil, rest: "", color: issueCell.color ?? volCell.color, volumeHint: vol.number)
                if candidates.count > before {
                    candidates[candidates.count - 1].volumeName = vol.name
                    candidates[candidates.count - 1].volumeIssues = item.issues
                }
                continue
            }

            // 2. "Title #N" inside each cell, keeping each cell's color.
            var found = false
            for cell in cells where !cell.text.isEmpty {
                for line in cell.text.components(separatedBy: "\n") {
                    if addMatches(in: line, color: cell.color) { found = true }
                }
            }
            if found { continue }

            // 3. The whole row together ("Spawn" | "#5").
            if cells.count > 1, addMatches(in: joined, color: cells.first(where: { $0.color != nil })?.color) { continue }

            // 4. A title cell next to a number cell ("Spawn" | "5").
            if cells.count > 1, let titleIndex = cells.firstIndex(where: { isTitleCell($0.text) }) {
                let after = cells[(titleIndex + 1)...].compactMap { isNumberCell($0.text, allowYears: false) }.first
                let before = cells[..<titleIndex].compactMap { isNumberCell($0.text, allowYears: false) }.last
                if let range = after ?? before {
                    let color = cells[titleIndex].color ?? cells.first(where: { $0.color != nil })?.color
                    for n in range { add(series: cells[titleIndex].text, number: n, rest: "", color: color) }
                    continue
                }
            }

            // 5. One-shots ("Spawn/Batman (One-Shot)").
            var oneShot = false
            for cell in cells {
                for line in cell.text.components(separatedBy: "\n") {
                    let t = normalize(line)
                    if let r = t.range(of: #"\(\s*one[- ]?shot\s*\)"#, options: [.regularExpression, .caseInsensitive]),
                       isTitleCell(String(t[..<r.lowerBound])) {
                        add(series: String(t[..<r.lowerBound]), number: nil, rest: "", color: cell.color)
                        oneShot = true
                    }
                }
            }
            if oneShot { continue }

            // 6. A title with no number (kept only if it's in your library).
            let titleCell = roles["title"].flatMap { $0 < cells.count ? cells[$0] : nil }
                ?? cells.first(where: { isTitleCell($0.text) })
            if let titleCell, !titleCell.text.contains("\n") {
                let t = stripListMarker(normalize(titleCell.text))
                if t.count <= 80, !t.hasSuffix(":"), isTitleCell(t) {
                    add(series: t, number: nil, rest: "", color: titleCell.color, titleOnly: true)
                }
            }
        }
        finishSection()

        // Volume rows belong to the main run: "Vol. 9: Ultimate Six | Ultimate Six #1–7" is Ultimate Spider-Man
        // Vol. 9, which collects Ultimate Six. Use the series most volume rows name.
        let volumeRows = candidates.indices.filter { candidates[$0].isVolume }
        if !volumeRows.isEmpty {
            var counts: [String: Int] = [:]
            var names: [String: String] = [:]
            for i in volumeRows {
                let key = TitleKey.make(candidates[i].series)
                counts[key, default: 0] += 1
                if names[key] == nil { names[key] = candidates[i].series }
            }
            let mainKey = volumeRows.map { TitleKey.make(candidates[$0].series) }
                .max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? ""
            let main = names[mainKey] ?? candidates[volumeRows[0]].series
            for i in volumeRows {
                let c = candidates[i]
                let own = TitleKey.make(c.series) == mainKey
                let issues = own ? (c.volumeIssues ?? "") : "\(c.series) \(c.volumeIssues ?? "")"
                let name = (c.volumeName ?? "").isEmpty ? "" : ": \(c.volumeName ?? "")"
                candidates[i].series = main
                candidates[i].label = "\(main) Vol. \(c.volume ?? 0)\(name) (\(issues))"
            }
        }

        // Colors, most common first.
        var counts: [String: Int] = [:]
        var order: [String] = []
        for c in candidates where !c.titleOnly {
            let k = c.color ?? ""
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
        }
        let colors = order.map { ImportColorGroup(color: $0.isEmpty ? nil : $0, count: counts[$0] ?? 0) }
            .sorted { $0.count > $1.count }

        return ExtractedOrder(candidates: candidates, sections: sections.filter { $0.count > 0 }, colors: colors)
    }

    // MARK: Helpers

    /// Turns "Issue 5" / "No. 5" into "#5", tidies dashes and spaces, and drops "(Note: …)".
    private static func normalize(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "＃", with: "#")
        t = t.replacingOccurrences(of: #"\((?i:note|notes)\b[^)]*\)"#, with: " ", options: .regularExpression)
        let ns = t as NSString
        t = issueWords.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "#")
        return t
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func stripListMarker(_ s: String) -> String {
        s.replacingOccurrences(of: #"^\s*(?:[-•*▪◦·]|\d{1,4}[.)])\s+"#, with: "", options: .regularExpression)
    }

    private static let volumeTitleRegex = try! NSRegularExpression(
        pattern: #"^\s*vol(?:ume)?\.?\s*(\d{1,3})\b\s*(?:[:\-–—.]\s*(.*))?$"#, options: .caseInsensitive)

    /// "Vol. 1: Power and Responsibility" -> (1, "Power and Responsibility")
    static func volumeTitle(_ text: String) -> (number: Int, name: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = t as NSString
        guard let m = volumeTitleRegex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              let n = Int(ns.substring(with: m.range(at: 1))) else { return nil }
        let name = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
        return (n, name.trimmingCharacters(in: .whitespaces))
    }

    /// The first "Series #…" in a cell, and the issue part ("#1–7", "#86–90 + Annual #1").
    static func firstItem(in text: String) -> (series: String, issues: String)? {
        let t = normalize(text)
        let ns = t as NSString
        guard let m = itemRegex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let series = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let from = t.range(of: series)?.upperBound ?? t.startIndex
        guard let hash = t.range(of: "#", range: from..<t.endIndex) else { return nil }
        let issues = String(t[hash.lowerBound...]).components(separatedBy: "\n")[0]
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (series, issues)
    }

    /// "Daredevil (1964)" -> ("Daredevil", 1964, nil); "Daredevil Vol. 2" -> ("Daredevil", nil, 2)
    static func splitSeries(_ raw: String) -> (String, Int?, Int?) {
        var s = stripListMarker(raw)
        var year: Int?
        var volume: Int?
        let ns = s as NSString
        if let m = yearRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            year = Int(ns.substring(with: m.range(at: 1)))
            s = ns.replacingCharacters(in: m.range, with: " ")
        }
        let ns2 = s as NSString
        if let m = volumeRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns2.length)) {
            volume = Int(ns2.substring(with: m.range(at: 1)))
            s = ns2.replacingCharacters(in: m.range, with: " ")
        }
        // Other bracketed bits like "(Image)" or "(A.K.A. The Red Scare)" aren't part of the title.
        let stripped = s.replacingOccurrences(of: #"\s*[(\[][^)\]]*[)\]]"#, with: " ", options: .regularExpression)
        if stripped.contains(where: \.isLetter) { s = stripped }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return (s.trimmingCharacters(in: .whitespaces), year, volume)
    }

    private static func expand(_ a: String, _ b: String) -> [String] {
        guard let lo = Int(a), let hi = Int(b), hi >= lo, hi - lo < maxRange else { return [a] }
        return (lo...hi).map(String.init)
    }

    /// "5", "#5", "5-8", "Issue 5" -> the issue numbers.
    private static func isNumberCell(_ text: String, allowYears: Bool = true) -> [String]? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let ns = t as NSString
        guard !t.isEmpty, let m = numberCell.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let first = ns.substring(with: m.range(at: 1))
        if !allowYears, m.range(at: 2).location == NSNotFound, first.count == 4, let y = Int(first), (1900...2099).contains(y) {
            return nil
        }
        if m.range(at: 2).location != NSNotFound { return expand(first, ns.substring(with: m.range(at: 2))) }
        return [first]
    }

    private static func isTitleCell(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.count <= 120, t.first?.isLetter == true || t.first?.isNumber == true else { return false }
        guard t.filter(\.isLetter).count >= 2 else { return false }
        if headerWords[t.lowercased()] != nil { return false }
        if t.lowercased().hasPrefix("http") { return false }
        return true
    }

    private static func leadingInt(_ text: String) -> Int? {
        Int(text.filter(\.isNumber).prefix(3))
    }

    /// A heading row: a real heading, or a short ALL-CAPS line with no issue numbers.
    private static func isHeading(_ row: ImportRow) -> Bool {
        let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.contains("#") || text.count > 70 { return false }
        if row.heading { return true }
        guard row.cells.filter({ !$0.text.isEmpty }).count == 1 else { return false }
        let letters = text.filter(\.isLetter)
        return letters.count >= 6 && letters.allSatisfy(\.isUppercase) && text.contains(" ")
    }
}

/// Turns what was found in a document into a saved reading order, and refreshes ones added from a link.
enum ReadingOrderBuilder {
    static func defaultColors(_ x: ExtractedOrder) -> Set<String> {
        let notGray = x.colors.filter { !$0.isGray }.map(\.id)
        return Set(notGray.isEmpty ? x.colors.map(\.id) : notGray)
    }

    static func defaultSections(_ x: ExtractedOrder) -> Set<Int> {
        let fresh = x.sections.filter { !$0.mostlyRepeats }.map(\.id)
        return Set(fresh.isEmpty ? x.sections.map(\.id) : fresh)
    }

    static func entries(_ x: ExtractedOrder, colors: Set<String>, sections: Set<Int>,
                        libraryKeys: Set<String>, hostName: String) -> [ReadingOrder.Entry] {
        let hostKey = TitleKey.make(hostName)
        let groupIds = Set(x.colors.map(\.id))
        let names = Dictionary(uniqueKeysWithValues: x.sections.map { ($0.id, $0.name) })
        return x.candidates.compactMap { c in
            guard sections.contains(c.section) else { return nil }
            let colorId = c.color ?? "none"
            if c.titleOnly {
                guard libraryKeys.contains(TitleKey.make(c.series)) else { return nil }
                if groupIds.contains(colorId), !colors.contains(colorId) { return nil }
            } else if !colors.contains(colorId) {
                return nil
            }
            let kind = c.isVolume ? "volume"
                : c.number == nil ? "oneshot" : (TitleKey.make(c.series) == hostKey ? "main" : "spinoff")
            return ReadingOrder.Entry(series: c.series, label: c.label, kind: kind, section: names[c.section] ?? "",
                                      number: c.number, year: c.year, volume: c.volume)
        }
    }
}
