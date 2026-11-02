import Foundation

/// The logo's shape: eight uneven bars, the tallest carrying the AI sparkle. The app icon is drawn from the same numbers.
nonisolated enum LogoGeometry {
    static let levels: [Double] = [0.34, 0.62, 0.46, 1.00, 0.58, 0.80, 0.40, 0.54]
    static let peak = 3
    /// As fractions of the tallest bar's height.
    static let barWidth = 0.11
    static let gap = 0.065
    static let sparkleRadius = 0.24
    static let sparkleLift = 0.20
    static let starRadius = 0.085
}

/// What is on screen at one instant of the launch animation.
nonisolated struct LaunchFrame: Equatable {
    var levels: [Double]
    /// 0...1: how bright the bars' glow is.
    var glow: Double
    var sparkleScale: Double
    var sparkleDegrees: Double
    var starScale: Double
    var logoScale: Double
    var logoOpacity: Double
    /// 0...1: how far the circle that reveals the app has grown (1 covers the whole screen).
    var reveal: Double
    /// 0...1: the soft flash of light behind the logo as it opens.
    var bloom: Double
}

/// The launch animation as a pure function of time: bars that bounce like live audio, damp and freeze onto the logo, a sparkle
/// that springs in, then a ring of light that opens onto the app.
nonisolated enum LaunchChoreography {
    static let liveEnd = 1.0
    static let settleEnd = 1.5
    static let sparkleStart = 1.25
    static let sparkleEnd = 1.7
    static let openStart = 1.7
    static let total = 2.4
    /// With Reduce Motion the finished logo is shown briefly, then fades.
    static let reducedTotal = 0.6

    private static let frequencies: [Double] = [5.6, 7.3, 6.2, 8.6, 5.1, 7.8, 6.7, 9.1]
    private static let phases: [Double] = [0.0, 1.9, 3.6, 0.8, 2.7, 4.4, 1.3, 5.2]

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    private static func easeInOutCubic(_ x: Double) -> Double { let p = clamp(x); return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    private static func easeOutBack(_ x: Double) -> Double {
        let p = clamp(x), c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }

    /// One bar moving on its own: up and down, never quite in step with its neighbours.
    static func liveLevel(_ i: Int, at t: Double) -> Double {
        let envelope = easeOutCubic(t / 0.25)
        let wave = 0.2 + 0.8 * pow(abs(sin(frequencies[i] * t + phases[i])), 0.75)
        return 0.08 + (wave - 0.08) * envelope
    }

    static func frame(at t: Double) -> LaunchFrame {
        let target = LogoGeometry.levels
        let settle = easeOutCubic((t - liveEnd) / (settleEnd - liveEnd))
        let levels = target.indices.map { i -> Double in
            if t >= settleEnd { return target[i] }
            let live = liveLevel(i, at: t)
            return t <= liveEnd ? live : target[i] + (live - target[i]) * (1 - settle)
        }
        let sparkleP = (t - sparkleStart) / (sparkleEnd - sparkleStart)
        let twinkle = 1 + 0.12 * sin(.pi * clamp((t - 1.55) / 0.3))
        let sparkleScale = t < sparkleStart ? 0 : easeOutBack(sparkleP) * twinkle
        let open = clamp((t - openStart) / (total - openStart))
        let moving = (levels.max() ?? 0)
        return LaunchFrame(
            levels: levels,
            glow: 0.45 + 0.4 * moving + 0.15 * clamp(sparkleScale),
            sparkleScale: sparkleScale,
            sparkleDegrees: -45 * (1 - easeOutCubic(sparkleP)),
            starScale: t < 1.45 ? 0 : easeOutBack((t - 1.45) / 0.3),
            logoScale: 1 + 0.3 * easeInOutCubic(open),
            logoOpacity: 1 - clamp((open - 0.1) / 0.6),
            reveal: easeInOutCubic(open),
            bloom: sin(.pi * clamp(open * 1.4)))
    }

    /// The finished logo, for Reduce Motion: nothing bounces and nothing expands.
    static func reducedFrame(at t: Double) -> LaunchFrame {
        LaunchFrame(levels: LogoGeometry.levels, glow: 0.65, sparkleScale: 1, sparkleDegrees: 0, starScale: 1, logoScale: 1,
                    logoOpacity: 1 - clamp((t - 0.3) / 0.3), reveal: 0, bloom: 0)
    }

    /// A gentle idle motion for the logo on the welcome screen: the bars breathe a little, the sparkle twinkles.
    static func idle(at t: Double) -> LaunchFrame {
        let levels = LogoGeometry.levels.indices.map { i in
            min(1, max(0.12, LogoGeometry.levels[i] + 0.07 * sin(1.7 * t + phases[i])))
        }
        return LaunchFrame(levels: levels, glow: 0.65, sparkleScale: 1 + 0.07 * sin(2.2 * t), sparkleDegrees: 6 * sin(1.1 * t),
                           starScale: 1 + 0.12 * sin(2.9 * t + 1), logoScale: 1, logoOpacity: 1, reveal: 0, bloom: 0)
    }
}
