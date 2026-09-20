import Observation
import SwiftUI
import UIKit
import VenueKit

/// On-simulator frame-timing evidence for the map (brewdesk#54).
///
/// A `CADisplayLink` on the main run loop measures the delta between vsync
/// callbacks; a frame that takes >1.5× its nominal duration counts as a hitch
/// and its overshoot accumulates into hitch time. The HUD publishes a
/// machine-readable summary once per 30 frames so publishing never contends
/// with the frames being measured.
///
/// Inert in every normal launch: the HUD only renders when the process was
/// launched with `-UITestFrameStats` (UI tests and manual profiling).
@Observable
final class FrameStatsRecorder {
    /// `key=value` pairs joined by `;` — parsed by MapPerformanceUITests.
    private(set) var summary = "fps=0.0;hitchRatio=0.0000;hitches=0;frames=0;worstMs=0.0;planMs=0.0;planWorstMs=0.0;planCalls=0;churn=0"

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var hitchTime: CFTimeInterval = 0
    @ObservationIgnored private var totalTime: CFTimeInterval = 0
    @ObservationIgnored private var worstFrameMs: Double = 0
    // bd#211: `MapAnnotationPlanner.plan(...)` call-site evidence — recorded
    // by `CafeMapScreen.cachedPlan()`, not this file, but published through
    // the same HUD label so a UI test's existing `hud.label` read already
    // carries it (no separate accessibility seam needed). `churn` is the
    // total count of marker identities (pin/dot/cluster ids) that entered or
    // left the rendered set across every re-plan in the scoped window — the
    // number this PR's fix set out to shrink.
    @ObservationIgnored private var planCalls = 0
    @ObservationIgnored private var planTotalMs: Double = 0
    @ObservationIgnored private var planWorstMs: Double = 0
    @ObservationIgnored private var identityChurnTotal = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Zero the counters so a test can scope measurement to a scripted pan.
    func reset() {
        frames = 0
        hitches = 0
        hitchTime = 0
        totalTime = 0
        worstFrameMs = 0
        lastTimestamp = nil
        planCalls = 0
        planTotalMs = 0
        planWorstMs = 0
        identityChurnTotal = 0
        publish()
    }

    /// Records one `MapAnnotationPlanner.plan(...)` call's cost and how many
    /// marker identities changed as a result (bd#211 diagnostic).
    func recordPlan(elapsedMs: Double, changedIDs: Int) {
        planCalls += 1
        planTotalMs += elapsedMs
        planWorstMs = max(planWorstMs, elapsedMs)
        identityChurnTotal += changedIDs
        publish()
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        let delta = link.timestamp - last
        let nominal = link.targetTimestamp - link.timestamp
        guard nominal > 0 else { return }
        frames += 1
        totalTime += delta
        worstFrameMs = max(worstFrameMs, delta * 1000)
        if delta > nominal * 1.5 {
            hitches += 1
            hitchTime += delta - nominal
        }
        if frames % 30 == 0 { publish() }
    }

    private func publish() {
        let fps = totalTime > 0 ? Double(frames) / totalTime : 0
        let ratio = totalTime > 0 ? hitchTime / totalTime : 0
        let planAvg = planCalls > 0 ? planTotalMs / Double(planCalls) : 0
        summary = String(
            format: "fps=%.1f;hitchRatio=%.4f;hitches=%d;frames=%d;worstMs=%.1f;planMs=%.2f;planWorstMs=%.2f;planCalls=%d;churn=%d",
            fps, ratio, hitches, frames, worstFrameMs, planAvg, planWorstMs, planCalls, identityChurnTotal
        )
    }
}

/// Tiny monospaced readout in the map's corner. Tap to zero the counters.
struct MapFrameStatsHUD: View {
    /// Computed once; normal launches never construct the HUD.
    static let isEnabled = LaunchEnvironment.current.frameStats
    /// Shared across the HUD (frame timing) and `CafeMapScreen.cachedPlan()`
    /// (plan-timing/churn) — bd#211's evidence needs one recorder both write
    /// to, not two isolated ones, and only one `CafeMapScreen`/HUD pair is
    /// ever on screen at a time in the UI-test harness this backs.
    static let shared = FrameStatsRecorder()

    let annotationCount: Int

    var body: some View {
        Text(verbatim: "\(Self.shared.summary);annotations=\(annotationCount)")
            .font(.system(size: 9, design: .monospaced))
            .padding(6)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.green)
            .onTapGesture { Self.shared.reset() }
            .accessibilityIdentifier("frame-stats")
            .accessibilityAddTraits(.isButton)
            .onAppear { Self.shared.start() }
            .onDisappear { Self.shared.stop() }
    }
}
