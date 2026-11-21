import Foundation

/// One cell of an imported table (or one line of a document), with its color as "#rrggbb".
struct ImportCell {
    var text: String
    var color: String?
}

/// One row of a table, or one paragraph of a document.
struct ImportRow {
    var cells: [ImportCell]
    /// A heading (Heading style, all-caps line, or a sheet name) starts a new section.
    var heading = false
    /// Rows from the same table share an id, so column headers carry over to the rows below.
    var table: Int? = nil

    var text: String { cells.map(\.text).joined(separator: " ") }
}

struct ImportedDocument {
    var title: String?
    var rows: [ImportRow]
}

enum ImportError: LocalizedError {
    case signIn, notFound, empty, unreadable(String), http(Int)

    var errorDescription: String? {
        switch self {
        case .signIn:
            return "That link asks for a Google sign-in. In Google, tap Share and set it to \"Anyone with the link\" (viewer), or download the file and import it from Files."
        case .notFound:
            return "Nothing was found at that link. Check it and try again."
        case .empty:
            return "No issues were found. Entries need a title and an issue number, like \"Spawn #1\", or columns for title and issue."
        case .unreadable(let kind):
            return "Couldn't read this \(kind). Try saving it as .xlsx, .csv or .docx, or paste the text instead."
        case .http(let code):
            return "The link answered with an error (\(code)). Make sure it's shared publicly."
        }
    }
}

// MARK: - Colors

enum ImportColor {
    /// "#abc", "rgb(1,2,3)", "FF112233" (Excel) or a few names, as "#rrggbb". nil for none/transparent.
    static func normalize(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        if s.hasPrefix("rgb") {
            let nums = s.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
                .compactMap { Int($0) }
            guard nums.count >= 3 else { return nil }
            if s.hasPrefix("rgba"), nums.count >= 4, nums[3] == 0, !s.contains(".") { return nil }
            return String(format: "#%02x%02x%02x", min(nums[0], 255), min(nums[1], 255), min(nums[2], 255))
        }
        let names = ["black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
                     "blue": "#0000ff", "gray": "#808080", "grey": "#808080", "yellow": "#ffff00",
                     "orange": "#ffa500", "purple": "#800080", "silver": "#c0c0c0", "darkred": "#8b0000",
                     "darkgreen": "#006400", "maroon": "#800000", "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3",
                     "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9"]
        if let named = names[s] { return named }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 8 { s = String(s.suffix(6)) }   // Excel's ARGB
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + s
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        guard hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Near-white backgrounds don't count as a color.
    static func isBlankBackground(_ hex: String?) -> Bool {
        guard let hex, let c = rgb(hex) else { return true }
        let (r, g, b) = c
        return r > 0.96 && g > 0.96 && b > 0.96
    }

    /// Black text is just normal text.
    static func isPlainText(_ hex: String?) -> Bool {
        guard let hex, let c = rgb(hex) else { return true }
        let (r, g, b) = c
        return r < 0.13 && g < 0.13 && b < 0.13
    }

    /// Gray (not black or white). Reading-order docs use gray for optional issues.
    static func isGray(_ hex: String) -> Bool {
        guard let c = rgb(hex) else { return false }
        let (r, g, b) = c
        let hi = max(r, g, b), lo = min(r, g, b)
        return hi - lo < 0.08 && hi > 0.2 && hi < 0.97
    }

    static func name(_ hex: String?) -> String {
        guard let hex, let c = rgb(hex) else { return "No color" }
        let (r, g, b) = c
        let hi = max(r, g, b), lo = min(r, g, b)
        if hi - lo < 0.08 {
            if hi < 0.2 { return "Black" }
            if hi > 0.97 { return "White" }
            return hi < 0.5 ? "Dark gray" : "Gray"
        }
        var hue: Double
        let d = hi - lo
        if hi == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if hi == g { hue = (b - r) / d + 2 }
        else { hue = (r - g) / d + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        let base: String
        switch hue {
        case ..<15, 345...: base = "Red"
        case ..<40: base = "Orange"
        case ..<65: base = "Yellow"
        case ..<165: base = "Green"
        case ..<200: base = "Teal"
        case ..<255: base = "Blue"
        case ..<290: base = "Purple"
        default: base = "Pink"
        }
        if hi < 0.45 { return "Dark \(base.lowercased())" }
        if lo > 0.7 { return "Light \(base.lowercased())" }
        return base
    }
}

// MARK: - Loading

enum ReadingOrderImporter {
    /// Turns a share link into something downloadable: Google Docs as a web page, Google Sheets as Excel
    /// (both keep colors), Drive and Dropbox files as the file itself.
    static func downloadURL(for link: String) -> URL? {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return nil }

        func id(after marker: String) -> String? {
            guard let r = text.range(of: marker) else { return nil }
            let rest = text[r.upperBound...]
            let id = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return id.isEmpty ? nil : String(id)
        }

        if host == "docs.google.com" {
            if let id = id(after: "/document/d/") {
                return URL(string: "https://docs.google.com/document/d/\(id)/export?format=html")
            }
            if let id = id(after: "/spreadsheets/d/") {
                return URL(string: "https://docs.google.com/spreadsheets/d/\(id)/export?format=xlsx")
            }
            if let id = id(after: "/presentation/d/") {
                return URL(string: "https://docs.google.com/presentation/d/\(id)/export/txt")
            }
        }
        if host == "drive.google.com" {
            if let id = id(after: "/file/d/") ?? id(after: "id=") {
                return URL(string: "https://drive.google.com/uc?export=download&id=\(id)")
            }
        }
        if host.hasSuffix("dropbox.com"), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = (comps.queryItems ?? []).filter { $0.name != "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            comps.queryItems = items
            return comps.url
        }
        return url
    }

    static func fetch(link: String) async throws -> ImportedDocument {
        guard let url = downloadURL(for: link) else { throw ImportError.notFound }
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let finalHost = response.url?.host?.lowercased() ?? ""
        if finalHost.contains("accounts.google.com") { throw ImportError.signIn }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 { throw ImportError.signIn }
            if http.statusCode == 404 { throw ImportError.notFound }
            throw ImportError.http(http.statusCode)
        }
        var name = url.lastPathComponent
        if let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition"),
           let file = filename(fromDisposition: disposition) {
            name = file
        }
        return try parse(data: data, filename: name)
    }

    /// `attachment; filename="Spawn.html"; filename*=UTF-8''Spawn%20Reading%20Order.html`
    static func filename(fromDisposition header: String) -> String? {
        for part in header.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("filename*=") {
                let value = p.dropFirst("filename*=".count)
                let encoded = value.components(separatedBy: "''").last ?? String(value)
                if let decoded = encoded.removingPercentEncoding, !decoded.isEmpty { return decoded }
            }
        }
        for part in header.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("filename=") {
                let v = p.dropFirst("filename=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    static func load(file url: URL) throws -> ImportedDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try parse(data: data, filename: url.lastPathComponent)
    }

    /// Works out what kind of file this is from its contents (and name), then reads it.
    static func parse(data: Data, filename: String) throws -> ImportedDocument {
        let ext = (filename as NSString).pathExtension.lowercased()
        let baseName = (filename as NSString).deletingPathExtension
        let title = baseName.isEmpty || baseName == "uc" || baseName == "export" ? nil : baseName

        if data.count > 4, data[0] == 0x50, data[1] == 0x4B {
            guard let zip = ZipReader(data: data) else { throw ImportError.unreadable("file") }
            if zip.contains("xl/workbook.xml") {
                var doc = try XLSXParser.parse(zip)
                doc.title = doc.title ?? title
                return doc
            }
            if zip.contains("word/document.xml") {
                var doc = try DOCXParser.parse(zip)
                doc.title = doc.title ?? title
                return doc
            }
            if let html = zip.names.first(where: { $0.lowercased().hasSuffix(".html") }), let inner = zip.data(html) {
                // Google Docs' "Web page (.html, zipped)" download.
                return try parse(data: inner, filename: (html as NSString).lastPathComponent)
            }
            throw ImportError.unreadable(ext.isEmpty ? "file" : ".\(ext) file")
        }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { throw ImportError.unreadable("PDF") }

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) else { throw ImportError.unreadable("file") }
        let head = text.prefix(4000).lowercased()
        if text.contains("accounts.google.com/ServiceLogin") || text.contains("accounts.google.com/v3/signin") {
            throw ImportError.signIn
        }
        if ext == "html" || ext == "htm" || head.contains("<html") || head.contains("<!doctype html")
            || head.contains("<table") || head.contains("<body") {
            var doc = HTMLParser.parse(text)
            doc.title = doc.title ?? title
            return doc
        }
        if ext == "csv" || ext == "tsv" || CSVParser.looksLikeCSV(text) {
            return ImportedDocument(title: title, rows: CSVParser.parse(text))
        }
        return ImportedDocument(title: title, rows: TextParser.parse(text))
    }
}

// MARK: - Plain text and CSV

enum TextParser {
    static func parse(_ text: String) -> [ImportRow] {
        text.components(separatedBy: .newlines).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            // Markdown headings count as headings.
            if t.hasPrefix("#"), let first = t.dropFirst().first, first == "#" || first == " " {
                let title = t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return ImportRow(cells: [ImportCell(text: title)], heading: true)
            }
            return ImportRow(cells: [ImportCell(text: t)])
        }
    }
}

enum CSVParser {
    static func delimiter(for text: String) -> Character {
        let lines = text.split(separator: "\n", maxSplits: 20).prefix(20)
        var best: Character = ","
        var bestCount = 0
        for candidate in [",", "\t", ";"] as [Character] {
            var count = 0
            for line in lines { count += line.filter { ch in ch == candidate }.count }
            if count > bestCount { best = candidate; bestCount = count }
        }
        return best
    }

    static func looksLikeCSV(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(30)
        guard lines.count >= 2 else { return false }
        let d = delimiter(for: text)
        let counts = lines.map { $0.filter { $0 == d }.count }
        let withDelimiter = counts.filter { $0 > 0 }.count
        return withDelimiter * 10 >= lines.count * 8 && Set(counts).count <= 3
    }

    static func parse(_ text: String) -> [ImportRow] {
        let d = delimiter(for: text)
        var rows: [ImportRow] = []
        var cells: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0

        func endRow() {
            cells.append(field)
            field = ""
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
            if trimmed.contains(where: { !$0.isEmpty }) {
                rows.append(ImportRow(cells: trimmed.map { ImportCell(text: $0) }, table: 0))
            }
            cells = []
        }

        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                quoted = true
            } else if c == d {
                cells.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                endRow()
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !cells.isEmpty { endRow() }
        return rows
    }
}

// MARK: - HTML (Google Docs, web pages)

enum HTMLParser {
    private struct Style { var background: String?; var color: String? }

    static func parse(_ html: String) -> ImportedDocument {
        // Class styles from <style> blocks (Google Docs uses classes like .c12{background-color:#000000}).
        var classes: [String: Style] = [:]
        if let styleBlock = try? NSRegularExpression(pattern: #"<style[^>]*>([\s\S]*?)</style>"#, options: .caseInsensitive),
           let rule = try? NSRegularExpression(pattern: #"\.([A-Za-z0-9_-]+)\s*\{([^}]*)\}"#) {
            let ns = html as NSString
            for block in styleBlock.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let css = ns.substring(with: block.range(at: 1))
                let cns = css as NSString
                for m in rule.matches(in: css, range: NSRange(location: 0, length: cns.length)) {
                    let name = cns.substring(with: m.range(at: 1))
                    let parsed = parseStyle(cns.substring(with: m.range(at: 2)))
                    if parsed.background != nil || parsed.color != nil { classes[name] = parsed }
                }
            }
        }

        func style(ofTag attrs: String) -> Style {
            var s = Style()
            if let cls = attribute("class", in: attrs) {
                for name in cls.split(separator: " ") {
                    if let c = classes[String(name)] {
                        s.background = c.background ?? s.background
                        s.color = c.color ?? s.color
                    }
                }
            }
            if let inline = attribute("style", in: attrs) {
                let i = parseStyle(inline)
                s.background = i.background ?? s.background
                s.color = i.color ?? s.color
            }
            if let bg = attribute("bgcolor", in: attrs) { s.background = ImportColor.normalize(bg) ?? s.background }
            if let fg = attribute("color", in: attrs) { s.color = ImportColor.normalize(fg) ?? s.color }
            return s
        }

        var rows: [ImportRow] = []
        var title: String?

        // Table state.
        var tableDepth = 0
        var tableCount = 0
        var tableIds: [Int] = []
        var row: [ImportCell]? = nil
        var cell: (text: String, background: String?, firstBackground: String?, firstColor: String?)? = nil

        // Text outside tables.
        var block = ""
        var blockHeading = false
        var blockBackground: String?
        var blockColor: String?

        var inlineStack: [Style] = []
        var skipDepth = 0          // inside <script>, <style>, <head> title etc.
        var inTitle = false
        var titleText = ""

        func flushBlock() {
            let t = clean(block)
            if !t.isEmpty {
                let color = !ImportColor.isBlankBackground(blockBackground) ? blockBackground
                    : (!ImportColor.isPlainText(blockColor) ? blockColor : nil)
                rows.append(ImportRow(cells: [ImportCell(text: t, color: color)], heading: blockHeading))
            }
            block = ""
            blockHeading = false
            blockBackground = nil
            blockColor = nil
        }

        func addText(_ raw: String) {
            let text = decodeEntities(raw)
            if inTitle { titleText += text; return }
            if skipDepth > 0 { return }
            let visible = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var bg: String?
            var fg: String?
            for s in inlineStack.reversed() {
                if bg == nil, !ImportColor.isBlankBackground(s.background) { bg = s.background }
                if fg == nil, s.color != nil { fg = s.color }
            }
            if cell != nil {
                cell!.text += text
                if visible {
                    if cell!.firstBackground == nil { cell!.firstBackground = bg }
                    if cell!.firstColor == nil, !ImportColor.isPlainText(fg) { cell!.firstColor = fg }
                }
            } else {
                block += text
                if visible {
                    if blockBackground == nil { blockBackground = bg }
                    if blockColor == nil, !ImportColor.isPlainText(fg) { blockColor = fg }
                }
            }
        }

        func closeCell() {
            guard let c = cell else { return }
            let t = clean(c.text)
            let color: String? = !ImportColor.isBlankBackground(c.background) ? c.background
                : (c.firstBackground ?? c.firstColor)
            if row == nil { row = [] }
            row!.append(ImportCell(text: t, color: color))
            cell = nil
        }

        func closeRow() {
            closeCell()
            if let r = row, r.contains(where: { !$0.text.isEmpty }) {
                rows.append(ImportRow(cells: r, table: tableIds.last))
            }
            row = nil
        }

        let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
                                      "section", "article", "dt", "dd", "pre", "ul", "ol", "header", "footer"]
        let inlineTags: Set<String> = ["span", "font", "mark", "a", "b", "strong", "i", "em", "u", "s"]

        guard let tagRegex = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)([^>]*)>"#) else {
            return ImportedDocument(title: nil, rows: [])
        }
        let ns = html as NSString
        var cursor = 0
        for m in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                addText(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = m.range.location + m.range.length
            guard m.range(at: 2).location != NSNotFound else { continue }   // comment
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            let tag = ns.substring(with: m.range(at: 2)).lowercased()
            let attrs = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""

            switch tag {
            case "script", "style", "noscript", "svg":
                skipDepth += closing ? -1 : 1
                skipDepth = max(skipDepth, 0)
            case "title":
                inTitle = !closing
                if closing, title == nil { title = clean(decodeEntities(titleText)) }
            case "table":
                if closing {
                    closeRow()
                    tableDepth = max(0, tableDepth - 1)
                    if !tableIds.isEmpty { tableIds.removeLast() }
                } else {
                    if tableDepth == 0 { flushBlock() }
                    tableDepth += 1
                    tableCount += 1
                    tableIds.append(tableCount)
                }
            case "tr":
                if tableDepth <= 1 { closeRow() } else if cell != nil { cell!.text += "\n" }
                if !closing, tableDepth <= 1 { row = [] }
            case "td", "th":
                if tableDepth <= 1 {
                    closeCell()
                    if !closing {
                        let s = style(ofTag: attrs)
                        cell = (text: "", background: s.background, firstBackground: nil, firstColor: nil)
                        inlineStack.removeAll()
                    }
                } else if cell != nil {
                    cell!.text += "\n"
                }
            case "br":
                if cell != nil { cell!.text += "\n" } else { flushBlock() }
            default:
                if blockTags.contains(tag) {
                    if cell != nil {
                        cell!.text += "\n"
                        if !closing { inlineStack.append(style(ofTag: attrs)) } else if !inlineStack.isEmpty { inlineStack.removeLast() }
                    } else {
                        flushBlock()
                        if !closing {
                            blockHeading = tag.count == 2 && tag.hasPrefix("h")
                            let s = style(ofTag: attrs)
                            blockBackground = ImportColor.isBlankBackground(s.background) ? nil : s.background
                            inlineStack = [s]
                        } else {
                            inlineStack.removeAll()
                        }
                    }
                } else if inlineTags.contains(tag) {
                    if closing {
                        if !inlineStack.isEmpty { inlineStack.removeLast() }
                    } else if !attrs.hasSuffix("/") {
                        inlineStack.append(style(ofTag: attrs))
                    }
                }
            }
        }
        if cursor < ns.length { addText(ns.substring(from: cursor)) }
        closeRow()
        flushBlock()
        return ImportedDocument(title: (title?.isEmpty ?? true) ? nil : title, rows: rows)
    }

    private static func parseStyle(_ css: String) -> Style {
        var s = Style()
        for decl in css.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "background-color", "background":
                let value = parts[1].split(separator: " ").first.map(String.init) ?? parts[1]
                s.background = ImportColor.normalize(value.hasPrefix("rgb") ? parts[1] : value)
            case "color":
                s.color = ImportColor.normalize(parts[1])
            default:
                break
            }
        }
        return s
    }

    private static func attribute(_ name: String, in attrs: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = attrs as NSString
        guard let m = re.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for i in 2...4 where m.range(at: i).location != NSNotFound { return ns.substring(with: m.range(at: i)) }
        return nil
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                       "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”", "ndash": "–",
                                       "mdash": "—", "hellip": "…", "eacute": "é", "copy": "©", "reg": "®",
                                       "trade": "™", "bull": "•", "middot": "·", "times": "×"]
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let name = String(s[s.index(after: i)..<semi])
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    if let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replacement = String(u) }
                } else if name.hasPrefix("#") {
                    if let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) { replacement = String(u) }
                } else {
                    replacement = named[name]
                }
                if let replacement {
                    out += replacement
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}

// MARK: - XML helper

/// Collects a flat list of elements (name, attributes, own text) from an XML file.
private final class FlatXML: NSObject, XMLParserDelegate {
    enum Event {
        case open(String, [String: String])
        case close(String)
        case text(String)
    }
    var events: [Event] = []

    static func events(_ data: Data) -> [Event] {
        let parser = XMLParser(data: data)
        let delegate = FlatXML()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.events
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        events.append(.open(elementName, attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        events.append(.close(elementName))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        events.append(.text(string))
    }
}

// MARK: - Excel (.xlsx)

enum XLSXParser {
    static func parse(_ zip: ZipReader) throws -> ImportedDocument {
        // Shared strings.
        var shared: [String] = []
        if let data = zip.data("xl/sharedStrings.xml") {
            var current: String?
            var inText = false
            var inPhonetic = false
            for e in FlatXML.events(data) {
                switch e {
                case .open("si", _): current = ""
                case .open("t", _): inText = true
                case .open("rPh", _): inPhonetic = true
                case .close("rPh"): inPhonetic = false
                case .text(let t): if inText, !inPhonetic { current? += t }
                case .close("t"): inText = false
                case .close("si"): shared.append(current ?? ""); current = nil
                default: break
                }
            }
        }

        // Styles: each cell style points at a fill and a font.
        var fills: [String?] = []
        var fonts: [String?] = []
        var xfs: [(fill: Int, font: Int)] = []
        if let data = zip.data("xl/styles.xml") {
            var section = ""
            var fillColor: String?
            var fontColor: String?
            var solid = false
            for e in FlatXML.events(data) {
                switch e {
                case .open("fills", _): section = "fills"
                case .open("fonts", _): section = "fonts"
                case .open("cellXfs", _): section = "xfs"
                case .close("fills"), .close("fonts"), .close("cellXfs"): section = ""
                case .open("fill", _) where section == "fills": fillColor = nil; solid = false
                case .open("patternFill", let a) where section == "fills": solid = a["patternType"] == "solid"
                case .open("fgColor", let a) where section == "fills":
                    if solid { fillColor = ImportColor.normalize(a["rgb"]) }
                case .close("fill") where section == "fills": fills.append(fillColor)
                case .open("font", _) where section == "fonts": fontColor = nil
                case .open("color", let a) where section == "fonts": fontColor = ImportColor.normalize(a["rgb"])
                case .close("font") where section == "fonts": fonts.append(fontColor)
                case .open("xf", let a) where section == "xfs":
                    xfs.append((Int(a["fillId"] ?? "") ?? 0, Int(a["fontId"] ?? "") ?? 0))
                default: break
                }
            }
        }
        func color(style: Int?) -> String? {
            guard let style, style < xfs.count else { return nil }
            let xf = xfs[style]
            if xf.fill < fills.count, let fill = fills[xf.fill], !ImportColor.isBlankBackground(fill) { return fill }
            if xf.font < fonts.count, let font = fonts[xf.font], !ImportColor.isPlainText(font) { return font }
            return nil
        }

        // Sheets in workbook order.
        var sheets: [(name: String, path: String)] = []
        var rels: [String: String] = [:]
        if let data = zip.data("xl/_rels/workbook.xml.rels") {
            for case .open("Relationship", let a) in FlatXML.events(data) {
                if let id = a["Id"], var target = a["Target"] {
                    if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
                    rels[id] = target
                }
            }
        }
        if let data = zip.data("xl/workbook.xml") {
            for case .open("sheet", let a) in FlatXML.events(data) {
                let rid = a["r:id"] ?? a.first { $0.key.hasSuffix(":id") }?.value ?? ""
                if let path = rels[rid] { sheets.append((a["name"] ?? "Sheet", path)) }
            }
        }
        if sheets.isEmpty {
            sheets = zip.names.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted()
                .map { ((($0 as NSString).lastPathComponent as NSString).deletingPathExtension, $0) }
        }
        guard !sheets.isEmpty else { throw ImportError.unreadable("spreadsheet") }

        var rows: [ImportRow] = []
        for (index, sheet) in sheets.enumerated() {
            guard let data = zip.data(sheet.path) else { continue }
            if sheets.count > 1 {
                rows.append(ImportRow(cells: [ImportCell(text: sheet.name)], heading: true))
            }
            var cells: [Int: ImportCell] = [:]
            var column = 0
            var type = ""
            var style: Int?
            var value = ""
            var inValue = false
            for e in FlatXML.events(data) {
                switch e {
                case .open("row", _):
                    cells = [:]
                    column = -1
                case .open("c", let a):
                    type = a["t"] ?? ""
                    style = Int(a["s"] ?? "")
                    value = ""
                    column = a["r"].map(columnIndex) ?? column + 1
                case .open("v", _), .open("t", _):
                    inValue = true
                case .text(let t):
                    if inValue { value += t }
                case .close("v"), .close("t"):
                    inValue = false
                case .close("c"):
                    var text = value
                    if type == "s", let i = Int(value), i < shared.count { text = shared[i] }
                    if type == "b" { text = value == "1" ? "TRUE" : "FALSE" }
                    if type.isEmpty || type == "n", let d = Double(value), d == d.rounded(), abs(d) < 1e9 {
                        text = String(Int(d))
                    }
                    cells[column] = ImportCell(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                               color: color(style: style))
                case .close("row"):
                    if let last = cells.keys.max() {
                        let list = (0...last).map { cells[$0] ?? ImportCell(text: "") }
                        if list.contains(where: { !$0.text.isEmpty }) {
                            rows.append(ImportRow(cells: list, table: index))
                        }
                    }
                default:
                    break
                }
            }
        }
        return ImportedDocument(title: nil, rows: rows)
    }

    /// "C12" -> 2
    private static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(n - 1, 0)
    }
}

// MARK: - Word (.docx)

enum DOCXParser {
    static func parse(_ zip: ZipReader) throws -> ImportedDocument {
        guard let data = zip.data("word/document.xml") else { throw ImportError.unreadable("Word file") }
        var rows: [ImportRow] = []
        var tableDepth = 0
        var tableCount = 0
        var row: [ImportCell]? = nil
        var cellText: String? = nil
        var cellShade: String?
        var para = ""
        var paraHeading = false
        var paraShade: String?
        var firstBackground: String?
        var firstColor: String?
        var runShade: String?
        var runColor: String?
        var inRunProps = false
        var inParaProps = false
        var inCellProps = false
        var inText = false

        func shade(_ a: [String: String]) -> String? {
            let v = a["w:fill"] ?? a["fill"]
            guard let v, v.lowercased() != "auto" else { return nil }
            let c = ImportColor.normalize(v)
            return ImportColor.isBlankBackground(c) ? nil : c
        }

        for e in FlatXML.events(data) {
            switch e {
            case .open("w:tbl", _):
                tableDepth += 1
                if tableDepth == 1 { tableCount += 1 }
            case .close("w:tbl"):
                tableDepth = max(0, tableDepth - 1)
            case .open("w:tr", _) where tableDepth == 1:
                row = []
            case .close("w:tr") where tableDepth == 1:
                if let r = row, r.contains(where: { !$0.text.isEmpty }) {
                    rows.append(ImportRow(cells: r, table: tableCount))
                }
                row = nil
            case .open("w:tc", _) where tableDepth == 1:
                cellText = ""
                cellShade = nil
                firstBackground = nil
                firstColor = nil
            case .close("w:tc") where tableDepth == 1:
                let color = cellShade ?? firstBackground ?? firstColor
                row?.append(ImportCell(text: HTMLParser.clean(cellText ?? ""), color: color))
                cellText = nil
            case .open("w:tcPr", _): inCellProps = true
            case .close("w:tcPr"): inCellProps = false
            case .open("w:p", _):
                para = ""
                paraHeading = false
                paraShade = nil
                if cellText == nil { firstBackground = nil; firstColor = nil }
            case .open("w:pPr", _): inParaProps = true
            case .close("w:pPr"): inParaProps = false
            case .open("w:pStyle", let a):
                let v = (a["w:val"] ?? "").lowercased()
                if v.hasPrefix("heading") || v == "title" { paraHeading = true }
            case .open("w:r", _):
                runShade = nil
                runColor = nil
            case .open("w:rPr", _): inRunProps = true
            case .close("w:rPr"): inRunProps = false
            case .open("w:shd", let a):
                if inCellProps { cellShade = shade(a) } else if inRunProps { runShade = shade(a) } else if inParaProps { paraShade = shade(a) }
            case .open("w:highlight", let a) where inRunProps:
                runShade = ImportColor.normalize(a["w:val"]).flatMap { ImportColor.isBlankBackground($0) ? nil : $0 }
            case .open("w:color", let a) where inRunProps:
                let v = a["w:val"] ?? ""
                runColor = v.lowercased() == "auto" ? nil : ImportColor.normalize(v)
            case .open("w:t", _): inText = true
            case .close("w:t"): inText = false
            case .open("w:tab", _): para += " "
            case .open("w:br", _): para += "\n"
            case .text(let t) where inText:
                para += t
                if !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    if firstBackground == nil { firstBackground = runShade ?? paraShade }
                    if firstColor == nil, !ImportColor.isPlainText(runColor) { firstColor = runColor }
                }
            case .close("w:p"):
                if cellText != nil {
                    cellText! += para + "\n"
                } else if tableDepth == 0 {
                    let t = HTMLParser.clean(para)
                    if !t.isEmpty {
                        rows.append(ImportRow(cells: [ImportCell(text: t, color: firstBackground ?? firstColor)],
                                              heading: paraHeading))
                    }
                }
                para = ""
            default:
                break
            }
        }
        return ImportedDocument(title: nil, rows: rows)
    }
}
