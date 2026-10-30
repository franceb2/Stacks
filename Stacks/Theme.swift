import SwiftUI

/// App color themes. Kavita green is the default; the rest are dark backgrounds with a colored trim.
enum AppTheme: String, CaseIterable, Identifiable {
    case kavita, crimson, cobalt, rose, violet, tangerine, teal, midnight, oled, gold

    var id: String { rawValue }

    var name: String {
        switch self {
        case .kavita: return "Kavita"
        case .crimson: return "Crimson"
        case .cobalt: return "Cobalt"
        case .rose: return "Rose"
        case .violet: return "Violet"
        case .tangerine: return "Tangerine"
        case .teal: return "Teal"
        case .midnight: return "Midnight"
        case .oled: return "OLED Black"
        case .gold: return "Gold"
        }
    }

    /// Trim color.
    var accent: UInt32 {
        switch self {
        case .kavita: return 0x4AC694
        case .crimson: return 0xE0303C
        case .cobalt: return 0x3B82F6
        case .rose: return 0xF0509A
        case .violet: return 0xA35BF5
        case .tangerine: return 0xF57C1F
        case .teal: return 0x14B8A6
        case .midnight: return 0x5B9BF0
        case .oled: return 0x4AC694
        case .gold: return 0xE3AA3B
        }
    }

    var background: UInt32 {
        switch self {
        case .kavita: return 0x1F2020
        case .crimson, .cobalt, .rose, .violet, .tangerine, .teal: return 0x0E0D0E
        case .midnight: return 0x0B1322
        case .oled: return 0x000000
        case .gold: return 0x1A1918
        }
    }

    var card: UInt32 {
        switch self {
        case .kavita: return 0x2B2C2C
        case .crimson, .cobalt, .rose, .violet, .tangerine, .teal: return 0x1C1B1D
        case .midnight: return 0x16233A
        case .oled: return 0x121212
        case .gold: return 0x282624
        }
    }

    var bar: UInt32 {
        switch self {
        case .midnight: return 0x070D18
        case .oled: return 0x000000
        default: return 0x0A0A0A
        }
    }

    /// Text color on top of the accent (dark on bright trims, white on deep ones).
    var onAccentIsDark: Bool {
        switch self {
        case .kavita, .teal, .gold, .oled, .tangerine: return true
        default: return false
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
