import SwiftUI

/// The app's design language: quiet monochrome surfaces, a single accent,
/// rounded type, capsule buttons and continuous corners. Every screen pulls
/// from these tokens so the whole app — and every future mini game — reads
/// as one calm, considered surface.
enum Theme {
    static let corner: CGFloat = 20

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let subheadline = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let caption2 = Font.system(.caption2, design: .rounded)

    /// Barely-there fill for cells, chips and icon wells.
    static let quietFill = Color.primary.opacity(0.05)
    /// Hairline stroke for outlines.
    static let hairline = Color.primary.opacity(0.12)
}

/// The one loud element allowed on a screen: a saturated accent capsule.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.3), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Understated secondary action: quiet fill, hairline outline.
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
    /// Standard content card.
    func card() -> some View {
        padding(20)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            )
    }
}

enum PlayerStyle {
    /// Muted-but-distinct player palette, tuned to sit quietly on
    /// monochrome surfaces.
    static let palette: [Color] = [
        Color(red: 0.39, green: 0.37, blue: 0.87),  // indigo
        Color(red: 0.93, green: 0.42, blue: 0.40),  // coral
        Color(red: 0.16, green: 0.66, blue: 0.52),  // emerald
        Color(red: 0.93, green: 0.65, blue: 0.25),  // amber
        Color(red: 0.33, green: 0.63, blue: 0.92),  // sky
        Color(red: 0.72, green: 0.44, blue: 0.86),  // violet
        Color(red: 0.92, green: 0.47, blue: 0.66),  // rose
        Color(red: 0.47, green: 0.53, blue: 0.60),  // slate
    ]

    static func color(for slot: Int) -> Color {
        palette[(slot - 1 + palette.count * 8) % palette.count]
    }
}
