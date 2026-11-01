import SwiftUI

/// Echo design tokens: near-black base, aurora accents, semantic Local/Cloud colors.
/// Dark only; text pairs are chosen to stay above 4.5:1 on the base surface.
enum Palette {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.078)   // #070914, not pure black

    static let teal = Color(red: 0.18, green: 0.83, blue: 0.75)            // Local / on-device / healthy
    static let blue = Color(red: 0.36, green: 0.55, blue: 1.00)
    static let violet = Color(red: 0.62, green: 0.45, blue: 0.98)          // Cloud (Muse API)
    static let rose = Color(red: 0.98, green: 0.45, blue: 0.55)            // dropped / rejected
    static let amber = Color(red: 0.98, green: 0.74, blue: 0.30)

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.46)                    // large/decorative only

    static let local = teal
    static let cloud = violet

    /// Rows and wells that sit on a glass card. One value each, so rows look the same everywhere.
    static let fill = Color.white.opacity(0.05)
    static let fillStrong = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.10)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [teal, blue], startPoint: .leading, endPoint: .trailing)
    }
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    /// Between a title and its caption, and inside tight clusters.
    static let tight: CGFloat = 6
    static let sm: CGFloat = 8
    /// Chip padding.
    static let snug: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii. A row on a card is always `row`; a card is `card`.
enum Radius {
    static let card: CGFloat = 24
    static let row: CGFloat = 16
    static let tile: CGFloat = 12
}

/// The type scale. Rounded design throughout; every size is a text style, so it follows Dynamic Type.
extension Font {
    static let echoScreenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let echoSheetTitle = Font.system(.title, design: .rounded, weight: .bold)
    static let echoSection = Font.system(.headline, design: .rounded, weight: .semibold)
    static let echoBody = Font.system(.body, design: .rounded, weight: .medium)
    static let echoLabel = Font.system(.footnote, design: .rounded, weight: .semibold)
    static let echoMeta = Font.caption
    static let echoMicro = Font.caption2
}

/// Slowly drifting mesh gradient over the base color. Static when Reduce Motion is on.
struct AuroraBackground: View {
    var calm = false
    /// Frames per second while animating. The watch runs it slower to save battery.
    var fps = 24.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let deep = Color(red: 0.027, green: 0.035, blue: 0.078)
    private static let indigo = Color(red: 0.09, green: 0.11, blue: 0.27)
    private static let tealDark = Color(red: 0.04, green: 0.24, blue: 0.27)
    private static let violetDark = Color(red: 0.22, green: 0.12, blue: 0.46)
    private static let blueDark = Color(red: 0.07, green: 0.16, blue: 0.42)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / (calm ? 14 : 9)
            MeshGradient(width: 3, height: 3, points: points(t), colors: [
                Self.deep, Self.indigo, Self.deep,
                Self.tealDark, Self.violetDark, Self.blueDark,
                Self.deep, Self.tealDark, Self.deep,
            ])
            .opacity(0.9)
        }
        .background(Palette.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ speed: Double, _ phase: Double, _ amount: Double = 0.09) -> Float {
            Float(sin(t * speed + phase) * amount)
        }
        return [
            [0, 0], [0.5 + w(1.0, 0), 0], [1, 0],
            [0, 0.5 + w(0.8, 1.2)], [0.5 + w(0.7, 2.1), 0.5 + w(0.9, 0.4)], [1, 0.5 + w(1.1, 3.0)],
            [0, 1], [0.5 + w(0.6, 4.2), 1], [1, 1],
        ]
    }
}

extension View {
    /// Frosted Liquid Glass card.
    func echoCard(radius: CGFloat = Radius.card, padding: CGFloat = Spacing.lg) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// Subtle press feedback (scale 0.97) that never shifts layout. With Reduce Motion on, only the opacity changes.
struct EchoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressLabel(configuration: configuration)
    }

    private struct PressLabel: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
        }
    }
}

enum ByteFormat {
    static func short(_ n: Int) -> String { n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024) }
}

enum Format {
    /// 427 -> "7:07"
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
