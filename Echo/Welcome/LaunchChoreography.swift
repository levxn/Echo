import Foundation

/// The logo's shape: eight uneven bars, centred, inside a shiny ring tilted 45 degrees. Its back half passes behind the bars and its
/// front half in front. The app icon is drawn from the same numbers. Lengths are fractions of the tallest bar's height.
nonisolated enum LogoGeometry {
    static let levels: [Double] = [0.34, 0.62, 0.46, 1.00, 0.58, 0.80, 0.40, 0.54]
    static let peak = 3
    static let barWidth = 0.11
    static let gap = 0.065
    /// Half the width of the row of bars.
    static var rowHalf: Double { (Double(levels.count) * barWidth + Double(levels.count - 1) * gap) / 2 }
    /// The ring's long and short half-axes, its stroke, and its tilt (counter-clockwise on screen).
    static let ringA = 1.05
    static let ringB = 0.50
    static let ringWidth = 0.05
    static let ringDegrees = -45.0
    /// The shortest a bar can be: a dot in a line.
    static let floor = 0.07
}

/// What is on screen at one instant of the launch animation.
nonisolated struct LaunchFrame: Equatable {
    var levels: [Double]
    /// The line that becomes the ring: half its width, how open it is (0 is a flat line, 1 the full ring), its tilt and its opacity.
    var ringHalfWidth: Double
    var ringOpen: Double
    var ringDegrees: Double
    var ringOpacity: Double
    /// 0...1, repeating: where the bright glint is on the ring.
    var shine: Double
    /// 0...1: how bright the glow is.
    var glow: Double
    var logoScale: Double
    var logoOpacity: Double
    /// 0...1: how far the circle that reveals the app has grown (1 covers the whole screen).
    var reveal: Double
    /// 0...1: the soft flash of light behind the logo as it opens.
    var bloom: Double
}

/// The launch animation as a pure function of time. A line draws out and splits into bars that move like live audio; the bars fall
/// back into a line; the line opens into a tilted ring while the bars rise again inside it; a glint travels round the ring; then
/// a ring of light opens onto the app.
nonisolated enum LaunchChoreography {
    static let lineEnd = 0.4            // the line has drawn out
    static let emergeStart = 0.4        // the bars start to grow out of it
    static let liveStart = 1.1          // they are fully alive
    static let collapseStart = 2.0      // and now they fall back into a line
    static let collapseEnd = 2.7
    static let ringStart = 2.7          // the line opens into the ring
    static let ringEnd = 3.5
    static let riseStart = 2.9          // while the bars rise again, middle first
    static let riseDuration = 0.8
    static let openStart = 4.0
    static let total = 4.7
    /// With Reduce Motion the finished logo is shown briefly, then fades.
    static let reducedTotal = 0.6

    /// Radians per second: one slow rise and fall every two to three and a half seconds, each bar at its own pace.
    private static let frequencies: [Double] = [1.9, 2.5, 2.2, 2.9, 1.8, 2.7, 2.3, 3.0]
    private static let phases: [Double] = [0.0, 1.9, 3.6, 0.8, 2.7, 4.4, 1.3, 5.2]

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func smooth(_ x: Double) -> Double { let p = clamp(x); return p * p * (3 - 2 * p) }
    private static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    private static func easeInOutCubic(_ x: Double) -> Double { let p = clamp(x); return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    private static func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }

    private static func riseStart(_ i: Int) -> Double { riseStart + 0.05 * Double(abs(i - LogoGeometry.peak)) }

    /// One bar moving on its own: a rounded wave between a fifth and the full height, eased in so nothing jolts.
    static func liveLevel(_ i: Int, at t: Double) -> Double {
        let floor = LogoGeometry.floor
        let wave = 0.2 + 0.8 * pow(0.5 + 0.5 * sin(frequencies[i] * t + phases[i]), 1.2)
        return floor + (wave - floor) * smooth((t - emergeStart) / (liveStart - emergeStart))
    }

    static func level(_ i: Int, at t: Double) -> Double {
        let floor = LogoGeometry.floor, target = LogoGeometry.levels[i]
        let start = riseStart(i)
        if t >= start {
            let p = (t - start) / riseDuration
            return p >= 1 ? target : floor + (target - floor) * smooth(p)
        }
        if t >= collapseStart { return floor + (liveLevel(i, at: t) - floor) * (1 - smooth((t - collapseStart) / (collapseEnd - collapseStart))) }
        return liveLevel(i, at: t)
    }

    static func frame(at t: Double) -> LaunchFrame {
        let levels = LogoGeometry.levels.indices.map { level($0, at: t) }
        let rowHalf = LogoGeometry.rowHalf
        let ring = easeInOutCubic((t - ringStart) / (ringEnd - ringStart))
        let halfWidth: Double = t < ringStart ? rowHalf * easeOutCubic(t / lineEnd) : lerp(rowHalf, LogoGeometry.ringA, ring)
        // The line shows at first, fades as the bars take over, comes back as they fall, and is the ring after that.
        let opacity: Double
        if t < emergeStart { opacity = min(1, t / 0.12) }
        else if t < liveStart { opacity = 1 - smooth((t - emergeStart) / 0.4) }
        else if t < collapseStart { opacity = 0 }
        else if t < collapseEnd { opacity = smooth((t - collapseStart) / (collapseEnd - collapseStart)) }
        else { opacity = 1 }
        let open = clamp((t - openStart) / (total - openStart))
        let shine = t < ringStart ? 0 : ((t - ringStart) / 1.6).truncatingRemainder(dividingBy: 1)
        return LaunchFrame(
            levels: levels,
            ringHalfWidth: halfWidth,
            ringOpen: ring,
            ringDegrees: LogoGeometry.ringDegrees * ring,
            ringOpacity: opacity,
            shine: shine,
            glow: 0.45 + 0.4 * (levels.max() ?? 0),
            logoScale: 1 + 0.3 * easeInOutCubic(open),
            logoOpacity: 1 - clamp((open - 0.1) / 0.6),
            reveal: easeInOutCubic(open),
            bloom: sin(.pi * clamp(open * 1.4)))
    }

    /// The finished logo, for Reduce Motion: nothing moves and nothing expands.
    static func reducedFrame(at t: Double) -> LaunchFrame {
        LaunchFrame(levels: LogoGeometry.levels, ringHalfWidth: LogoGeometry.ringA, ringOpen: 1, ringDegrees: LogoGeometry.ringDegrees,
                    ringOpacity: 1, shine: 0.35, glow: 0.65, logoScale: 1, logoOpacity: 1 - clamp((t - 0.3) / 0.3), reveal: 0, bloom: 0)
    }

    /// A gentle idle motion for the logo on the welcome screen: the bars breathe a little and a glint travels round the ring.
    static func idle(at t: Double) -> LaunchFrame {
        let levels = LogoGeometry.levels.indices.map { i in
            min(1, max(0.12, LogoGeometry.levels[i] + 0.06 * sin(1.1 * t + phases[i])))
        }
        return LaunchFrame(levels: levels, ringHalfWidth: LogoGeometry.ringA, ringOpen: 1, ringDegrees: LogoGeometry.ringDegrees, ringOpacity: 1,
                           shine: (t / 3.2).truncatingRemainder(dividingBy: 1), glow: 0.65, logoScale: 1, logoOpacity: 1, reveal: 0, bloom: 0)
    }
}
