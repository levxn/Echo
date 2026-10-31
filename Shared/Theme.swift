import SwiftUI

/// Echo design tokens: near-black base, aurora accents, semantic Local/Cloud colors.
/// Dark only; text pairs are chosen to stay above 4.5:1 on the base surface.
enum Palette {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.078)   // #070914, not pure black
    static let surface = Color(red: 0.055, green: 0.067, blue: 0.125)

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

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [teal, blue], startPoint: .leading, endPoint: .trailing)
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Slowly drifting mesh gradient over the base color. Static when Reduce Motion is on.
struct AuroraBackground: View {
    var calm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let deep = Color(red: 0.027, green: 0.035, blue: 0.078)
    private static let indigo = Color(red: 0.09, green: 0.11, blue: 0.27)
    private static let tealDark = Color(red: 0.04, green: 0.24, blue: 0.27)
    private static let violetDark = Color(red: 0.22, green: 0.12, blue: 0.46)
    private static let blueDark = Color(red: 0.07, green: 0.16, blue: 0.42)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
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
    func echoCard(radius: CGFloat = 24, padding: CGFloat = Spacing.lg) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// Subtle press feedback (scale 0.97) that never shifts layout.
struct EchoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
    }
}

enum Format {
    /// 427 -> "7:07"
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
