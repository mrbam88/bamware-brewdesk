import BrewDeskKit
import Testing
@testable import BrewDesk

/// Pure-logic coverage for the cold-launch reveal's stage timing
/// (bamware-brewdesk#186) — no view, no simulator, no `Timer`/`Task`
/// involved. `LaunchRevealTimeline.frame(atElapsedMS:)` and
/// `overlayOpacity(atElapsedMS:)` are plain functions of a `Double`, so
/// every assertion below is exact and instant.
@Suite struct LaunchRevealTimelineTests {
    // MARK: - Frame 0 / start state

    @Test func frameZeroIsFullyHidden() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: 0)
        #expect(stage.bodyOpacity == 0)
        #expect(stage.bodyScale == 0.96)
        #expect(stage.dotScale == 0)
        #expect(stage.arc1Trim == 0)
        #expect(stage.arc2Trim == 0)
        #expect(stage.arc3Trim == 0)
        #expect(stage.glowOpacity == 0)
    }

    @Test func overlayStartsFullyOpaque() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: 0) == 1)
    }

    // MARK: - Body settle (0–350ms)

    @Test func bodyFullyVisibleAtSettleEnd() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.bodySettleDuration)
        #expect(stage.bodyOpacity == 1)
        // A slight overshoot past 1.0 mid-settle, per the design spec's
        // "spring, slight overshoot" — settled scale itself lands at 1.0.
        #expect(abs(stage.bodyScale - 1.0) < 0.001)
    }

    @Test func bodyPartiallyVisibleMidSettle() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.bodySettleDuration / 2)
        #expect(stage.bodyOpacity > 0 && stage.bodyOpacity < 1)
    }

    // MARK: - Dot pop (300ms start, 180ms long, overshoots to 1.15)

    @Test func dotHiddenBeforeItsStart() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.dotPopStart - 1)
        #expect(stage.dotScale == 0)
    }

    @Test func dotOvershootsPastOneMidPop() {
        // 60% through the pop is exactly the overshoot peak in the model.
        let midPop = LaunchRevealTimeline.dotPopStart + LaunchRevealTimeline.dotPopDuration * 0.6
        let stage = LaunchRevealTimeline.frame(atElapsedMS: midPop)
        #expect(abs(stage.dotScale - 1.15) < 0.001)
    }

    @Test func dotSettlesToOneAtPopEnd() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.dotPopStart + LaunchRevealTimeline.dotPopDuration)
        #expect(abs(stage.dotScale - 1.0) < 0.001)
    }

    // MARK: - Arcs draw on (380/470/560ms, 260ms each)

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

    @Test func arcsStartInAscendingOrder() {
        #expect(LaunchRevealTimeline.arcStarts == LaunchRevealTimeline.arcStarts.sorted())
    }

    // MARK: - Glow pulse (780ms start, 300ms long, one soft peak)

    @Test func glowIsZeroBeforeAndAtItsBoundaries() {
        #expect(LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.glowStart - 1).glowOpacity == 0)
        let atEnd = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.glowStart + LaunchRevealTimeline.glowDuration)
        #expect(atEnd.glowOpacity < 0.001)
    }

    @Test func glowPeaksAtItsMidpoint() {
        let midpoint = LaunchRevealTimeline.glowStart + LaunchRevealTimeline.glowDuration / 2
        let stage = LaunchRevealTimeline.frame(atElapsedMS: midpoint)
        #expect(abs(stage.glowOpacity - LaunchRevealTimeline.glowPeakOpacity) < 0.001)
    }

    // MARK: - Crossfade out (950ms start, 200ms long)

    @Test func overlayIsGoneAfterCrossfadeEnds() {
        let end = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: end) == 0)
    }

    @Test func overlayIsPartiallyFadedMidCrossfade() {
        let mid = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration / 2
        let opacity = LaunchRevealTimeline.overlayOpacity(atElapsedMS: mid)
        #expect(opacity > 0 && opacity < 1)
    }

    // MARK: - Hard cap (1200ms regardless)

    @Test func overlayIsGoneAtAndBeyondTheHardCap() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS) == 0)
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS + 5000) == 0)
    }

    @Test func hardCapIsAtOrAfterEveryOtherStageEnds() {
        let crossfadeEnd = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(LaunchRevealTimeline.hardCapMS >= crossfadeEnd)
        let glowEnd = LaunchRevealTimeline.glowStart + LaunchRevealTimeline.glowDuration
        #expect(LaunchRevealTimeline.hardCapMS >= glowEnd)
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
