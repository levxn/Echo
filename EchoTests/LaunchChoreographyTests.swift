import Foundation
import Testing
@testable import Echo

struct LaunchChoreographyTests {
    private let steps = stride(from: 0.0, through: LaunchChoreography.total, by: 0.02).map { $0 }

    @Test func theLogoIsEightUnevenBars() {
        let levels = LogoGeometry.levels
        #expect(levels.count == 8)
        #expect(levels.max() == 1 && levels[LogoGeometry.peak] == 1)
        #expect(Set(levels).count == levels.count, "no two bars are alike")
        #expect(levels != levels.reversed() && levels != levels.sorted() , "not a pyramid and not a staircase")
        #expect(levels.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test func everyBarStaysInRangeAtEveryMoment() {
        for t in steps {
            let f = LaunchChoreography.frame(at: t)
            #expect(f.levels.count == 8 && f.levels.allSatisfy { $0 >= 0 && $0 <= 1 }, "t = \(t)")
        }
    }

    @Test func theBarsBounceIndependentlyAtFirst() {
        let early = LaunchChoreography.frame(at: 0.9).levels
        let later = LaunchChoreography.frame(at: 1.1).levels
        #expect(early != later, "they are moving")
        #expect(Set(early.map { ($0 * 1000).rounded() }).count > 4, "and not in step with one another")
        #expect(LaunchChoreography.frame(at: 0.0).levels.allSatisfy { $0 <= 0.2 }, "they start low")
    }

    @Test func theBarsMoveGentlyNotFrantically() {
        // Between two frames a twentieth of a second apart no bar may jump by more than a few percent of its full height.
        var biggest = 0.0
        for t in stride(from: 0.0, through: LaunchChoreography.liveEnd, by: 0.05) {
            let a = LaunchChoreography.frame(at: t).levels, b = LaunchChoreography.frame(at: t + 0.05).levels
            biggest = max(biggest, zip(a, b).map { abs($0 - $1) }.max() ?? 0)
        }
        #expect(biggest < 0.10, "the fastest bar moved \(biggest) in 50 ms")
    }

    @Test func theMotionSettlesExactlyOntoTheLogo() {
        #expect(LaunchChoreography.frame(at: LaunchChoreography.settleEnd).levels == LogoGeometry.levels)
        #expect(LaunchChoreography.frame(at: LaunchChoreography.total).levels == LogoGeometry.levels)
        // How far the bars are from the logo only ever shrinks while they settle (a smooth freeze, no jolt).
        func distance(_ t: Double) -> Double {
            zip(LaunchChoreography.frame(at: t).levels, LogoGeometry.levels).map { abs($0 - $1) }.reduce(0, +)
        }
        let settling = stride(from: LaunchChoreography.liveEnd, through: LaunchChoreography.settleEnd, by: 0.1).map(distance)
        #expect(settling.last == 0 && settling.first! > 0.5)
        // No jump at the moment the bars start settling.
        let before = LaunchChoreography.frame(at: LaunchChoreography.liveEnd - 0.001).levels
        let after = LaunchChoreography.frame(at: LaunchChoreography.liveEnd + 0.001).levels
        #expect(zip(before, after).allSatisfy { abs($0 - $1) < 0.05 })
    }

    @Test func theSparkleAppearsAfterTheBarsSlowDownAndEndsAtFullSize() {
        #expect(LaunchChoreography.frame(at: LaunchChoreography.sparkleStart - 0.01).sparkleScale == 0)
        let mid = LaunchChoreography.frame(at: (LaunchChoreography.sparkleStart + LaunchChoreography.sparkleEnd) / 2)
        #expect(mid.sparkleScale > 0 && mid.sparkleDegrees < 0, "it spins in")
        let done = LaunchChoreography.frame(at: LaunchChoreography.sparkleEnd + 0.1)
        #expect(abs(done.sparkleScale - 1) < 0.2 && done.sparkleDegrees == 0)
        #expect(LaunchChoreography.sparkleStart < LaunchChoreography.settleEnd, "it arrives as the bars come to rest")
    }

    @Test func theAppIsRevealedByACircleThatGrowsFromNothingToEverything() {
        #expect(LaunchChoreography.frame(at: LaunchChoreography.openStart).reveal == 0)
        #expect(LaunchChoreography.frame(at: LaunchChoreography.openStart - 0.5).reveal == 0)
        #expect(LaunchChoreography.frame(at: LaunchChoreography.total).reveal == 1)
        let reveals = stride(from: LaunchChoreography.openStart, through: LaunchChoreography.total, by: 0.02).map { LaunchChoreography.frame(at: $0).reveal }
        #expect(zip(reveals, reveals.dropFirst()).allSatisfy { $0 <= $1 }, "it only grows")
        let end = LaunchChoreography.frame(at: LaunchChoreography.total)
        #expect(end.logoOpacity == 0 && end.logoScale > 1.2, "the logo has grown and gone")
        let middle = (LaunchChoreography.openStart + LaunchChoreography.total) / 2
        #expect(end.bloom < 0.2 && LaunchChoreography.frame(at: middle).bloom > 0.5, "a flash of light on the way")
    }

    @Test func theAnimationIsTheSameEveryTime() {
        #expect(LaunchChoreography.frame(at: 0.9) == LaunchChoreography.frame(at: 0.9))
    }

    @Test func reduceMotionShowsTheFinishedLogoAndOnlyFades() {
        for t in stride(from: 0.0, through: LaunchChoreography.reducedTotal, by: 0.05) {
            let f = LaunchChoreography.reducedFrame(at: t)
            #expect(f.levels == LogoGeometry.levels && f.reveal == 0 && f.logoScale == 1 && f.sparkleScale == 1)
        }
        #expect(LaunchChoreography.reducedFrame(at: 0).logoOpacity == 1 && LaunchChoreography.reducedFrame(at: LaunchChoreography.reducedTotal).logoOpacity == 0)
    }

    @Test func theIdleLogoOnlyBreathesAroundTheLogoShape() {
        for t in stride(from: 0.0, through: 20.0, by: 0.5) {
            let f = LaunchChoreography.idle(at: t)
            #expect(zip(f.levels, LogoGeometry.levels).allSatisfy { abs($0 - $1) <= 0.07 + 1e-9 } && f.sparkleScale > 0.85)
        }
    }

    @Test func theSparkleSitsInTheTopRightCornerClearOfTheBars() {
        let bw = LogoGeometry.barWidth, pitch = LogoGeometry.barWidth + LogoGeometry.gap
        let rowHalf = (Double(LogoGeometry.levels.count) * bw + Double(LogoGeometry.levels.count - 1) * LogoGeometry.gap) / 2
        let r = LogoGeometry.sparkleRadius
        #expect(LogoGeometry.sparkleX > 0 && LogoGeometry.sparkleY < 0, "top right")
        // For every bar the sparkle's lowest point is above the bar's top (y grows downwards from the middle).
        for (i, level) in LogoGeometry.levels.enumerated() {
            let center = Double(i) * pitch + bw / 2 - rowHalf
            let overlapsHorizontally = abs(center - LogoGeometry.sparkleX) < (bw / 2 + r)
            let barTop = -level / 2
            if overlapsHorizontally { #expect(LogoGeometry.sparkleY + r <= barTop + 1e-9, "bar \(i) is clear of the sparkle") }
        }
    }
}
