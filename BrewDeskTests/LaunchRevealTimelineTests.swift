import BrewDeskKit
import Testing
@testable import BrewDesk

/// Pure-logic coverage for the cold-launch reveal's stage timing
/// (bamware-brewdesk#186, polished in #193) — no view, no simulator, no
/// `Timer`/`Task` involved. `LaunchRevealTimeline.frame(atElapsedMS:)` and
/// friends are plain functions of a `Double`, so every assertion below is
/// exact and instant.
@Suite struct LaunchRevealTimelineTests {
    // MARK: - Frame 0 / start state

    @Test func frameZeroIsFullyHidden() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: 0)
        #expect(stage.bodyOpacity == 0)
        #expect(stage.bodyScale == 0.97)
        #expect(stage.dotScale == 0)
        #expect(stage.arc1Trim == 0)
        #expect(stage.arc2Trim == 0)
        #expect(stage.arc3Trim == 0)
        #expect(stage.glowOpacity == 0)
    }

    @Test func overlayStartsFullyOpaque() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: 0) == 1)
    }

    @Test func handoffScaleStartsAtOne() {
        #expect(LaunchRevealTimeline.handoffScale(atElapsedMS: 0) == 1)
    }

    // MARK: - Body settle (0–320ms, timingCurve(0.2, 0.9, 0.3, 1.0), no overshoot)

    @Test func bodyFullyVisibleAtSettleEnd() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.bodySettleDuration)
        #expect(abs(stage.bodyOpacity - 1) < 0.001)
        #expect(abs(stage.bodyScale - 1.0) < 0.001)
    }

    @Test func bodyPartiallyVisibleMidSettle() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.bodySettleDuration / 2)
        #expect(stage.bodyOpacity > 0 && stage.bodyOpacity < 1)
    }

    @Test func bodyScaleNeverOvershootsPastOne() {
        // The new curve is a convex combination of control points whose own
        // y's never exceed 1 (0, 0.9, 1.0, 1) — sampling densely across the
        // settle window should never show bodyScale drifting past 1.0 by
        // more than a hair (allow up to 1.5% per the ticket's tolerance).
        var maxScale = 0.0
        for ms in stride(from: 0.0, through: LaunchRevealTimeline.bodySettleDuration, by: 5) {
            maxScale = max(maxScale, LaunchRevealTimeline.frame(atElapsedMS: ms).bodyScale)
        }
        #expect(maxScale <= 1.0 + 0.015)
    }

    // MARK: - Dot pop (250ms start, 140ms long, overshoots to 1.08)

    @Test func dotHiddenBeforeItsStart() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.dotPopStart - 1)
        #expect(stage.dotScale == 0)
    }

    @Test func dotOvershootsPastOneMidPop() {
        // 60% through the pop is exactly the overshoot peak in the model.
        let midPop = LaunchRevealTimeline.dotPopStart + LaunchRevealTimeline.dotPopDuration * 0.6
        let stage = LaunchRevealTimeline.frame(atElapsedMS: midPop)
        #expect(abs(stage.dotScale - 1.08) < 0.001)
    }

    @Test func dotSettlesToOneAtPopEnd() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.dotPopStart + LaunchRevealTimeline.dotPopDuration)
        #expect(abs(stage.dotScale - 1.0) < 0.001)
    }

    // MARK: - Arcs draw on (300/370/440ms, 220ms each, ease-out)

    @Test func arcsAreZeroBeforeTheirOwnStart() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.arcStarts[0] - 1)
        #expect(stage.arc1Trim == 0)
        #expect(stage.arc2Trim == 0)
        #expect(stage.arc3Trim == 0)
    }

    @Test func eachArcReachesFullTrimAtItsOwnEnd() {
        for (index, start) in LaunchRevealTimeline.arcStarts.enumerated() {
            let stage = LaunchRevealTimeline.frame(atElapsedMS: start + LaunchRevealTimeline.arcDuration)
            let trim = [stage.arc1Trim, stage.arc2Trim, stage.arc3Trim][index]
            #expect(trim == 1, "arc \(index) should be fully drawn by \(start + LaunchRevealTimeline.arcDuration)ms")
        }
    }

    @Test func arcsStartInAscendingOrderSeventyMsApart() {
        #expect(LaunchRevealTimeline.arcStarts == LaunchRevealTimeline.arcStarts.sorted())
        let gaps = zip(LaunchRevealTimeline.arcStarts, LaunchRevealTimeline.arcStarts.dropFirst()).map { $1 - $0 }
        #expect(gaps == [70, 70])
    }

    @Test func markIsFullyDrawnBySevenHundredMS() {
        let lastArcEnd = LaunchRevealTimeline.arcStarts.last! + LaunchRevealTimeline.arcDuration
        #expect(lastArcEnd <= 700)
    }

    @Test func arcTrimEasesOutRatherThanLinear() {
        // Ease-out means more progress happens early than a linear ramp
        // would give — at 25% through the duration, trim should already be
        // further along than 25%.
        let quarterPoint = LaunchRevealTimeline.arcStarts[0] + LaunchRevealTimeline.arcDuration * 0.25
        let stage = LaunchRevealTimeline.frame(atElapsedMS: quarterPoint)
        #expect(stage.arc1Trim > 0.25)
    }

    // MARK: - Light sweep (680ms start, 380ms long, once, ease-in-out)

    @Test func sweepInactiveBeforeItsWindow() {
        #expect(!LaunchRevealTimeline.isSweepActive(atElapsedMS: LaunchRevealTimeline.sweepStart - 1))
        #expect(LaunchRevealTimeline.sweepOpacityProgress(atElapsedMS: LaunchRevealTimeline.sweepStart - 1) == 0)
    }

    @Test func sweepActiveThroughoutItsWindow() {
        #expect(LaunchRevealTimeline.isSweepActive(atElapsedMS: LaunchRevealTimeline.sweepStart))
        #expect(LaunchRevealTimeline.isSweepActive(atElapsedMS: LaunchRevealTimeline.sweepStart + LaunchRevealTimeline.sweepDuration))
    }

    @Test func sweepInactiveAfterItsWindow() {
        #expect(!LaunchRevealTimeline.isSweepActive(atElapsedMS: LaunchRevealTimeline.sweepStart + LaunchRevealTimeline.sweepDuration + 1))
    }

    @Test func sweepProgressReachesOneAtWindowEnd() {
        let end = LaunchRevealTimeline.sweepStart + LaunchRevealTimeline.sweepDuration
        #expect(abs(LaunchRevealTimeline.sweepOpacityProgress(atElapsedMS: end) - 1) < 0.001)
    }

    @Test func sweepStartsAfterTheMarkFinishesDrawing() {
        let lastArcEnd = LaunchRevealTimeline.arcStarts.last! + LaunchRevealTimeline.arcDuration
        #expect(LaunchRevealTimeline.sweepStart >= lastArcEnd)
    }

    // MARK: - Hand-off (900ms start, 220ms long, fade + scale to 1.04)

    @Test func overlayIsGoneAfterHandoffEnds() {
        let end = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: end) == 0)
    }

    @Test func overlayIsPartiallyFadedMidHandoff() {
        let mid = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration / 2
        let opacity = LaunchRevealTimeline.overlayOpacity(atElapsedMS: mid)
        #expect(opacity > 0 && opacity < 1)
    }

    @Test func handoffScaleReachesPeakAtHandoffEnd() {
        let end = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(abs(LaunchRevealTimeline.handoffScale(atElapsedMS: end) - 1.04) < 0.001)
    }

    @Test func handoffScaleIsMonotonicDuringItsWindow() {
        var previous = LaunchRevealTimeline.handoffScale(atElapsedMS: LaunchRevealTimeline.crossfadeStart)
        for ms in stride(from: LaunchRevealTimeline.crossfadeStart, through: LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration, by: 10) {
            let scale = LaunchRevealTimeline.handoffScale(atElapsedMS: ms)
            #expect(scale >= previous - 0.0001)
            previous = scale
        }
    }

    // MARK: - Hard cap (1200ms regardless)

    @Test func overlayIsGoneAtAndBeyondTheHardCap() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS) == 0)
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS + 5000) == 0)
    }

    @Test func hardCapIsAtOrAfterEveryOtherStageEnds() {
        let handoffEnd = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(LaunchRevealTimeline.hardCapMS >= handoffEnd)
        let sweepEnd = LaunchRevealTimeline.sweepStart + LaunchRevealTimeline.sweepDuration
        #expect(LaunchRevealTimeline.hardCapMS >= sweepEnd)
        for start in LaunchRevealTimeline.arcStarts {
            #expect(LaunchRevealTimeline.hardCapMS >= start + LaunchRevealTimeline.arcDuration)
        }
    }

    @Test func frameNeverExtrapolatesPastTheHardCap() {
        let atCap = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.hardCapMS)
        let wayPast = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.hardCapMS + 10_000)
        #expect(atCap == wayPast)
    }

    // MARK: - Reduce Motion: fade only, no other motion

    @Test func reducedMotionFadesOutOverItsOwnShorterDuration() {
        #expect(LaunchRevealTimeline.reducedMotionOverlayOpacity(atElapsedMS: 0) == 1)
        let end = LaunchRevealTimeline.reducedMotionFadeDuration
        #expect(LaunchRevealTimeline.reducedMotionOverlayOpacity(atElapsedMS: end) == 0)
        #expect(LaunchRevealTimeline.reducedMotionFadeDuration < LaunchRevealTimeline.hardCapMS)
    }

    // MARK: - Negative/garbage input doesn't crash or go out of range

    @Test func negativeElapsedClampsToFrameZero() {
        #expect(LaunchRevealTimeline.frame(atElapsedMS: -500) == LaunchRevealTimeline.frame(atElapsedMS: 0))
    }
}

/// Coverage for the pure Bezier-easing helper `LaunchRevealTimeline` uses
/// for the body settle, isolated from the timeline's own stage assembly.
@Suite struct CubicBezierEaseTests {
    private let ease = CubicBezierEase(x1: 0.2, y1: 0.9, x2: 0.3, y2: 1.0)

    @Test func startsAtZeroEndsAtOne() {
        #expect(ease.solve(0) == 0)
        #expect(ease.solve(1) == 1)
    }

    @Test func neverExceedsOne() {
        for i in stride(from: 0.0, through: 1.0, by: 0.02) {
            #expect(ease.solve(i) <= 1.0 + 0.0001)
        }
    }

    @Test func isMonotonicallyNonDecreasing() {
        var previous = 0.0
        for i in stride(from: 0.0, through: 1.0, by: 0.02) {
            let y = ease.solve(i)
            #expect(y >= previous - 0.0001)
            previous = y
        }
    }

    @Test func clampsOutOfRangeInput() {
        #expect(ease.solve(-1) == 0)
        #expect(ease.solve(2) == 1)
    }
}
