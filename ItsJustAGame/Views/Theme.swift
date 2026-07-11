import SwiftUI

/// The app's design language: a dark, near-black canvas with white text,
/// cyan as the primary accent and magenta as its counterpoint. Rounded
/// type, capsule buttons with a soft neon glow, continuous corners. Every
/// screen — and every future mini game — pulls from these tokens so the
/// whole app reads as one calm, considered surface.
enum Theme {
    static let corner: CGFloat = 20

    // Palette
    static let background = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.16)
    /// Text color on top of neon fills (buttons, highlights).
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let cyan = Color(red: 0.20, green: 0.85, blue: 1.00)
    static let magenta = Color(red: 1.00, green: 0.30, blue: 0.80)

    // Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let subheadline = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let caption2 = Font.system(.caption2, design: .rounded)

    /// Barely-there fill for cells, chips and icon wells.
    static let quietFill = Color.white.opacity(0.06)
    /// Hairline stroke for outlines.
    static let hairline = Color.white.opacity(0.14)
}

/// The loud element on a screen: a neon capsule with a soft glow.
/// Defaults to cyan; pass a tint for the magenta counterpart.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.cyan
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(tint.opacity(isEnabled ? 1 : 0.3), in: Capsule())
            .shadow(color: tint.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Understated secondary action: quiet fill, hairline outline, white text.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Theme.quietFill, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension View {
    /// Standard content card on the dark canvas.
    func card() -> some View {
        padding(20)
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

enum PlayerStyle {
    /// Neon-leaning player palette, led by the brand cyan and magenta.
    static let palette: [Color] = [
        Theme.cyan,
        Theme.magenta,
        Color(red: 0.55, green: 0.93, blue: 0.35),  // lime
        Color(red: 1.00, green: 0.75, blue: 0.25),  // amber
        Color(red: 0.65, green: 0.55, blue: 1.00),  // violet
        Color(red: 1.00, green: 0.52, blue: 0.35),  // coral
        Color(red: 0.35, green: 0.93, blue: 0.72),  // mint
        Color(red: 0.48, green: 0.64, blue: 1.00),  // azure
    ]

    static func color(index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// Fallback when no dealt color is known (e.g. before the config has
    /// been fetched): slot order.
    static func color(for slot: Int) -> Color {
        color(index: slot - 1)
    }
}

extension PlayerInfo {
    var color: Color {
        PlayerStyle.color(index: colorIndex ?? (slot - 1))
    }
}
