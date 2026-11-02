import Foundation
import Testing
@testable import Echo

struct LaunchChoreographyTests {
    private typealias C = LaunchChoreography
    private let steps = stride(from: 0.0, through: LaunchChoreography.total, by: 0.02).map { $0 }

    @Test func theLogoIsEightUnevenBarsInsideATiltedRing() {
        let levels = LogoGeometry.levels
        #expect(levels.count == 8 && levels.max() == 1 && levels[LogoGeometry.peak] == 1)
        #expect(Set(levels).count == levels.count, "no two bars are alike")
        #expect(levels != levels.reversed() && levels != levels.sorted(), "not a pyramid and not a staircase")
        #expect(LogoGeometry.ringDegrees == -45)
        #expect(LogoGeometry.ringA > LogoGeometry.rowHalf, "the ring is wider than the bars, so it goes around them")
        #expect(LogoGeometry.ringA > LogoGeometry.ringB)
    }

    @Test func theRingClearsTheBarsAtTheirEnds() {
        // The tilted ellipse's half-width at the height of the tallest bar's top must reach past the row of bars.
        let a = LogoGeometry.ringA, b = LogoGeometry.ringB, c = cos(Double.pi / 4)
        let reach = (a * a * c * c + b * b * c * c).squareRoot()   // the farthest the ring gets from the middle along the axes
        #expect(reach > LogoGeometry.rowHalf && reach > 0.5, "wider than the row and taller than the tallest bar")
    }

    @Test func everyBarStaysInRangeAtEveryMoment() {
        for t in steps {
            let f = C.frame(at: t)
            #expect(f.levels.count == 8 && f.levels.allSatisfy { $0 >= 0 && $0 <= 1 }, "t = \(t)")
        }
    }

    @Test func itStartsAsALineThatDrawsOut() {
        let first = C.frame(at: 0)
        #expect(first.ringHalfWidth == 0 && first.ringOpen == 0, "nothing yet")
        let drawn = C.frame(at: C.lineEnd)
        #expect(drawn.ringHalfWidth == LogoGeometry.rowHalf && drawn.ringOpen == 0 && drawn.ringDegrees == 0 && drawn.ringOpacity > 0.9, "a flat, level line")
        #expect(C.frame(at: 0.0).levels.allSatisfy { $0 == LogoGeometry.floor }, "the bars are dots in it")
    }

    @Test func theBarsGrowOutOfTheLineAndBounceIndependently() {
        #expect(C.frame(at: C.liveStart).ringOpacity == 0, "the line has become the bars")
        let early = C.frame(at: 1.2).levels, later = C.frame(at: 1.45).levels
        #expect(early != later, "they are moving")
        #expect(Set(early.map { ($0 * 1000).rounded() }).count > 4, "and not in step with one another")
    }

    @Test func theBarsMoveGentlyNotFrantically() {
        var biggest = 0.0
        for t in stride(from: 0.0, through: C.total - 0.05, by: 0.05) {
            let a = C.frame(at: t).levels, b = C.frame(at: t + 0.05).levels
            biggest = max(biggest, zip(a, b).map { abs($0 - $1) }.max() ?? 0)
        }
        #expect(biggest < 0.11, "the fastest bar moved \(biggest) of its height in 50 ms")
    }

    @Test func theBarsFallBackIntoALineAndTheLineReturns() {
        let before = C.frame(at: C.collapseStart - 0.01), after = C.frame(at: C.collapseEnd)
        #expect(before.ringOpacity < 0.05 && after.ringOpacity == 1, "the line fades back in as the bars fall")
        #expect(after.levels.allSatisfy { abs($0 - LogoGeometry.floor) < 1e-9 }, "they are dots in a line again")
        #expect(after.ringOpen == 0 && after.ringDegrees == 0)
    }

    @Test func theLineOpensIntoATiltedRingWhileTheBarsRiseAgain() {
        let mid = C.frame(at: (C.ringStart + C.ringEnd) / 2)
        #expect(mid.ringOpen > 0.3 && mid.ringOpen < 0.7 && mid.ringDegrees < 0 && mid.ringDegrees > LogoGeometry.ringDegrees)
        let done = C.frame(at: C.ringEnd)
        #expect(done.ringOpen == 1 && done.ringDegrees == LogoGeometry.ringDegrees && done.ringHalfWidth == LogoGeometry.ringA)
        // The middle bar rises first and the bars finish on the logo exactly.
        let early = C.frame(at: C.riseStart + 0.15).levels
        #expect(early[LogoGeometry.peak] - LogoGeometry.floor > early[0] - LogoGeometry.floor)
        #expect(C.frame(at: C.openStart).levels == LogoGeometry.levels)
    }

    @Test func theRingOnlyEverOpensAndTurns() {
        let opens = stride(from: C.ringStart, through: C.ringEnd, by: 0.02).map { C.frame(at: $0).ringOpen }
        #expect(zip(opens, opens.dropFirst()).allSatisfy { $0 <= $1 })
        let angles = stride(from: C.ringStart, through: C.ringEnd, by: 0.02).map { C.frame(at: $0).ringDegrees }
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 >= $1 }, "it turns one way, to -45 degrees")
    }

    @Test func aGlintTravelsRoundTheFinishedRing() {
        let glints = stride(from: C.ringEnd, through: C.openStart, by: 0.1).map { C.frame(at: $0).shine }
        #expect(Set(glints.map { ($0 * 100).rounded() }).count > 3 && glints.allSatisfy { $0 >= 0 && $0 < 1 })
    }

    @Test func theAppIsRevealedByACircleThatGrowsFromNothingToEverything() {
        #expect(C.frame(at: C.openStart).reveal == 0 && C.frame(at: C.openStart - 0.5).reveal == 0 && C.frame(at: C.total).reveal == 1)
        let reveals = stride(from: C.openStart, through: C.total, by: 0.02).map { C.frame(at: $0).reveal }
        #expect(zip(reveals, reveals.dropFirst()).allSatisfy { $0 <= $1 }, "it only grows")
        let end = C.frame(at: C.total)
        #expect(end.logoOpacity == 0 && end.logoScale > 1.2, "the logo has grown and gone")
        let middle = (C.openStart + C.total) / 2
        #expect(end.bloom < 0.2 && C.frame(at: middle).bloom > 0.5, "a flash of light on the way")
    }

    @Test func theAnimationIsTheSameEveryTime() {
        #expect(C.frame(at: 1.3) == C.frame(at: 1.3))
    }

    @Test func reduceMotionShowsTheFinishedLogoAndOnlyFades() {
        for t in stride(from: 0.0, through: C.reducedTotal, by: 0.05) {
            let f = C.reducedFrame(at: t)
            #expect(f.levels == LogoGeometry.levels && f.reveal == 0 && f.logoScale == 1 && f.ringOpen == 1 && f.ringDegrees == LogoGeometry.ringDegrees)
        }
        #expect(C.reducedFrame(at: 0).logoOpacity == 1 && C.reducedFrame(at: C.reducedTotal).logoOpacity == 0)
    }

    @Test func theIdleLogoOnlyBreathesAroundTheLogoShape() {
        for t in stride(from: 0.0, through: 20.0, by: 0.5) {
            let f = C.idle(at: t)
            #expect(zip(f.levels, LogoGeometry.levels).allSatisfy { abs($0 - $1) <= 0.07 + 1e-9 } && f.ringOpen == 1 && f.shine >= 0 && f.shine < 1)
        }
    }
}
