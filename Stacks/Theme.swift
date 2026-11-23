import SwiftUI

/// App color themes. Kavita green is the default; each theme tints the background, cards and bars,
/// not just the trim color. Raw values stay the same when a theme is restyled, so your choice carries over.
enum AppTheme: String, CaseIterable, Identifiable {
    case kavita, rose, violet, crimson, cobalt, tangerine, teal, midnight, oled, gold, synthwave, ocean, ember, forest, mocha, arctic, sakura, matrix, hellsKitchen, dracula, nord, retro, tokyoNight, cyberpunk, royal, mono

    var id: String { rawValue }

    var name: String {
        switch self {
        case .kavita: return "Kavita"
        case .rose: return "Rose"
        case .violet: return "Violet"
        case .crimson: return "Crimson Night"
        case .cobalt: return "Deep Sea"
        case .tangerine: return "Sunset"
        case .teal: return "Jade"
        case .midnight: return "Nebula"
        case .oled: return "OLED Black"
        case .gold: return "Noir Gold"
        case .synthwave: return "Synthwave"
        case .ocean: return "Ocean"
        case .ember: return "Ember"
        case .forest: return "Forest"
        case .mocha: return "Mocha"
        case .arctic: return "Arctic"
        case .sakura: return "Sakura"
        case .matrix: return "Matrix"
        case .hellsKitchen: return "Hell's Kitchen"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .retro: return "Retro"
        case .tokyoNight: return "Tokyo Night"
        case .cyberpunk: return "Cyberpunk"
        case .royal: return "Royal"
        case .mono: return "Mono"
        }
    }

    /// Trim color.
    var accent: UInt32 {
        switch self {
        case .kavita: return 0x4AC694
        case .rose: return 0xF0509A
        case .violet: return 0xA35BF5
        case .crimson: return 0xE63946
        case .cobalt: return 0x3D8BFF
        case .tangerine: return 0xFF8A3D
        case .teal: return 0x2FD6A4
        case .midnight: return 0xB794F6
        case .oled: return 0xE5E5E5
        case .gold: return 0xE3AA3B
        case .synthwave: return 0xFF4FD8
        case .ocean: return 0x4FD1E8
        case .ember: return 0xFF6A3D
        case .forest: return 0xA3D977
        case .mocha: return 0xD9A774
        case .arctic: return 0xBFE3FF
        case .sakura: return 0xF7A8C4
        case .matrix: return 0x00FF66
        case .hellsKitchen: return 0xFF3B30
        case .dracula: return 0xBD93F9
        case .nord: return 0x88C0D0
        case .retro: return 0xFABD2F
        case .tokyoNight: return 0x7AA2F7
        case .cyberpunk: return 0xFCEE0A
        case .royal: return 0xF5C542
        case .mono: return 0xF2F2F2
        }
    }

    var background: UInt32 {
        switch self {
        case .kavita: return 0x1F2020
        case .rose: return 0x0E0D0E
        case .violet: return 0x0E0D0E
        case .crimson: return 0x14090B
        case .cobalt: return 0x07101F
        case .tangerine: return 0x1F0F1A
        case .teal: return 0x0A1714
        case .midnight: return 0x110E24
        case .oled: return 0x000000
        case .gold: return 0x0B0A08
        case .synthwave: return 0x170A2B
        case .ocean: return 0x061C26
        case .ember: return 0x1A0D08
        case .forest: return 0x0D1810
        case .mocha: return 0x1B1411
        case .arctic: return 0x111827
        case .sakura: return 0x1D1317
        case .matrix: return 0x000A04
        case .hellsKitchen: return 0x1A0607
        case .dracula: return 0x282A36
        case .nord: return 0x2E3440
        case .retro: return 0x282828
        case .tokyoNight: return 0x1A1B26
        case .cyberpunk: return 0x0D0221
        case .royal: return 0x1A1446
        case .mono: return 0x1C1C1E
        }
    }

    var card: UInt32 {
        switch self {
        case .kavita: return 0x2B2C2C
        case .rose: return 0x1C1B1D
        case .violet: return 0x1C1B1D
        case .crimson: return 0x26121A
        case .cobalt: return 0x0F1E36
        case .tangerine: return 0x321A2B
        case .teal: return 0x13261F
        case .midnight: return 0x1E1A3A
        case .oled: return 0x121212
        case .gold: return 0x1A1712
        case .synthwave: return 0x271543
        case .ocean: return 0x0D2E3B
        case .ember: return 0x2B1810
        case .forest: return 0x17271B
        case .mocha: return 0x2A201B
        case .arctic: return 0x1F2937
        case .sakura: return 0x2D1F25
        case .matrix: return 0x07170D
        case .hellsKitchen: return 0x2B0D0E
        case .dracula: return 0x343746
        case .nord: return 0x3B4252
        case .retro: return 0x3C3836
        case .tokyoNight: return 0x24283B
        case .cyberpunk: return 0x1B0B3B
        case .royal: return 0x282060
        case .mono: return 0x2C2C2E
        }
    }

    var bar: UInt32 {
        switch self {
        case .kavita: return 0x0A0A0A
        case .rose: return 0x0A0A0A
        case .violet: return 0x0A0A0A
        case .crimson: return 0x0D0507
        case .cobalt: return 0x040A14
        case .tangerine: return 0x150A12
        case .teal: return 0x06100D
        case .midnight: return 0x0A0818
        case .oled: return 0x000000
        case .gold: return 0x060504
        case .synthwave: return 0x10061F
        case .ocean: return 0x03141B
        case .ember: return 0x120804
        case .forest: return 0x08110A
        case .mocha: return 0x130E0B
        case .arctic: return 0x0B111C
        case .sakura: return 0x150D10
        case .matrix: return 0x000502
        case .hellsKitchen: return 0x120304
        case .dracula: return 0x1E1F29
        case .nord: return 0x242933
        case .retro: return 0x1D2021
        case .tokyoNight: return 0x16161E
        case .cyberpunk: return 0x07011A
        case .royal: return 0x110D31
        case .mono: return 0x141416
        }
    }

    /// Text color on top of the accent (dark on bright trims, white on deep ones).
    var onAccentIsDark: Bool {
        switch self {
        case .kavita: return true
        case .rose: return false
        case .violet: return false
        case .crimson: return false
        case .cobalt: return false
        case .tangerine: return true
        case .teal: return true
        case .midnight: return true
        case .oled: return true
        case .gold: return true
        case .synthwave: return true
        case .ocean: return true
        case .ember: return true
        case .forest: return true
        case .mocha: return true
        case .arctic: return true
        case .sakura: return true
        case .matrix: return true
        case .hellsKitchen: return false
        case .dracula: return true
        case .nord: return true
        case .retro: return true
        case .tokyoNight: return true
        case .cyberpunk: return true
        case .royal: return true
        case .mono: return true
        }
    }

    /// "#rrggbb" for web views.
    var accentCSS: String { String(format: "#%06X", accent) }

    private static let key = "appTheme"
    nonisolated(unsafe) static var current: AppTheme =
        AppTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .kavita

    /// Switches theme. Bars are restyled first so the rebuilt screens pick up the new colors.
    @MainActor
    static func select(_ theme: AppTheme) {
        current = theme
        StacksApp.applyBarAppearance()
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}

/// Colors for the current theme (Kavita's dark theme by default).
enum Theme {
    static var primary: Color { Color(hex: AppTheme.current.accent) }
    static var onPrimary: Color { AppTheme.current.onAccentIsDark ? .black : .white }
    static var background: Color { Color(hex: AppTheme.current.background) }
    static var navBar: Color { Color(hex: AppTheme.current.bar) }
    static var card: Color { Color(hex: AppTheme.current.card) }
    static let text = Color(hex: 0xEFEFEF)
    static let muted = Color.white.opacity(0.55)
    static let danger = Color(hex: 0xE24B4A)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Dark Kavita background behind lists and scroll views.
    func kavitaBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// Kavita's section heading: bold title with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
    }
}

/// Green filled button like Kavita's primary buttons.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Outlined button like Kavita's secondary buttons.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12)))
    }
}

// MARK: - Cinematic touches

/// Cards shrink slightly and spring back when pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// A big blurred copy of the cover that fades into the page, used behind headers.
struct Backdrop: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            CachedImage(url: url) { Color.clear }
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 30, opaque: true)
                .saturation(1.2)
                .opacity(0.65)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(
                LinearGradient(colors: [Theme.background.opacity(0.15), Theme.background.opacity(0.7), Theme.background],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Zoom transitions (iOS 18 and later; older iOS uses the normal slide)

private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.heroNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.matchedTransitionSource(id: id, in: namespace)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let id: String
    @Environment(\.heroNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    /// The card a zoom transition starts from.
    func zoomSource(_ id: String) -> some View { modifier(ZoomSourceModifier(id: id)) }
    /// The page a zoom transition opens into.
    func zoomDestination(_ id: String) -> some View { modifier(ZoomDestinationModifier(id: id)) }
}
