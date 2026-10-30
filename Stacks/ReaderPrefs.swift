import Foundation
import SwiftUI

/// Kavita's manga/comic reader modes.
enum ReadingMode: String, Codable, CaseIterable, Identifiable {
    case leftRight, upDown, webtoon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leftRight: return "Left to right"
        case .upDown: return "Up to down"
        case .webtoon: return "Webtoon"
        }
    }
    var systemImage: String {
        switch self {
        case .leftRight: return "arrow.left.and.right"
        case .upDown: return "arrow.up.and.down"
        case .webtoon: return "scroll"
        }
    }
}

enum ScalingMode: String, Codable, CaseIterable, Identifiable {
    case automatic, fitWidth, fitHeight, original
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .fitWidth: return "Fit to width"
        case .fitHeight: return "Fit to height"
        case .original: return "Original"
        }
    }
}

enum ReaderBackground: String, Codable, CaseIterable, Identifiable {
    case black, gray, white
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(hex: 0x2B2C2C)
        case .white: return .white
        }
    }
}

struct ComicPrefs: Codable, Equatable {
    var mode: ReadingMode = .leftRight
    var rightToLeft = false
    var scaling: ScalingMode = .automatic
    var background: ReaderBackground = .black
}

enum BookTheme: String, Codable, CaseIterable, Identifiable {
    case dark, black, white, paper
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var background: String {
        switch self {
        case .dark: return "#1f2020"
        case .black: return "#000000"
        case .white: return "#ffffff"
        case .paper: return "#f4ecd8"
        }
    }
    var text: String {
        switch self {
        case .dark: return "#e6e6e6"
        case .black: return "#d9d9d9"
        case .white: return "#1a1a1a"
        case .paper: return "#3b2f20"
        }
    }
    var isDark: Bool { self == .dark || self == .black }
}

enum BookFont: String, Codable, CaseIterable, Identifiable {
    case original, serif, sans
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Book default"
        case .serif: return "Serif"
        case .sans: return "Sans serif"
        }
    }
    var css: String? {
        switch self {
        case .original: return nil
        case .serif: return "Georgia, 'Times New Roman', serif"
        case .sans: return "-apple-system, 'Helvetica Neue', sans-serif"
        }
    }
}

struct BookPrefs: Codable, Equatable {
    var paged = true            // Kavita's "1 column" layout; false = continuous scroll
    var fontSize = 100          // percent
    var lineHeight = 1.5
    var margin = 22             // points on each side
    var theme: BookTheme = .dark
    var font: BookFont = .original
}

/// Global defaults plus per-series overrides, like Kavita's reading profiles.
enum ReaderPrefsStore {
    private static let defaultsKey = "comicPrefs.default"
    private static let seriesKey = "comicPrefs.series"
    private static let bookKey = "bookPrefs"

    static var defaultComic: ComicPrefs {
        get { decode(UserDefaults.standard.data(forKey: defaultsKey)) ?? ComicPrefs() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: defaultsKey) }
    }

    static func comic(seriesId: Int, libraryType: Int? = nil) -> ComicPrefs {
        let all: [String: ComicPrefs] = decode(UserDefaults.standard.data(forKey: seriesKey)) ?? [:]
        if let saved = all[String(seriesId)] { return saved }
        return defaultComic
    }

    static func setComic(_ prefs: ComicPrefs, seriesId: Int) {
        var all: [String: ComicPrefs] = decode(UserDefaults.standard.data(forKey: seriesKey)) ?? [:]
        all[String(seriesId)] = prefs
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: seriesKey)
    }

    static func clearSeriesOverrides() {
        UserDefaults.standard.removeObject(forKey: seriesKey)
    }

    static var book: BookPrefs {
        get { decode(UserDefaults.standard.data(forKey: bookKey)) ?? BookPrefs() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: bookKey) }
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
