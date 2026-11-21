import Foundation

/// Matches titles loosely: case, punctuation, "&"/"and", "The", word order and years don't matter.
enum TitleKey {
    static func make(_ name: String) -> String {
        var s = name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s", with: "s")
        s = s.replacingOccurrences(of: #"\((19|20)\d\d\)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bvol(ume)?\.?\s*\d+\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        let words = s.split(separator: " ").map(String.init).filter { $0 != "the" && !$0.isEmpty }
        return words.sorted().joined(separator: " ")
    }

    static func year(in name: String) -> Int? {
        guard let r = name.range(of: #"\((19|20)\d\d\)"#, options: .regularExpression) else { return nil }
        return Int(name[r].dropFirst().dropLast())
    }

    /// "001", "1", "1.0" all become 1.
    static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }
}
