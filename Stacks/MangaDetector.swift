import Foundation

/// Decides per series whether it's manga (right to left, "chapters") or a comic (left to right, "issues").
///
/// Kavita's library type alone isn't reliable: a new library starts as type Manga, so a comics library
/// left that way made every new comic open right to left. This also looks at the series' folder, the
/// library's name, and its Kavita details (publisher, language, genres). Comic and Book library types
/// are trusted as they are. Your own per-series reader settings always win over this.
@MainActor
enum MangaDetector {
    private static let storeKey = "mangaDetection.v1"

    private static var saved: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Bool] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storeKey) }
    }

    /// The last answer for a series, if it has been worked out (works offline).
    static func cached(_ seriesId: Int) -> Bool? { saved[String(seriesId)] }

    /// Manga or not, fetching what's needed from Kavita the first time.
    static func isManga(seriesId: Int, libraryType: Int?, client: KavitaClient) async -> Bool {
        if let type = libraryType, type != 0 { return false }   // Kavita says comic or book
        if let hit = cached(seriesId) { return hit }
        async let s = try? client.series(id: seriesId)
        async let m = try? client.metadata(seriesId: seriesId)
        let series = await s
        let metadata = await m
        guard series != nil || metadata != nil else { return libraryType == 0 }   // offline: no new clues
        return remember(seriesId, guess(libraryType: libraryType, series: series, metadata: metadata))
    }

    /// Records an answer worked out elsewhere (the series page already has the details).
    @discardableResult
    static func remember(_ seriesId: Int, _ manga: Bool) -> Bool {
        var all = saved
        all[String(seriesId)] = manga
        saved = all
        return manga
    }

    private static let mangaPublishers = ["viz", "shueisha", "kodansha", "shogakukan", "yen press", "seven seas",
                                          "square enix", "tokyopop", "dark horse manga", "vertical", "kadokawa",
                                          "hakusensha", "akita shoten", "j-novel", "denpa", "one peace",
                                          "udon", "ize press", "tappytoon", "webtoon", "naver", "kakao"]
    private static let comicPublishers = ["marvel", "dc comics", "image", "dark horse comics", "idw", "boom",
                                          "dynamite", "valiant", "vertigo", "oni press", "aftershock",
                                          "titan", "archie", "skybound", "wildstorm", "top cow", "mad cave",
                                          "awa", "ahoy", "black mask", "zenescope", "avatar"]
    private static let mangaWords = ["manga", "manhwa", "manhua", "shonen", "shounen", "seinen", "shojo",
                                     "shoujo", "josei", "isekai", "webtoon"]

    /// Adds up clues. Positive means manga.
    static func guess(libraryType: Int?, series: Series?, metadata: SeriesMetadata?) -> Bool {
        if let type = libraryType, type != 0 { return false }
        var score = 0

        func has(_ text: String, _ words: [String]) -> Bool { words.contains { text.contains($0) } }

        // The folder on your PC, like D:\Comics\Saga or D:\Manga\One Piece.
        let path = (series?.folderPath ?? "").lowercased()
        if has(path, ["manga", "manhwa", "manhua", "webtoon"]) { score += 4 }
        if has(path, ["comic"]) { score -= 4 }

        // The library's name in Kavita.
        let library = (series?.libraryName ?? "").lowercased()
        if has(library, ["manga", "manhwa", "manhua", "webtoon"]) { score += 3 }
        if has(library, ["comic"]) { score -= 3 }

        if let metadata {
            let publishers = (metadata.publishers ?? []).map { $0.name.lowercased() }
            if publishers.contains(where: { p in mangaPublishers.contains { p.contains($0) } }) { score += 3 }
            if publishers.contains(where: { p in comicPublishers.contains { p.contains($0) } }) { score -= 3 }

            let labels = ((metadata.genres ?? []) + (metadata.tags ?? [])).map { $0.title.lowercased() }
            if labels.contains(where: { l in mangaWords.contains { l.contains($0) } }) { score += 2 }
            if labels.contains(where: { $0.contains("superhero") || $0.contains("comic") }) { score -= 1 }

            let language = (metadata.language ?? "").lowercased()
            if ["ja", "ko", "zh"].contains(where: { language.hasPrefix($0) }) { score += 2 }
        }

        // No clues either way: go with Kavita's library type.
        if score == 0 { return libraryType == 0 }
        return score > 0
    }
}
