import Observation
import SwiftUI
import UIKit
import VenueKit

/// Work counters and the measurement window for the map pan metric
/// (brewdesk#211). Plain unobserved storage: bumping a counter from a view
/// body never invalidates anything. Every entry point is a no-op unless the
/// process was launched with `-UITestFrameStats`.
///
/// The window is what makes the metric repeatable: frames count only from
/// the first map gesture after a reset until `windowTail` seconds after the
/// last one, so the idle time XCUITest spends between and after gestures
/// (which varied 2-3x run to run and wrecked the old hitch RATIO) is not in
/// the numbers at all.
@MainActor
final class MapPerfProbe {
    static let shared = MapPerfProbe()
    static let isEnabled = LaunchEnvironment.current.frameStats
    /// Seconds after the last gesture ends that still count: long enough
    /// for the camera to come to rest, the settle re-plan to land, and the
    /// auto-load that follows a rest (400 ms debounce, bd#267) to answer.
    /// At 0.5 s that last answer fell on either side of the edge.
    static let windowTail: CFTimeInterval = 1.0

    /// Evaluations of the view body that builds the `Map` content.
    private(set) var mapBodyEvals = 0
    /// Evaluations of `CafeMapScreen.body` (header, shelf, overlays).
    private(set) var screenBodyEvals = 0
    /// Marker plans actually computed (cache misses), not cache hits.
    private(set) var replans = 0
    private(set) var teardrops = 0
    private(set) var firstGestureStart: CFTimeInterval?
    private(set) var lastGestureEnd: CFTimeInterval?
    private(set) var gestureActive = false

    static func mapBodyEvaluated() {
        guard isEnabled else { return }
        shared.mapBodyEvals += 1
    }

    static func screenBodyEvaluated() {
        guard isEnabled else { return }
        shared.screenBodyEvals += 1
    }

    static func replanned(teardrops: Int) {
        guard isEnabled else { return }
        shared.replans += 1
        shared.teardrops = teardrops
    }

    static func gestureChanged() {
        guard isEnabled, !shared.gestureActive else { return }
        shared.gestureActive = true
        if shared.firstGestureStart == nil { shared.firstGestureStart = CACurrentMediaTime() }
    }

    static func gestureEnded() {
        guard isEnabled else { return }
        shared.gestureActive = false
        shared.lastGestureEnd = CACurrentMediaTime()
    }

    func reset() {
        mapBodyEvals = 0
        screenBodyEvals = 0
        replans = 0
        firstGestureStart = nil
        lastGestureEnd = nil
        gestureActive = false
    }

    /// True while `timestamp` falls inside the measurement window as it is
    /// known right now (its far end moves with every further gesture).
    func isInWindow(_ timestamp: CFTimeInterval) -> Bool {
        guard let firstGestureStart, timestamp >= firstGestureStart else { return false }
        if gestureActive { return true }
        guard let lastGestureEnd else { return true }
        return timestamp <= lastGestureEnd + Self.windowTail
    }
}

/// On-simulator frame-timing evidence for the map (brewdesk#54, #211).
///
/// A `CADisplayLink` on the main run loop measures the delta between vsync
/// callbacks. The headline is hitch TIME: the summed duration of every frame
/// longer than `longFrameMs` (and of those longer than `stallFrameMs`)
/// inside `MapPerfProbe`'s gesture window. An absolute number of
/// milliseconds, so it does not move when the amount of idle time around the
/// gestures does. `hitchRatio` (hitch time over ALL time since the reset) is
/// still published for continuity, but it swung 0.18-0.25 on one binary and
/// proves nothing on its own.
///
/// The HUD publishes a machine-readable summary once per 30 frames so
/// publishing never contends with the frames being measured.
///
/// Inert in every normal launch: the HUD only renders when the process was
/// launched with `-UITestFrameStats` (UI tests and manual profiling).
@MainActor
@Observable
final class FrameStatsRecorder {
    /// A frame at least this long dropped more than one 60 Hz refresh.
    static let longFrameMs = 34.0
    /// A frame at least this long is a stall anyone can see.
    static let stallFrameMs = 100.0

    /// `key=value` pairs joined by `;` — parsed by MapPerformanceUITests.
    private(set) var summary = "fps=0.0;hitchRatio=0.0000;hitches=0;frames=0;worstMs=0.0"

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var hitchTime: CFTimeInterval = 0
    @ObservationIgnored private var totalTime: CFTimeInterval = 0
    @ObservationIgnored private var worstFrameMs: Double = 0
    /// Frames longer than `longFrameMs` since the reset: when each began and
    /// how long it took. Windowed at publish time, because the window's end
    /// keeps moving until the last gesture has finished.
    @ObservationIgnored private var longFrames: [(start: CFTimeInterval, ms: Double, work: String)] = []
    /// The probe's counters as of the previous tick, to tell which work
    /// (M map body, S screen body, P re-plan) ran inside each frame.
    @ObservationIgnored private var seen = (map: 0, screen: 0, replans: 0)

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
        longFrames = []
        seen = (0, 0, 0)
        MapPerfProbe.shared.reset()
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
        // Everything after the first gesture is kept; the window's far end
        // is only known once the last gesture has finished (see `publish`).
        let probe = MapPerfProbe.shared
        let now = (map: probe.mapBodyEvals, screen: probe.screenBodyEvals, replans: probe.replans)
        if let first = probe.firstGestureStart, last >= first, delta * 1000 >= Self.longFrameMs {
            let work = (now.replans != seen.replans ? "P" : "")
                + (now.map != seen.map ? "M" : "")
                + (now.screen != seen.screen ? "S" : "")
            longFrames.append((start: last, ms: delta * 1000, work: work))
        }
        seen = now
        if frames % 30 == 0 { publish() }
    }

    private func publish() {
        let fps = totalTime > 0 ? Double(frames) / totalTime : 0
        let ratio = totalTime > 0 ? hitchTime / totalTime : 0
        let probe = MapPerfProbe.shared
        let counted = longFrames.filter { probe.isInWindow($0.start) }
        let stalls = counted.filter { $0.ms >= Self.stallFrameMs }
        let windowMs: Double
        if let first = probe.firstGestureStart, let last = probe.lastGestureEnd, !probe.gestureActive {
            windowMs = max(0, last + MapPerfProbe.windowTail - first) * 1000
        } else {
            windowMs = 0
        }
        summary = String(
            format: "fps=%.1f;hitchRatio=%.4f;hitches=%d;frames=%d;worstMs=%.1f;"
                + "hitchMs=%.0f;stallMs=%.0f;longFrames=%d;stallFrames=%d;windowMs=%.0f;"
                + "mapBodyEvals=%d;screenBodyEvals=%d;replans=%d;teardrops=%d;stalls=%@",
            fps, ratio, hitches, frames, worstFrameMs,
            counted.reduce(0) { $0 + $1.ms }, stalls.reduce(0) { $0 + $1.ms }, counted.count, stalls.count,
            windowMs,
            probe.mapBodyEvals, probe.screenBodyEvals, probe.replans, probe.teardrops,
            stalls.map { String(format: "%.0f", $0.ms) + $0.work }.joined(separator: ",")
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
