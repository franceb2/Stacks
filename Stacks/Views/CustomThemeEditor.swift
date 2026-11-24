import SwiftUI
import UIKit

/// Make your own theme: pick any accent on the color wheel (or a preset), and a background hue.
struct CustomThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accent = Color(hex: CustomTheme.accent)
    @State private var background = Color(hex: CustomTheme.background)

    private var accentHex: UInt32 { Self.hex(of: accent) }
    private var backgroundHex: UInt32 { CustomTheme.darkened(Self.hex(of: background)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    ColorPicker("Any color", selection: $accent, supportsOpacity: false)
                    swatches(CustomTheme.accentPresets, pick: { accent = Color(hex: $0) }, isSelected: { $0 == accentHex })
                } header: {
                    Text("Accent")
                } footer: {
                    Text("Buttons, progress bars, tabs and highlights.")
                }
                .listRowBackground(Color(hex: CustomTheme.blend(backgroundHex, 0xFFFFFF, 0.08)))

                Section {
                    swatches(CustomTheme.backgroundPresets.map(\.hex), pick: { background = Color(hex: $0) },
                             isSelected: { $0 == backgroundHex })
                    ColorPicker("Any color", selection: $background, supportsOpacity: false)
                } header: {
                    Text("Background")
                } footer: {
                    Text("Bright colors are darkened automatically so text stays readable.")
                }
                .listRowBackground(Color(hex: CustomTheme.blend(backgroundHex, 0xFFFFFF, 0.08)))
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: backgroundHex).ignoresSafeArea())
            .navigationTitle("Custom theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use theme") {
                        CustomTheme.save(accent: accentHex, background: backgroundHex)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(Color(hex: accentHex))
        }
        .preferredColorScheme(.dark)
    }

    /// A small mock of the app in the chosen colors.
    private var preview: some View {
        let bg = backgroundHex
        let card = CustomTheme.blend(bg, 0xFFFFFF, 0.08)
        let bar = CustomTheme.blend(bg, 0x000000, 0.4)
        let onAccent: Color = CustomTheme.luminance(accentHex) > 0.55 ? .black : .white
        return VStack(spacing: 0) {
            HStack {
                Text("Home").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: accentHex))
            }
            .padding(12)
            .background(Color(hex: bar))

            HStack(alignment: .bottom, spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(hex: accentHex).opacity(0.85), Color(hex: card)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE READING").font(.caption2.weight(.bold)).kerning(1)
                        .foregroundStyle(Color(hex: accentHex))
                    Text("Spawn #1").font(.subheadline.bold()).foregroundStyle(Theme.text)
                    ProgressView(value: 0.4).tint(Color(hex: accentHex))
                    Text("Continue")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color(hex: accentHex), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .background(Color(hex: card), in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
        .background(Color(hex: bg))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
    }

    private func swatches(_ colors: [UInt32], pick: @escaping (UInt32) -> Void,
                          isSelected: @escaping (UInt32) -> Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 10)], spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                Button { pick(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(isSelected(hex) ? Color.white : Color.white.opacity(0.2),
                                                 lineWidth: isSelected(hex) ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    static func hex(of color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return CustomTheme.hex(Double(r), Double(g), Double(b))
    }
}
