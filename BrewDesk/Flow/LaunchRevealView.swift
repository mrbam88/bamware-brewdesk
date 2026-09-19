import BrewDeskKit
import SwiftUI

/// A purely cosmetic overlay shown once, on cold launch, on top of the
/// already-rendered main UI: the static system launch screen (white
/// `LaunchMark` on `LaunchBackground`, from `UILaunchScreen` in
/// `BrewDesk-*-Info.plist`) hands off into this view's frame 0, which draws
/// the same mark at the same size/position/colors before animating it in
/// (bamware-brewdesk#186). It never gates anything: `RootView` mounts the
/// real UI underneath at the same time, so onboarding, location prompts,
/// and data loading all proceed on their own regardless of whether this
/// view is still fading out.
///
/// Driven by `TimelineView(.animation)` sampling the pure
/// `LaunchRevealTimeline` every frame — no `Timer`, no `Task.sleep` chain
/// to cancel. Once `onFinished()` fires, `RootView` removes this view from
/// the hierarchy, which stops `TimelineView` invalidating on its own; there
/// is nothing left running after that.
struct LaunchRevealView: View {
    var tint: Color = .white
    /// Screenshot-capture seam (bamware-brewdesk#193,
    /// `-UITestFreezeLaunchRevealAtMS`) — when set, the reveal renders this
    /// exact elapsed time forever instead of advancing with the clock, and
    /// never calls `onFinished()`. `nil` for every real launch.
    var frozenElapsedMS: Double? = nil
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var hasFinished = false

    /// The static launch screen's `LaunchMark` is shown by `UILaunchScreen`
    /// at its native, unscaled point size (`LaunchMark.png`, the @1x
    /// asset) — 120×145pt — centered on screen. Matching that size exactly
    /// is what makes this view's frame 0 pixel-identical to what iOS was
    /// already showing.
    private static let markSize = CGSize(width: 120, height: 145)

    var body: some View {
        TimelineView(.animation(paused: hasFinished || frozenElapsedMS != nil)) { context in
            let elapsedMS = frozenElapsedMS ?? (context.date.timeIntervalSince(startDate) * 1000)
            let overlayOpacity = reduceMotion
                ? LaunchRevealTimeline.reducedMotionOverlayOpacity(atElapsedMS: elapsedMS)
                : LaunchRevealTimeline.overlayOpacity(atElapsedMS: elapsedMS)
            let stage = reduceMotion ? .settled : LaunchRevealTimeline.frame(atElapsedMS: elapsedMS)
            // Hand-off (bamware-brewdesk#193): the mark itself grows very
            // slightly (1.0→1.04) as the overlay fades out. A wrapping
            // `.scaleEffect` around the whole (vector) mark, not a
            // `BrewDeskMarkStage` field — by this point in the timeline
            // every stage value is already at rest, so this is purely the
            // hand-off's own motion, not part of "what the mark looks like
            // while assembling itself."
            let handoffScale = reduceMotion ? 1.0 : LaunchRevealTimeline.handoffScale(atElapsedMS: elapsedMS)
            let showSweep = !reduceMotion && LaunchRevealTimeline.isSweepActive(atElapsedMS: elapsedMS)
            let isDone = elapsedMS >= (reduceMotion ? LaunchRevealTimeline.reducedMotionFadeDuration : LaunchRevealTimeline.hardCapMS)

            ZStack {
                Color("LaunchBackground")
                ZStack {
                    BrewDeskMark(tint: tint, mode: .stage(stage), isAnimated: true)
                    if showSweep {
                        LaunchSweep(
                            size: Self.markSize,
                            progress: LaunchRevealTimeline.sweepOpacityProgress(atElapsedMS: elapsedMS)
                        )
                    }
                }
                .frame(width: Self.markSize.width, height: Self.markSize.height)
                .scaleEffect(handoffScale)
            }
            .ignoresSafeArea()
            .opacity(overlayOpacity)
            .allowsHitTesting(overlayOpacity > 0)
            // Not `.accessibilityHidden` — kept inspectable (by identifier
            // only, no label) so `LaunchRevealUITests` can assert it's gone
            // within the promised window instead of just trusting a timer.
            .accessibilityIdentifier("launch-reveal-overlay")
            .task(id: isDone) {
                guard frozenElapsedMS == nil, isDone, !hasFinished else { return }
                hasFinished = true
                onFinished()
            }
        }
    }
}

/// The single specular light sweep near the end of the reveal
/// (bamware-brewdesk#193): a soft diagonal band traveling bottom-left →
/// top-right across the mark, once. Built from a rotated `LinearGradient`
/// masked to the mark's own silhouette — no rasterized image, so it stays
/// crisp regardless of size, and since neither the gradient nor the mask
/// scales during the reveal, it has no bearing on the "nothing that scales
/// gets rasterized" rule the settling body/arcs/dot follow.
///
/// Spec-gap decision: the ticket describes this as a white gradient band.
/// `LaunchRevealView` renders the mark in pure `.white` (matching the
/// static `LaunchMark` asset exactly, per its own doc comment) — a white
/// highlight masked on top of already-fully-white shapes is invisible;
/// alpha compositing can't push a color brighter than its own opaque
/// value. This draws the "shine" the other way around instead: a soft
/// dark vignette flanks a thin untouched gap, so the gap — full, untouched
/// white — reads as a bright streak by contrast with its own briefly
/// dimmed surroundings as it travels. Same read ("a moment of light
/// crossing the mark, once"), same softness, same direction; achievable
/// within a pure-white glyph.
///
/// Uses `.settled` as its mask shape rather than the live `stage`: by the
/// time the sweep window opens (680ms), the mark has already finished
/// drawing (arcs complete at 660ms), so the settled silhouette is what's
/// actually on screen.
private struct LaunchSweep: View {
    let size: CGSize
    /// 0 = band fully off past the bottom-left corner, 1 = fully off past
    /// the top-right corner (already eased — see
    /// `LaunchRevealTimeline.sweepOpacityProgress`).
    let progress: Double

    var body: some View {
        let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
        let bandWidth = diagonal * 0.35
        let travel = diagonal + bandWidth * 2
        let offset = travel * progress - travel / 2
        let dim = Color.black.opacity(0.22)

        LinearGradient(
            stops: [
                .init(color: dim.opacity(0), location: 0.00),
                .init(color: dim, location: 0.32),
                .init(color: dim.opacity(0), location: 0.47),
                .init(color: dim.opacity(0), location: 0.53),
                .init(color: dim, location: 0.68),
                .init(color: dim.opacity(0), location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth, height: diagonal * 1.5)
        .rotationEffect(.degrees(-45))
        .offset(x: offset, y: -offset)
        .frame(width: size.width, height: size.height)
        .mask(BrewDeskMark(tint: .white, mode: .settled, isAnimated: false))
        .allowsHitTesting(false)
    }
}

#Preview {
    LaunchRevealView(onFinished: {})
}
