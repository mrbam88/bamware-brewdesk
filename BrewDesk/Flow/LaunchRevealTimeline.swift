import BrewDeskKit
import Foundation

/// The cold-launch reveal's stage timing, as a pure function of elapsed
/// milliseconds — no `View`, no `Timer`, no `Task`. `LaunchRevealView`
/// samples this every frame (via `TimelineView`) to get the
/// `BrewDeskMarkStage` it hands to `BrewDeskMark`; this type owns none of
/// the scheduling, only "what should it look like at time t," which is
/// what makes it unit-testable without booting a view.
///
/// Timeline (bamware-brewdesk#193 polish pass over #186's original):
/// - 0–320ms: body (saucer/cup/handle) settles in, opacity 0→1, scale
///   0.97→1.0, both eased through `.timingCurve(0.2, 0.9, 0.3, 1.0)` — a
///   tight curve with no overshoot (#186's spring `easeOutBack` bounce is
///   gone).
/// - 250ms, 140ms long: the dot pops, scale 0→1.08→1 (was 0→1.15→1 over
///   180ms — smaller, quicker).
/// - 300/370/440ms, 220ms each (70ms stagger): arcs 1/2/3 draw on via trim,
///   ease-out. Mark fully drawn by 660ms.
/// - 680ms, 380ms long: one specular light sweep crosses the settled mark,
///   ease-in-out — replaces #186's shared arc glow pulse with a single more
///   deliberate "shine" moment (`LaunchRevealView.LaunchSweep`; masked to
///   the mark's own shape there, not represented in `BrewDeskMarkStage`).
/// - 900ms, 220ms long: the whole overlay fades out while the mark scales
///   1.0→1.04 (hand-off — was a plain 950/200ms crossfade with no scale).
/// - Hard cap at 1200ms regardless of the above.
nonisolated public enum LaunchRevealTimeline {
    public static let bodySettleStart: Double = 0
    public static let bodySettleDuration: Double = 320
    private static let bodyStartScale: Double = 0.97
    private static let bodyEase = CubicBezierEase(x1: 0.2, y1: 0.9, x2: 0.3, y2: 1.0)

    public static let dotPopStart: Double = 250
    public static let dotPopDuration: Double = 140
    private static let dotPeakScale: Double = 1.08

    /// Innermost arc first (index 0), matching `BrewDeskMarkArc.index`.
    public static let arcStarts: [Double] = [300, 370, 440]
    public static let arcDuration: Double = 220

    /// The light sweep's window — see `LaunchRevealView.LaunchSweep`, which
    /// owns the actual visual (a masked, translating gradient band). This
    /// type only owns the timing: when it's active and how far through its
    /// own ease-in-out it is.
    public static let sweepStart: Double = 680
    public static let sweepDuration: Double = 380

    /// Hand-off: the overlay's final fade, paired with a small scale-up on
    /// the mark itself (still vector, so it stays crisp through the scale).
    public static let crossfadeStart: Double = 900
    public static let crossfadeDuration: Double = 220
    private static let handoffPeakScale: Double = 1.04

    /// The overlay removes itself here regardless of where the timeline
    /// above has reached — it must never block navigation or data loading.
    public static let hardCapMS: Double = 1200

    /// Reduce Motion: no motion at all, the settled mark just fades out.
    public static let reducedMotionFadeDuration: Double = 250

    /// The mark's appearance at `elapsedMS` since the reveal started.
    /// Time beyond `hardCapMS` clamps to the hard cap's own frame (fully
    /// faded out), so a caller that forgets to stop sampling still gets a
    /// stable, harmless answer instead of a runaway value.
    ///
    /// `glowOpacity` is always 0 here — #186's shared arc glow pulse was
    /// replaced by the light sweep (`sweepOpacityProgress`, below), which
    /// isn't part of `BrewDeskMarkStage` since it's a full-mark overlay
    /// effect, not a per-arc one. The field stays on `BrewDeskMarkStage`
    /// itself for API stability (other modes may still want it).
    public static func frame(atElapsedMS elapsedMS: Double) -> BrewDeskMarkStage {
        let t = min(max(elapsedMS, 0), hardCapMS)

        let bodyProgress = bodyEase.solve(progress(t, start: bodySettleStart, duration: bodySettleDuration))
        let dotProgress = progress(t, start: dotPopStart, duration: dotPopDuration)
        let arcProgress = arcStarts.map { easeOutCubic(progress(t, start: $0, duration: arcDuration)) }

        var stage = BrewDeskMarkStage(
            bodyOpacity: bodyProgress,
            bodyScale: bodyStartScale + (1 - bodyStartScale) * bodyProgress,
            dotScale: dotScale(dotProgress),
            arc1Trim: arcProgress[0],
            arc2Trim: arcProgress[1],
            arc3Trim: arcProgress[2],
            glowOpacity: 0
        )

        // The hand-off fade is a whole-mark fade, layered on top of whatever
        // the stage above already computed — represented here as an extra
        // multiply on the opacity channel rather than a separate `Stage`
        // field, since `LaunchRevealView` also needs to fade the background
        // color, which isn't part of `BrewDeskMarkStage` at all (see
        // `overlayOpacity(atElapsedMS:)`).
        let fade = 1 - progress(t, start: crossfadeStart, duration: crossfadeDuration)
        stage.bodyOpacity *= fade
        return stage
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
    /// climbing to 1.04 as the overlay fades out. Applied by
    /// `LaunchRevealView` as a wrapping `.scaleEffect` around the whole
    /// (already vector) `BrewDeskMark`, so the settle-then-slightly-grow
    /// motion stays crisp at every frame.
    public static func handoffScale(atElapsedMS elapsedMS: Double) -> Double {
        1 + (handoffPeakScale - 1) * progress(elapsedMS, start: crossfadeStart, duration: crossfadeDuration)
    }

    /// The light sweep's own ease-in-out progress (0...1) across its
    /// `sweepStart`/`sweepDuration` window — 0 before it starts, 1 once
    /// it's swept fully past. `LaunchRevealView` only shows the sweep
    /// view while this is strictly between its start and end.
    public static func sweepOpacityProgress(atElapsedMS elapsedMS: Double) -> Double {
        smoothstep(progress(elapsedMS, start: sweepStart, duration: sweepDuration))
    }

    public static func isSweepActive(atElapsedMS elapsedMS: Double) -> Bool {
        elapsedMS >= sweepStart && elapsedMS <= sweepStart + sweepDuration
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

    private static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    private static func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// 0 → 1.08 over the first 60% of the pop, then settles 1.08 → 1.0.
    private static func dotScale(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress < 0.6 {
            return (progress / 0.6) * dotPeakScale
        }
        let settle = (progress - 0.6) / 0.4
        return dotPeakScale - (dotPeakScale - 1) * settle
    }
}

/// A CSS/SwiftUI-style cubic Bezier easing curve — the same shape
/// `.timingCurve(x1, y1, x2, y2)` draws, expressed as a pure `x -> y`
/// function so `LaunchRevealTimeline` can sample it at any instant without
/// an actual SwiftUI animation running. `x` is elapsed-fraction (0...1) and
/// doubles as the curve's own parametric `x`; `y` is the eased output
/// (0...1 as long as both control points' `y`s are, which they are for the
/// curve this file uses — control points are a convex combination bound, so
/// the curve never overshoots past its own control `y`s).
nonisolated struct CubicBezierEase {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// Newton-Raphson on the parametric `x(t) = fraction`, then evaluates
    /// `y(t)`. 8 iterations is comfortably more than enough for a curve
    /// this well-conditioned (monotonic x1/x2 in (0, 1)) to converge to
    /// sub-pixel precision.
    func solve(_ fraction: Double) -> Double {
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return 1 }
        var t = fraction
        for _ in 0..<8 {
            let currentX = bezier(t, x1, x2) - fraction
            let d = derivative(t, x1, x2)
            guard abs(d) > 1e-6 else { break }
            t -= currentX / d
            t = min(max(t, 0), 1)
        }
        return bezier(t, y1, y2)
    }

    private func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
    }

    private func derivative(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }
}
