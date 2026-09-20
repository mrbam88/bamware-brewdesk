import BrewDeskKit
import Foundation

/// The cold-launch reveal's stage timing, as a pure function of elapsed
/// milliseconds — no `View`, no `Timer`, no `Task`. `LaunchRevealView`
/// samples this every frame (via `TimelineView`) to get the
/// `BrewDeskMarkStage` it hands to `BrewDeskMark`; this type owns none of
/// the scheduling, only "what should it look like at time t," which is
/// what makes it unit-testable without booting a view.
///
/// ## bamware-brewdesk#205: additive signal pulse (replaces #193's "draw on")
///
/// Bilal on TestFlight build 23 (which shipped #195/#193's timeline): "the
/// animation is worse now. It looks like it's broken." Frame-by-frame
/// extraction confirmed why: iOS shows the *complete* static `LaunchMark`
/// for ~0.9s before this view's first frame runs (the system launch screen
/// hand-off). #193's timeline started from `BrewDeskMarkStage.hidden` —
/// body invisible, arcs untrimmed — so the mark the user was already
/// looking at visibly dimmed/vanished and redrew itself within ~4 frames.
/// On a device that reads as a flicker or a rendering bug, not a reveal.
/// You cannot "draw on" a logo the user is already looking at.
///
/// The fix: every stage below is **additive** on top of the full, static,
/// settled mark. `BrewDeskMarkStage.settled` — pixel-identical to the
/// static `LaunchMark` asset — *is* the reveal's frame 0. Nothing fades in,
/// trims in, or dims at any point before the final hand-off fade; the only
/// per-element motion is a brief outward *scale pulse*, each one settling
/// back to exactly 1 before the next begins:
///
/// - 0ms: frame 0, `== .settled`, byte-for-byte what iOS was already
///   showing.
/// - 120ms, 220ms long: the dot pulses, scale 1→1.18→1, ease-in-out.
/// - 200/290/380ms, 260ms each (90ms stagger): arc1/2/3 each pulse in turn,
///   scale 1→1.05→1 about the arcs' shared center, ease-out into the peak
///   then ease-in back to rest. Arcs are always fully drawn with their
///   final `.butt` cap throughout — no trim, no cap switching (#193's
///   round→butt snap at trim==1 was a second, smaller source of visible
///   pop this ticket also removes).
/// - 430ms, 420ms long: one ripple — a 4th ghost arc at the same center,
///   starting exactly at the outermost arc's own radius and expanding to
///   1.45× while fading from 0.45 opacity to 0, ease-out. The only element
///   that appears from partial opacity, and it only ever fades *out*; it
///   never touches the cup.
/// - Cup/handle/saucer (`bodyScale`) do not move at all before hand-off —
///   see the "no breath" spec-gap note below.
/// - 760ms, 240ms long: hand-off — the whole overlay fades 1→0
///   (`overlayOpacity`) while the mark scales 1→1.06 (`handoffScale`). The
///   dark diagonal "sweep" #193 added is gone entirely (it was a grey band
///   crossing a white cup — the second thing that read as a rendering
///   bug); nothing replaces it, the pulses above are the entire "shine."
/// - Hard cap at 1200ms regardless of the above (unchanged from #193)
///   — `LaunchRevealView` never lets this block navigation or data
///   loading.
///
/// Total reveal ≈ 1.0s (hand-off ends at 760+240 = 1000ms), well inside the
/// hard cap.
///
/// **Spec-gap decision — no "breath":** the ticket allows an optional,
/// very subtle 1→1.015→1 body "breath" over 600ms, "only if it is
/// imperceptible as flicker; if in doubt leave them still." Given this
/// entire ticket exists because a previous, much smaller-looking change
/// (a cap style snap) read as a visible glitch on a real device, any risk
/// of the breath reading as flicker is not worth it for a barely-visible
/// 1.5% wobble. `bodyScale` stays exactly 1 throughout — cup/handle/saucer
/// genuinely never move pre-hand-off.
///
/// Reduce Motion is unchanged from #193: no pulses at all, the settled
/// mark just fades out over `reducedMotionFadeDuration`.
nonisolated public enum LaunchRevealTimeline {
    /// The dot's own pulse window.
    public static let dotPulseStart: Double = 120
    public static let dotPulseDuration: Double = 220
    private static let dotPeakScale: Double = 1.18

    /// Innermost arc first (index 0), matching `BrewDeskMarkArc.index`.
    /// Each arc pulses in turn, 90ms apart.
    public static let arcPulseStarts: [Double] = [200, 290, 380]
    public static let arcPulseDuration: Double = 260
    private static let arcPeakScale: Double = 1.05

    /// The one-shot ripple: a 4th ghost arc expanding out from the
    /// outermost arc's own radius while fading out. Timing only — the
    /// actual shape/color live in `BrewDeskMark`'s `MarkFace.ripple`.
    public static let rippleStart: Double = 430
    public static let rippleDuration: Double = 420
    private static let rippleStartOpacity: Double = 0.45
    private static let ripplePeakScale: Double = 1.45

    /// Hand-off: the overlay's final fade, paired with a small scale-up on
    /// the mark itself (still vector, so it stays crisp through the
    /// scale). Replaces #193's dark diagonal sweep entirely.
    public static let crossfadeStart: Double = 760
    public static let crossfadeDuration: Double = 240
    private static let handoffPeakScale: Double = 1.06

    /// The overlay removes itself here regardless of where the timeline
    /// above has reached — it must never block navigation or data loading.
    public static let hardCapMS: Double = 1200

    /// Reduce Motion: no motion at all, the settled mark just fades out.
    public static let reducedMotionFadeDuration: Double = 250

    /// The mark's appearance at `elapsedMS` since the reveal started.
    /// Time beyond `hardCapMS` clamps to the hard cap's own frame (fully
    /// faded out via `overlayOpacity`, though this function's own output
    /// stays at rest), so a caller that forgets to stop sampling still
    /// gets a stable, harmless answer instead of a runaway value.
    ///
    /// `frame(atElapsedMS: 0) == .settled` is the load-bearing guarantee
    /// this whole ticket exists to make true — see the type's header.
    public static func frame(atElapsedMS elapsedMS: Double) -> BrewDeskMarkStage {
        let t = min(max(elapsedMS, 0), hardCapMS)

        return BrewDeskMarkStage(
            bodyScale: 1,
            dotScale: pulseScale(t, start: dotPulseStart, duration: dotPulseDuration, peak: dotPeakScale),
            arc1Scale: pulseScale(t, start: arcPulseStarts[0], duration: arcPulseDuration, peak: arcPeakScale),
            arc2Scale: pulseScale(t, start: arcPulseStarts[1], duration: arcPulseDuration, peak: arcPeakScale),
            arc3Scale: pulseScale(t, start: arcPulseStarts[2], duration: arcPulseDuration, peak: arcPeakScale),
            rippleScale: rippleScale(atElapsedMS: t),
            rippleOpacity: rippleOpacity(atElapsedMS: t)
        )
    }

    /// The overlay's own opacity (background + mark together) at
    /// `elapsedMS`. 1 = fully covering the main UI, 0 = gone. Callers
    /// should stop rendering the overlay entirely once this reaches 0
    /// (or once `elapsedMS >= hardCapMS`) rather than keep it around at
    /// zero opacity.
    public static func overlayOpacity(atElapsedMS elapsedMS: Double) -> Double {
        guard elapsedMS < hardCapMS else { return 0 }
        return 1 - progress(elapsedMS, start: crossfadeStart, duration: crossfadeDuration)
    }

    /// The mark's own extra scale during hand-off — 1.0 before it starts,
    /// climbing to 1.06 as the overlay fades out. Applied by
    /// `LaunchRevealView` as a wrapping `.scaleEffect` around the whole
    /// (already vector) `BrewDeskMark`, so the settle-then-slightly-grow
    /// motion stays crisp at every frame.
    public static func handoffScale(atElapsedMS elapsedMS: Double) -> Double {
        1 + (handoffPeakScale - 1) * progress(elapsedMS, start: crossfadeStart, duration: crossfadeDuration)
    }

    /// Reduce Motion variant: the finished mark, fading straight out with
    /// no other motion.
    public static func reducedMotionOverlayOpacity(atElapsedMS elapsedMS: Double) -> Double {
        1 - progress(elapsedMS, start: 0, duration: reducedMotionFadeDuration)
    }

    // MARK: - Ripple

    /// 0 before/after the ripple's window; fades `rippleStartOpacity` → 0,
    /// ease-out, across it.
    private static func rippleOpacity(atElapsedMS elapsedMS: Double) -> Double {
        guard elapsedMS >= rippleStart, elapsedMS <= rippleStart + rippleDuration else { return 0 }
        let p = easeOutCubic(progress(elapsedMS, start: rippleStart, duration: rippleDuration))
        return rippleStartOpacity * (1 - p)
    }

    /// 1 (the outermost arc's own radius, no jump) before/after the
    /// window; expands to `ripplePeakScale`, ease-out, across it.
    private static func rippleScale(atElapsedMS elapsedMS: Double) -> Double {
        guard elapsedMS >= rippleStart, elapsedMS <= rippleStart + rippleDuration else { return 1 }
        let p = easeOutCubic(progress(elapsedMS, start: rippleStart, duration: rippleDuration))
        return 1 + (ripplePeakScale - 1) * p
    }

    // MARK: - Per-property easing

    private static func progress(_ t: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return t >= start ? 1 : 0 }
        return min(max((t - start) / duration, 0), 1)
    }

    private static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    private static func easeInCubic(_ x: Double) -> Double {
        x * x * x
    }

    /// A symmetric additive pulse: `restValue` (1) outside `[start, start +
    /// duration]`, easing up to `peak` over the first half of the window
    /// (ease-out — fast rise, slowing into the peak) and back down to
    /// `restValue` over the second half (ease-in — slow leaving the peak,
    /// accelerating back to rest). Used for the dot and each arc
    /// (bamware-brewdesk#205) — every element this drives is fully drawn
    /// and at rest both before its own window starts and after it ends, so
    /// there's no "hidden" state to interpolate from, unlike #193's trim/
    /// opacity ramps.
    private static func pulseScale(_ t: Double, start: Double, duration: Double, peak: Double, restValue: Double = 1) -> Double {
        guard duration > 0 else { return restValue }
        let elapsed = t - start
        guard elapsed > 0, elapsed < duration else { return restValue }
        let half = duration / 2
        if elapsed < half {
            return restValue + (peak - restValue) * easeOutCubic(elapsed / half)
        }
        let fallProgress = (elapsed - half) / half
        return peak - (peak - restValue) * easeInCubic(fallProgress)
    }
}
