import BrewDeskKit
import Testing
@testable import BrewDesk

/// Pure-logic coverage for the cold-launch reveal's stage timing
/// (bamware-brewdesk#186, polished in #193, redesigned as an additive
/// signal pulse in #205 after the #193 "draw on" timeline read as broken
/// on a device) — no view, no simulator, no `Timer`/`Task` involved.
/// `LaunchRevealTimeline.frame(atElapsedMS:)` and friends are plain
/// functions of a `Double`, so every assertion below is exact and instant.
@Suite struct LaunchRevealTimelineTests {
    // MARK: - Frame 0: the whole point of #205

    /// The load-bearing guarantee this ticket exists to make true: frame 0
    /// is byte-for-byte `.settled`, i.e. pixel-identical to the static
    /// `LaunchMark` iOS was already showing. Nothing is hidden, trimmed,
    /// or faded at the start anymore.
    @Test func frameZeroIsExactlySettled() {
        #expect(LaunchRevealTimeline.frame(atElapsedMS: 0) == BrewDeskMarkStage.settled)
    }

    @Test func overlayStartsFullyOpaque() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: 0) == 1)
    }

    @Test func handoffScaleStartsAtOne() {
        #expect(LaunchRevealTimeline.handoffScale(atElapsedMS: 0) == 1)
    }

    /// Nothing before the dot's own pulse window moves at all — guards
    /// against the exact bug this ticket was filed over: something visibly
    /// changing before the reveal's first intentional motion.
    @Test func nothingMovesBeforeTheDotPulseStarts() {
        for ms in stride(from: 0.0, to: LaunchRevealTimeline.dotPulseStart, by: 10) {
            #expect(LaunchRevealTimeline.frame(atElapsedMS: ms) == BrewDeskMarkStage.settled, "unexpected motion at \(ms)ms")
        }
    }

    // MARK: - Body never moves before hand-off (spec-gap: no "breath")

    @Test func bodyScaleIsAlwaysExactlyOneBeforeHandoff() {
        for ms in stride(from: 0.0, to: LaunchRevealTimeline.crossfadeStart, by: 20) {
            #expect(LaunchRevealTimeline.frame(atElapsedMS: ms).bodyScale == 1, "body moved at \(ms)ms")
        }
    }

    // MARK: - Dot pulse (120ms start, 220ms long, 1→1.18→1, ease-in-out)

    @Test func dotAtRestBeforeItsPulseStarts() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.dotPulseStart - 1)
        #expect(stage.dotScale == 1)
    }

    @Test func dotReachesPeakAtPulseMidpoint() {
        let mid = LaunchRevealTimeline.dotPulseStart + LaunchRevealTimeline.dotPulseDuration / 2
        let stage = LaunchRevealTimeline.frame(atElapsedMS: mid)
        #expect(abs(stage.dotScale - 1.18) < 0.001)
    }

    @Test func dotSettlesBackToOneAtPulseEnd() {
        let end = LaunchRevealTimeline.dotPulseStart + LaunchRevealTimeline.dotPulseDuration
        let stage = LaunchRevealTimeline.frame(atElapsedMS: end)
        #expect(abs(stage.dotScale - 1) < 0.001)
    }

    @Test func dotStaysAtRestAfterItsPulseEnds() {
        let end = LaunchRevealTimeline.dotPulseStart + LaunchRevealTimeline.dotPulseDuration
        let stage = LaunchRevealTimeline.frame(atElapsedMS: end + 50)
        #expect(stage.dotScale == 1)
    }

    @Test func dotNeverExceedsItsOwnPeak() {
        var maxScale = 0.0
        for ms in stride(from: LaunchRevealTimeline.dotPulseStart, through: LaunchRevealTimeline.dotPulseStart + LaunchRevealTimeline.dotPulseDuration, by: 2) {
            maxScale = max(maxScale, LaunchRevealTimeline.frame(atElapsedMS: ms).dotScale)
        }
        #expect(maxScale <= 1.18 + 0.001)
    }

    // MARK: - Arc pulses (200/290/380ms, 260ms each, 1→1.05→1)

    @Test func arcsStartInAscendingOrderNinetyMsApart() {
        #expect(LaunchRevealTimeline.arcPulseStarts == LaunchRevealTimeline.arcPulseStarts.sorted())
        let gaps = zip(LaunchRevealTimeline.arcPulseStarts, LaunchRevealTimeline.arcPulseStarts.dropFirst()).map { $1 - $0 }
        #expect(gaps == [90, 90])
    }

    @Test func eachArcAtRestBeforeItsOwnPulseStarts() {
        for (index, start) in LaunchRevealTimeline.arcPulseStarts.enumerated() {
            let stage = LaunchRevealTimeline.frame(atElapsedMS: start - 1)
            let scale = [stage.arc1Scale, stage.arc2Scale, stage.arc3Scale][index]
            #expect(scale == 1, "arc \(index) should be at rest before \(start)ms")
        }
    }

    @Test func eachArcReachesItsOwnPeakAtPulseMidpoint() {
        for (index, start) in LaunchRevealTimeline.arcPulseStarts.enumerated() {
            let mid = start + LaunchRevealTimeline.arcPulseDuration / 2
            let stage = LaunchRevealTimeline.frame(atElapsedMS: mid)
            let scale = [stage.arc1Scale, stage.arc2Scale, stage.arc3Scale][index]
            #expect(abs(scale - 1.05) < 0.001, "arc \(index) should peak at \(mid)ms")
        }
    }

    @Test func eachArcSettlesBackToOneAtItsOwnPulseEnd() {
        for (index, start) in LaunchRevealTimeline.arcPulseStarts.enumerated() {
            let end = start + LaunchRevealTimeline.arcPulseDuration
            let stage = LaunchRevealTimeline.frame(atElapsedMS: end)
            let scale = [stage.arc1Scale, stage.arc2Scale, stage.arc3Scale][index]
            #expect(abs(scale - 1) < 0.001, "arc \(index) should be back at rest by \(end)ms")
        }
    }

    @Test func arcsFinishPulsingWellBeforeHandoff() {
        let lastArcEnd = LaunchRevealTimeline.arcPulseStarts.last! + LaunchRevealTimeline.arcPulseDuration
        #expect(lastArcEnd <= LaunchRevealTimeline.crossfadeStart)
    }

    // MARK: - Ripple (430ms start, 420ms long, scale 1→1.45, opacity 0.45→0)

    @Test func rippleInvisibleBeforeItsWindow() {
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.rippleStart - 1)
        #expect(stage.rippleOpacity == 0)
        #expect(stage.rippleScale == 1)
    }

    @Test func rippleStartsAtOutermostArcsOwnRadiusWithNoJump() {
        // scale == 1 at the very instant it becomes visible — "starting at
        // arc 3's radius" per the ticket, i.e. no pop-in jump.
        let stage = LaunchRevealTimeline.frame(atElapsedMS: LaunchRevealTimeline.rippleStart)
        #expect(stage.rippleScale == 1)
        #expect(abs(stage.rippleOpacity - 0.45) < 0.001)
    }

    @Test func rippleExpandsAndFadesOutOnlyAcrossItsWindow() {
        let end = LaunchRevealTimeline.rippleStart + LaunchRevealTimeline.rippleDuration
        let stage = LaunchRevealTimeline.frame(atElapsedMS: end)
        #expect(abs(stage.rippleScale - 1.45) < 0.001)
        #expect(stage.rippleOpacity == 0)
    }

    @Test func rippleOpacityNeverIncreases() {
        var previous = Double.infinity
        for ms in stride(from: LaunchRevealTimeline.rippleStart, through: LaunchRevealTimeline.rippleStart + LaunchRevealTimeline.rippleDuration, by: 10) {
            let opacity = LaunchRevealTimeline.frame(atElapsedMS: ms).rippleOpacity
            #expect(opacity <= previous + 0.0001)
            previous = opacity
        }
    }

    @Test func rippleInvisibleAfterItsWindow() {
        let end = LaunchRevealTimeline.rippleStart + LaunchRevealTimeline.rippleDuration
        let stage = LaunchRevealTimeline.frame(atElapsedMS: end + 50)
        #expect(stage.rippleOpacity == 0)
        #expect(stage.rippleScale == 1)
    }

    /// Unlike the arcs, the ripple's own window (430–850ms) genuinely runs
    /// past the hand-off's start (760ms) — the ticket's own numbers do
    /// this. That's fine: the ripple only ever fades further toward 0
    /// opacity as it goes (never brightens/reappears), so overlapping with
    /// the overlay's own fade just means it finishes invisible slightly
    /// earlier than its nominal end, never that something "un-fades."
    @Test func rippleOverlapsHandoffButOnlyKeepsFadingOut() {
        let rippleEnd = LaunchRevealTimeline.rippleStart + LaunchRevealTimeline.rippleDuration
        #expect(rippleEnd > LaunchRevealTimeline.crossfadeStart, "this test documents the overlap — update it if the numbers change")
        var previous = Double.infinity
        for ms in stride(from: LaunchRevealTimeline.crossfadeStart, through: rippleEnd, by: 10) {
            let opacity = LaunchRevealTimeline.frame(atElapsedMS: ms).rippleOpacity
            #expect(opacity <= previous + 0.0001)
            previous = opacity
        }
    }

    // MARK: - Hand-off (760ms start, 240ms long, fade + scale to 1.06)

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
        #expect(abs(LaunchRevealTimeline.handoffScale(atElapsedMS: end) - 1.06) < 0.001)
    }

    @Test func handoffScaleIsMonotonicDuringItsWindow() {
        var previous = LaunchRevealTimeline.handoffScale(atElapsedMS: LaunchRevealTimeline.crossfadeStart)
        for ms in stride(from: LaunchRevealTimeline.crossfadeStart, through: LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration, by: 10) {
            let scale = LaunchRevealTimeline.handoffScale(atElapsedMS: ms)
            #expect(scale >= previous - 0.0001)
            previous = scale
        }
    }

    @Test func totalRevealIsAboutOneSecond() {
        let handoffEnd = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(abs(handoffEnd - 1000) <= 50)
    }

    // MARK: - Hard cap (1200ms regardless)

    @Test func overlayIsGoneAtAndBeyondTheHardCap() {
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS) == 0)
        #expect(LaunchRevealTimeline.overlayOpacity(atElapsedMS: LaunchRevealTimeline.hardCapMS + 5000) == 0)
    }

    @Test func hardCapIsAtOrAfterEveryOtherStageEnds() {
        let handoffEnd = LaunchRevealTimeline.crossfadeStart + LaunchRevealTimeline.crossfadeDuration
        #expect(LaunchRevealTimeline.hardCapMS >= handoffEnd)
        let rippleEnd = LaunchRevealTimeline.rippleStart + LaunchRevealTimeline.rippleDuration
        #expect(LaunchRevealTimeline.hardCapMS >= rippleEnd)
        for start in LaunchRevealTimeline.arcPulseStarts {
            #expect(LaunchRevealTimeline.hardCapMS >= start + LaunchRevealTimeline.arcPulseDuration)
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
