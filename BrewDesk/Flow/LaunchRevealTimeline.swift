import BrewDeskKit
import Foundation

/// The cold-launch reveal's stage timing, as a pure function of elapsed
/// milliseconds — no `View`, no `Timer`, no `Task`. `LaunchRevealView`
/// samples this every frame (via `TimelineView`) to get the
/// `BrewDeskMarkStage` it hands to `BrewDeskMark`; this type owns none of
/// the scheduling, only "what should it look like at time t," which is
/// what makes it unit-testable without booting a view.
///
/// Timeline (bamware-brewdesk#186 design spec):
/// - 0–350ms: body (saucer/cup/handle) settles in, opacity 0→1, scale
///   0.96→1.0 with a slight spring overshoot.
/// - 300ms, 180ms long: the dot pops, scale 0→1.15→1.
/// - 380/470/560ms, 260ms each: arcs 1/2/3 draw on via trim, ease-out.
/// - 780ms, 300ms long: one shared glow pulse across the arcs.
/// - 950ms, 200ms long: the whole mark crossfades out.
/// - Hard cap at 1200ms regardless of the above.
nonisolated public enum LaunchRevealTimeline {
    public static let bodySettleStart: Double = 0
    public static let bodySettleDuration: Double = 350

    public static let dotPopStart: Double = 300
    public static let dotPopDuration: Double = 180

    /// Innermost arc first (index 0), matching `BrewDeskMarkArc.index`.
    public static let arcStarts: [Double] = [380, 470, 560]
    public static let arcDuration: Double = 260

    public static let glowStart: Double = 780
    public static let glowDuration: Double = 300
    public static let glowPeakOpacity: Double = 0.35

    public static let crossfadeStart: Double = 950
    public static let crossfadeDuration: Double = 200

    /// The overlay removes itself here regardless of where the timeline
    /// above has reached — it must never block navigation or data loading.
    public static let hardCapMS: Double = 1200

    /// Reduce Motion: no motion at all, the settled mark just fades out.
    public static let reducedMotionFadeDuration: Double = 250

    /// The mark's appearance at `elapsedMS` since the reveal started.
    /// Time beyond `hardCapMS` clamps to the hard cap's own frame (fully
    /// faded out), so a caller that forgets to stop sampling still gets a
    /// stable, harmless answer instead of a runaway value.
    public static func frame(atElapsedMS elapsedMS: Double) -> BrewDeskMarkStage {
        let t = min(max(elapsedMS, 0), hardCapMS)

        let bodyProgress = progress(t, start: bodySettleStart, duration: bodySettleDuration)
        let dotProgress = progress(t, start: dotPopStart, duration: dotPopDuration)
        let arcProgress = arcStarts.map { progress(t, start: $0, duration: arcDuration) }
        let glowProgress = progress(t, start: glowStart, duration: glowDuration)
        let crossfadeProgress = progress(t, start: crossfadeStart, duration: crossfadeDuration)

        var stage = BrewDeskMarkStage(
            bodyOpacity: bodyProgress,
            bodyScale: bodyScale(bodyProgress),
            dotScale: dotScale(dotProgress),
            arc1Trim: arcProgress[0],
            arc2Trim: arcProgress[1],
            arc3Trim: arcProgress[2],
            glowOpacity: glowPeakOpacity * sin(.pi * glowProgress)
        )

        // The crossfade is a whole-mark fade, layered on top of whatever
        // the stage above already computed — represented here as an extra
        // multiply on the two opacity channels rather than a separate
        // `Stage` field, since `LaunchRevealView` also needs to fade the
        // background color, which isn't part of `BrewDeskMarkStage` at all
        // (see `LaunchRevealView.overlayOpacity(atElapsedMS:)`).
        let fade = 1 - crossfadeProgress
        stage.bodyOpacity *= fade
        stage.glowOpacity *= fade
        return stage
    }

    /// The overlay's own opacity (background + mark together) at
    /// `elapsedMS`. 1 = fully covering the main UI, 0 = gone. Callers
    /// should stop rendering the overlay entirely once this reaches 0
    /// (or once `elapsedMS >= hardCapMS`) rather than keep it around at
    /// zero opacity.
    public static func overlayOpacity(atElapsedMS elapsedMS: Double) -> Double {
        guard elapsedMS < hardCapMS else { return 0 }
        let crossfadeProgress = progress(elapsedMS, start: crossfadeStart, duration: crossfadeDuration)
        return 1 - crossfadeProgress
    }

    /// Reduce Motion variant: the finished mark, fading straight out with
    /// no other motion.
    public static func reducedMotionOverlayOpacity(atElapsedMS elapsedMS: Double) -> Double {
        1 - progress(elapsedMS, start: 0, duration: reducedMotionFadeDuration)
    }

    // MARK: - Per-property easing

    private static func progress(_ t: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return t >= start ? 1 : 0 }
        return min(max((t - start) / duration, 0), 1)
    }

    /// 0.96 → 1.0 with a small overshoot past 1.0 before settling — the
    /// "slight overshoot" spring the design spec calls for, expressed as a
    /// plain function of progress rather than a physical spring so it can
    /// be evaluated (and tested) at any instant without integrating a
    /// differential equation.
    private static func bodyScale(_ progress: Double) -> Double {
        let overshoot = easeOutBack(progress)
        return 0.96 + 0.04 * overshoot
    }

    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let shifted = x - 1
        return 1 + c3 * shifted * shifted * shifted + c1 * shifted * shifted
    }

    /// 0 → 1.15 over the first 60% of the pop, then settles 1.15 → 1.0.
    private static func dotScale(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress < 0.6 {
            return (progress / 0.6) * 1.15
        }
        let settle = (progress - 0.6) / 0.4
        return 1.15 - 0.15 * settle
    }
}
