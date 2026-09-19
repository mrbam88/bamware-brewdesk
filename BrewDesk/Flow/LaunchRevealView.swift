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
        TimelineView(.animation(paused: hasFinished)) { context in
            let elapsedMS = context.date.timeIntervalSince(startDate) * 1000
            let overlayOpacity = reduceMotion
                ? LaunchRevealTimeline.reducedMotionOverlayOpacity(atElapsedMS: elapsedMS)
                : LaunchRevealTimeline.overlayOpacity(atElapsedMS: elapsedMS)
            let stage = reduceMotion ? .settled : LaunchRevealTimeline.frame(atElapsedMS: elapsedMS)
            let isDone = elapsedMS >= (reduceMotion ? LaunchRevealTimeline.reducedMotionFadeDuration : LaunchRevealTimeline.hardCapMS)

            ZStack {
                Color("LaunchBackground")
                BrewDeskMark(tint: tint, mode: .stage(stage), isAnimated: true)
                    .frame(width: Self.markSize.width, height: Self.markSize.height)
            }
            .ignoresSafeArea()
            .opacity(overlayOpacity)
            .allowsHitTesting(overlayOpacity > 0)
            // Not `.accessibilityHidden` — kept inspectable (by identifier
            // only, no label) so `LaunchRevealUITests` can assert it's gone
            // within the promised window instead of just trusting a timer.
            .accessibilityIdentifier("launch-reveal-overlay")
            .task(id: isDone) {
                guard isDone, !hasFinished else { return }
                hasFinished = true
                onFinished()
            }
        }
    }
}

#Preview {
    LaunchRevealView(onFinished: {})
}
