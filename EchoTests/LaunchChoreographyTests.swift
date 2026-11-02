import Foundation
import Testing
@testable import Echo

struct LaunchChoreographyTests {
    private let steps = stride(from: 0.0, through: LaunchChoreography.total, by: 0.02).map { $0 }

    @Test func theLogoIsEightUnevenBarsWithTheSparkleOnTheTallest() {
        let levels = LogoGeometry.levels
        #expect(levels.count == 8)
        #expect(levels.max() == 1 && levels[LogoGeometry.peak] == 1, "the tallest bar carries the sparkle")
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
        let early = LaunchChoreography.frame(at: 0.6).levels
        let later = LaunchChoreography.frame(at: 0.75).levels
        #expect(early != later, "they are moving")
        #expect(Set(early.map { ($0 * 1000).rounded() }).count > 4, "and not in step with one another")
        #expect(LaunchChoreography.frame(at: 0.0).levels.allSatisfy { $0 <= 0.2 }, "they start low")
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
        let mid = LaunchChoreography.frame(at: 1.45)
        #expect(mid.sparkleScale > 0 && mid.sparkleDegrees < 0, "it spins in")
        let done = LaunchChoreography.frame(at: LaunchChoreography.sparkleEnd + 0.2)
        #expect(abs(done.sparkleScale - 1) < 0.2 && done.sparkleDegrees == 0)
        #expect(LaunchChoreography.frame(at: 1.3).starScale == 0 && LaunchChoreography.frame(at: 1.9).starScale > 0.9)
    }

    @Test func theAppIsRevealedByACircleThatGrowsFromNothingToEverything() {
        #expect(LaunchChoreography.frame(at: LaunchChoreography.openStart).reveal == 0)
        #expect(LaunchChoreography.frame(at: LaunchChoreography.openStart - 0.5).reveal == 0)
        #expect(LaunchChoreography.frame(at: LaunchChoreography.total).reveal == 1)
        let reveals = stride(from: LaunchChoreography.openStart, through: LaunchChoreography.total, by: 0.02).map { LaunchChoreography.frame(at: $0).reveal }
        #expect(zip(reveals, reveals.dropFirst()).allSatisfy { $0 <= $1 }, "it only grows")
        let end = LaunchChoreography.frame(at: LaunchChoreography.total)
        #expect(end.logoOpacity == 0 && end.logoScale > 1.2, "the logo has grown and gone")
        #expect(end.bloom < 0.2 && LaunchChoreography.frame(at: 1.9).bloom > 0.5, "a flash of light on the way")
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
            #expect(zip(f.levels, LogoGeometry.levels).allSatisfy { abs($0 - $1) <= 0.08 + 1e-9 } && f.sparkleScale > 0.9)
        }
    }
}
