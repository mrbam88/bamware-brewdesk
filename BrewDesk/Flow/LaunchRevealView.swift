import BrewDeskKit
import SwiftUI

/// A purely cosmetic overlay shown once, on cold launch, on top of the
/// already-rendered main UI: the static system launch screen (white
/// `LaunchMark` on `LaunchBackground`, from `UILaunchScreen` in
/// `BrewDesk-*-Info.plist`) hands off into this view's frame 0, which is
/// `BrewDeskMarkStage.settled` — pixel-identical to that static mark — and
/// only ever *adds* motion on top of it from there (bamware-brewdesk#205;
/// see `LaunchRevealTimeline`'s header for why the previous "draw on"
/// design, #186/#193, read as broken on a device). It never gates
/// anything: `RootView` mounts the real UI underneath at the same time, so
/// onboarding, location prompts, and data loading all proceed on their own
/// regardless of whether this view is still fading out.
///
/// Driven by `TimelineView(.animation)` sampling the pure
/// `LaunchRevealTimeline` every frame — no `Timer`, no `Task.sleep` chain
/// to cancel. Once `onFinished()` fires, `RootView` removes this view from
/// the hierarchy, which stops `TimelineView` invalidating on its own; there
/// is nothing left running after that.
///
/// ## bamware-brewdesk#207: the clock starts at *presentation*, not init
///
/// #205 fixed what the reveal draws (nothing hidden, everything additive).
/// A real-speed recording afterwards showed the fix wasn't enough: this
/// view timed itself from `startDate = Date()`, evaluated when the view's
/// `@State` is first installed — essentially `onAppear` time. On a cold
/// launch the main thread is still busy well past that point (map setup,
/// data loading), so the entire 120–860ms pulse window elapsed against the
/// clock *before* the first frame actually reached the screen — the user
/// saw the static mark, then only the tail end of the hand-off fade. The
/// pulses were computed the whole time; they just never got presented.
///
/// `presentedStartDate` fixes this: it starts `nil`, which holds the
/// timeline at `elapsedMS == 0` (`.settled` — still pixel-identical to the
/// static launch image, so nothing is wrong to look at while waiting), and
/// is only set once from the one-shot `.task` below, after yielding twice
/// and a further 50ms — by construction that `Task` cannot resume until
/// the main run loop is actually free to service it, so on a busy cold
/// launch it naturally waits out the congestion instead of firing on a
/// stale clock. Every stage in `LaunchRevealTimeline` is then measured
/// from *that* timestamp, not from `appearDate`.
struct LaunchRevealView: View {
    var tint: Color = .white
    /// Screenshot-capture seam (bamware-brewdesk#193,
    /// `-UITestFreezeLaunchRevealAtMS`) — when set, the reveal renders this
    /// exact elapsed time forever instead of advancing with the clock, and
    /// never calls `onFinished()`. `nil` for every real launch.
    var frozenElapsedMS: Double? = nil
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When `onAppear` actually ran — used only for `absoluteSafetyCapMS`
    /// below, never for the reveal's own stage timing.
    @State private var appearDate = Date()
    /// `nil` until the one-shot `.task` below has confirmed the main run
    /// loop is free (bamware-brewdesk#207) — every stage in
    /// `LaunchRevealTimeline` is measured from this timestamp once set.
    @State private var presentedStartDate: Date? = nil
    @State private var hasFinished = false

    /// The static launch screen's `LaunchMark` is shown by `UILaunchScreen`
    /// at its native, unscaled point size (`LaunchMark.png`, the @1x
    /// asset) — 120×145pt — centered on screen. Matching that size exactly
    /// is what makes this view's frame 0 pixel-identical to what iOS was
    /// already showing.
    private static let markSize = CGSize(width: 120, height: 145)

    /// A coarser, independent ceiling (bamware-brewdesk#207) measured from
    /// `appearDate`, not `presentedStartDate` — guards the case where a
    /// presented start somehow never arrives (e.g. the run loop never
    /// frees up), so the overlay still cannot get stuck forever the way it
    /// could have before this fix existed. `LaunchRevealTimeline
    /// .hardCapMS` (1.2s) is the normal ceiling, measured from the
    /// presented start once established; this is the backstop for before
    /// that point.
    private static let absoluteSafetyCapMS: Double = 2500

    var body: some View {
        TimelineView(.animation(paused: hasFinished || frozenElapsedMS != nil)) { context in
            let elapsedMS = frozenElapsedMS ?? presentedElapsedMS(at: context.date)
            let overlayOpacity = reduceMotion
                ? LaunchRevealTimeline.reducedMotionOverlayOpacity(atElapsedMS: elapsedMS)
                : LaunchRevealTimeline.overlayOpacity(atElapsedMS: elapsedMS)
            let stage = reduceMotion ? .settled : LaunchRevealTimeline.frame(atElapsedMS: elapsedMS)
            // Hand-off (bamware-brewdesk#193, timing updated in #205/#207):
            // the mark itself grows very slightly (1.0→1.06) as the overlay
            // fades out. A wrapping `.scaleEffect` around the whole
            // (vector) mark, not a `BrewDeskMarkStage` field — by this
            // point in the timeline every stage value is already at rest,
            // so this is purely the hand-off's own motion, not part of
            // "what the mark looks like while pulsing."
            let handoffScale = reduceMotion ? 1.0 : LaunchRevealTimeline.handoffScale(atElapsedMS: elapsedMS)
            let absoluteElapsedMS = context.date.timeIntervalSince(appearDate) * 1000
            let hardCap = reduceMotion ? LaunchRevealTimeline.reducedMotionFadeDuration : LaunchRevealTimeline.hardCapMS
            let isDone = frozenElapsedMS == nil && (elapsedMS >= hardCap || absoluteElapsedMS >= Self.absoluteSafetyCapMS)

            ZStack {
                Color("LaunchBackground")
                BrewDeskMark(tint: tint, mode: .stage(stage), isAnimated: true)
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
        .onAppear { appearDate = Date() }
        .task {
            await establishPresentedStart()
        }
    }

    private func presentedElapsedMS(at date: Date) -> Double {
        guard let start = presentedStartDate else { return 0 }
        return date.timeIntervalSince(start) * 1000
    }

    /// Runs once per view identity (bamware-brewdesk#207). Two `Task
    /// .yield()`s plus a short, fixed `Task.sleep` — each of these can
    /// only resume once the main run loop is actually free to service
    /// them, so on a cold launch where the main thread is still busy with
    /// map/data setup, this `Task` simply doesn't resume until that
    /// congestion clears, which is exactly the signal we need ("frames can
    /// now actually be presented"). The fixed sleep adds margin beyond the
    /// first free run-loop turn so the *first* pulse-bearing frame this
    /// produces has a real chance of being composited, not just scheduled.
    private func establishPresentedStart() async {
        guard frozenElapsedMS == nil else { return }
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, presentedStartDate == nil else { return }
        presentedStartDate = Date()
    }
}

#Preview {
    LaunchRevealView(onFinished: {})
}
