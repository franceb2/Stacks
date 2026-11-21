import Foundation

/// A reading order: bundled with the app (like Spawn's) or added by you from a link, file or pasted text.
/// It's matched against your Kavita library and shown as a tab on the series page; no Kavita reading list
/// is created, and your files aren't changed.
struct ReadingOrder: Codable, Identifiable {
    struct Entry: Codable {
        let series: String
        let label: String
        let kind: String        // main, spinoff, oneshot
        let section: String     // main, universe, or a heading from an imported doc
        let number: String?
        var year: Int? = nil    // "Daredevil (1964)"
        var volume: Int? = nil  // "Daredevil Vol. 2"
    }

    /// Where an added order came from, so it can be refreshed with the same choices.
    struct Source: Codable {
        var link: String?
        var fileName: String?
        /// Colors kept ("none" for uncolored), and section names kept.
        var colors: [String]
        var sections: [String]
        var added: Date
    }

    let id: String
    var title: String
    var credit: String
    var note: String?
    var hosts: [String]
    var entries: [Entry]
    var years: [String: Int]?
    var source: Source?

    var isUserAdded: Bool { source != nil }

    /// Which year's run an entry means, when the library has several series with the same name.
    func yearHint(_ e: Entry) -> Int? {
        e.year ?? years?["\(e.series)|\(e.section)"] ?? years?[e.series]
    }
}
