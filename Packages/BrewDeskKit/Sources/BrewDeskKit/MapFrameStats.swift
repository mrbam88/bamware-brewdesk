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
    private(set) var summary = "fps=0.0;hitchRatio=0.0000;hitches=0;frames=0;worstMs=0.0"

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var hitchTime: CFTimeInterval = 0
    @ObservationIgnored private var totalTime: CFTimeInterval = 0
    @ObservationIgnored private var worstFrameMs: Double = 0

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
        summary = String(
            format: "fps=%.1f;hitchRatio=%.4f;hitches=%d;frames=%d;worstMs=%.1f",
            fps, ratio, hitches, frames, worstFrameMs
        )
    }
}

/// Tiny monospaced readout in the map's corner. Tap to zero the counters.
struct MapFrameStatsHUD: View {
    /// Computed once; normal launches never construct the HUD.
    static let isEnabled = LaunchEnvironment.current.frameStats

    let annotationCount: Int
    @State private var recorder = FrameStatsRecorder()

    var body: some View {
        Text(verbatim: "\(recorder.summary);annotations=\(annotationCount)")
            .font(.system(size: 9, design: .monospaced))
            .padding(6)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.green)
            .onTapGesture { recorder.reset() }
            .accessibilityIdentifier("frame-stats")
            .accessibilityAddTraits(.isButton)
            .onAppear { recorder.start() }
            .onDisappear { recorder.stop() }
    }
}
