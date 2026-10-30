import SwiftUI

/// Colors taken from Kavita's default dark theme so the app feels like Kavita.
enum Theme {
    static let primary = Color(hex: 0x4AC694)        // --primary-color
    static let primaryDark = Color(hex: 0x3B9E76)    // --primary-color-dark-shade
    static let background = Color(hex: 0x1F2020)     // --bs-body-bg
    static let navBar = Color(hex: 0x121212)
    static let card = Color(hex: 0x2B2C2C)           // elevation layer over the body
    static let cardHigh = Color(hex: 0x333434)
    static let text = Color(hex: 0xEFEFEF)           // --body-text-color
    static let muted = Color.white.opacity(0.55)     // --text-muted-color (slightly lifted for small text)
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
            .foregroundStyle(.black)
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
