import SwiftUI

/// Vector geometry for the BrewDesk mark (saucer, cup body, handle, dot,
/// three signal arcs), traced from `icon-1024-dark.png` / the static
/// `LaunchMark` asset's pixel proportions (bamware-brewdesk#186).
///
/// All constants are fractions of the asset's own canvas (360×436, the
/// `LaunchMark@3x` pixel size) — the same aspect ratio `BrewDeskMark` locks
/// itself to via `aspectRatio` below, so a shape drawn at any size lands in
/// the same relative place the raster mark does. Verified by eye against a
/// 50%-opacity overlay on the real asset (see `BrewDeskMark`'s `#Preview`
/// in the app target, `BrewDesk/Design/BrewDeskMark.swift`) rather than an
/// exact bezier trace — good enough for an animated mark, not a pixel diff.
nonisolated enum BrewDeskMarkGeometry {
    static let canvasW: CGFloat = 360
    static let canvasH: CGFloat = 436
    /// width / height — pass to `.aspectRatio(_:contentMode:)`.
    static let aspectRatio: CGFloat = canvasW / canvasH

    static let cx: CGFloat = 174 / canvasW

    static let dotCY: CGFloat = 191 / canvasH
    static let dotR: CGFloat = 20 / canvasW

    static let cupTopY: CGFloat = 255 / canvasH
    static let cupTopL: CGFloat = 52 / canvasW
    static let cupTopR: CGFloat = 296 / canvasW
    static let cupBotY: CGFloat = 399 / canvasH
    static let cupBotL: CGFloat = 90 / canvasW
    static let cupBotR: CGFloat = 259 / canvasW
    static let cupCorner: CGFloat = 15 / canvasW

    static let saucerY0: CGFloat = 410 / canvasH
    static let saucerY1: CGFloat = 435 / canvasH
    static let saucerL: CGFloat = 1 / canvasW
    static let saucerR: CGFloat = 348 / canvasW

    static let handleCX: CGFloat = 294 / canvasW
    static let handleCY: CGFloat = 300 / canvasH
    static let handleR: CGFloat = 50 / canvasW
    /// Fraction of width — the handle stroke's line width.
    static let handleLineWidth: CGFloat = 23 / canvasW

    /// Three concentric arcs, centered just above the dot, opening upward.
    static let fanCY: CGFloat = 194 / canvasH
    static let arcGap: CGFloat = 15 / canvasW
    /// Fraction of width — each arc stroke's line width.
    static let arcLineWidth: CGFloat = 20 / canvasW
    static let arcHalfAngleDeg: Double = 58
    static let arcOuterR: CGFloat = 172 / canvasW

    static func point(_ nx: CGFloat, _ ny: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + nx * rect.width, y: rect.minY + ny * rect.height)
    }

    /// A fraction-of-width value (e.g. `arcLineWidth`) resolved to a
    /// concrete point size. Shapes above size themselves per-frame off
    /// `path(in:)`'s `rect`, but `StrokeStyle` needs one fixed number —
    /// callers of `BrewDeskMark` size the view explicitly (launch reveal,
    /// idle indicator), so scaling off the canvas's own width is stable.
    static func resolved(_ fraction: CGFloat) -> CGFloat {
        fraction * canvasW
    }
}

/// The saucer: a rounded bar beneath the cup.
struct BrewDeskMarkSaucer: Shape {
    func path(in rect: CGRect) -> Path {
        let g = BrewDeskMarkGeometry.self
        let topLeft = g.point(g.saucerL, g.saucerY0, in: rect)
        let size = CGSize(
            width: (g.saucerR - g.saucerL) * rect.width,
            height: (g.saucerY1 - g.saucerY0) * rect.height
        )
        let bar = CGRect(origin: topLeft, size: size)
        return Path(roundedRect: bar, cornerSize: CGSize(width: bar.height / 2, height: bar.height / 2))
    }
}

/// The cup body: a trapezoid (wide rim, narrower base) with rounded bottom
/// corners. The handle is its own shape (`BrewDeskMarkHandle`).
struct BrewDeskMarkCupBody: Shape {
    func path(in rect: CGRect) -> Path {
        let g = BrewDeskMarkGeometry.self
        let topL = g.point(g.cupTopL, g.cupTopY, in: rect)
        let topR = g.point(g.cupTopR, g.cupTopY, in: rect)
        let botR = g.point(g.cupBotR, g.cupBotY, in: rect)
        let botL = g.point(g.cupBotL, g.cupBotY, in: rect)
        let corner = g.cupCorner * rect.width

        var path = Path()
        path.move(to: topL)
        path.addLine(to: topR)
        path.addLine(to: CGPoint(x: botR.x, y: botR.y - corner))
        path.addQuadCurve(to: CGPoint(x: botR.x - corner, y: botR.y), control: botR)
        path.addLine(to: CGPoint(x: botL.x + corner, y: botL.y))
        path.addQuadCurve(to: CGPoint(x: botL.x, y: botL.y - corner), control: botL)
        path.closeSubpath()
        return path
    }
}

/// The handle: a ring segment attached to the cup's right rim. This is the
/// arc centerline only — stroke it with `BrewDeskMarkGeometry.handleLineWidth`
/// so `.trim` keeps working for anyone who wants to draw it on too.
struct BrewDeskMarkHandle: Shape {
    func path(in rect: CGRect) -> Path {
        let g = BrewDeskMarkGeometry.self
        let center = g.point(g.handleCX, g.handleCY, in: rect)
        var path = Path()
        path.addArc(
            center: center,
            radius: g.handleR * rect.width,
            startAngle: .degrees(-100),
            endAngle: .degrees(100),
            clockwise: false
        )
        return path
    }
}

/// The dot above the arcs.
struct BrewDeskMarkDot: Shape {
    func path(in rect: CGRect) -> Path {
        let g = BrewDeskMarkGeometry.self
        let center = g.point(g.cx, g.dotCY, in: rect)
        let radius = g.dotR * rect.width
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// One of the three concentric signal arcs above the dot. `index` 0 is the
/// innermost (smallest radius, closest to the dot), 2 is the outermost.
/// Centerline only — stroke it with `BrewDeskMarkGeometry.arcLineWidth`.
struct BrewDeskMarkArc: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let g = BrewDeskMarkGeometry.self
        let center = g.point(g.cx, g.fanCY, in: rect)
        let step = (g.arcLineWidth + g.arcGap) * rect.width
        let radius = g.arcOuterR * rect.width - CGFloat(2 - index) * step
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 - g.arcHalfAngleDeg),
            endAngle: .degrees(-90 + g.arcHalfAngleDeg),
            clockwise: false
        )
        return path
    }
}

/// A snapshot of every animatable property of the mark at one instant —
/// the "progress values" `BrewDeskMark` renders from. Pure data; how a
/// `Stage` changes over time for the launch reveal lives in
/// `LaunchRevealTimeline` (app target, unit tested there as pure logic
/// with no view involved).
nonisolated public struct BrewDeskMarkStage: Equatable, Sendable {
    /// Shared by saucer + cup body + handle.
    public var bodyOpacity: Double
    public var bodyScale: Double
    public var dotScale: Double
    /// 0...1 trim fraction per arc, innermost (0) to outermost (2).
    public var arc1Trim: Double
    public var arc2Trim: Double
    public var arc3Trim: Double
    /// 0...1 — drives one shared soft shadow pulse across all three arcs
    /// (the launch reveal's single glow moment; the idle "signal" mode
    /// does its own independent per-arc glow, not this field).
    public var glowOpacity: Double

    public init(
        bodyOpacity: Double,
        bodyScale: Double,
        dotScale: Double,
        arc1Trim: Double,
        arc2Trim: Double,
        arc3Trim: Double,
        glowOpacity: Double
    ) {
        self.bodyOpacity = bodyOpacity
        self.bodyScale = bodyScale
        self.dotScale = dotScale
        self.arc1Trim = arc1Trim
        self.arc2Trim = arc2Trim
        self.arc3Trim = arc3Trim
        self.glowOpacity = glowOpacity
    }

    /// Nothing drawn yet — the reveal's frame 0.
    public static let hidden = BrewDeskMarkStage(
        bodyOpacity: 0, bodyScale: 0.96, dotScale: 0,
        arc1Trim: 0, arc2Trim: 0, arc3Trim: 0, glowOpacity: 0
    )
    /// Fully drawn, resting — matches the static `LaunchMark` asset.
    public static let settled = BrewDeskMarkStage(
        bodyOpacity: 1, bodyScale: 1, dotScale: 1,
        arc1Trim: 1, arc2Trim: 1, arc3Trim: 1, glowOpacity: 0
    )
}

/// The BrewDesk mark, rendered as vector shapes rather than the raster
/// `LaunchMark`/`AppIcon` assets — so it can be driven frame-by-frame for
/// the cold-launch reveal (`LaunchRevealView`, app target) and reused,
/// gently animated, as an idle "finding cafés" indicator.
public struct BrewDeskMark: View {
    public enum Mode: Equatable, Sendable {
        /// Externally driven — the caller supplies every property. Used by
        /// `LaunchRevealView`, which computes a `Stage` from
        /// `LaunchRevealTimeline` every frame.
        case stage(BrewDeskMarkStage)
        /// Fully drawn, resting. The default — matches the static asset.
        case settled
        /// A very low-amplitude, self-contained loop: the three arcs
        /// brighten in sequence, ~1.6s per cycle. For a loading/empty
        /// state, not a launch moment — `LaunchRevealView` never uses this.
        case signal
    }

    private let tint: Color
    private let mode: Mode
    private let isAnimated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - tint: the mark's fill/stroke color. Defaults to
    ///     `BrewDeskPalette.roast` (the palette's primary brand fill — this
    ///     codebase has no separate "lime" token; see PR notes). Pass
    ///     `.white` for the launch reveal to match the static `LaunchMark`.
    ///   - mode: what to render — see `Mode`.
    ///   - isAnimated: when `false`, always renders fully settled with no
    ///     motion, ignoring `mode` — for reduced-motion callers that still
    ///     want the finished mark.
    public init(tint: Color = BrewDeskPalette.roast, mode: Mode = .settled, isAnimated: Bool = true) {
        self.tint = tint
        self.mode = mode
        self.isAnimated = isAnimated
    }

    public var body: some View {
        Group {
            if isAnimated, case .signal = mode, !reduceMotion {
                SignalLoopMark(tint: tint)
            } else {
                MarkFace(tint: tint, stage: resolvedStage)
            }
        }
        .aspectRatio(BrewDeskMarkGeometry.aspectRatio, contentMode: .fit)
    }

    private var resolvedStage: BrewDeskMarkStage {
        guard isAnimated else { return .settled }
        switch mode {
        case .stage(let stage): return stage
        case .settled, .signal: return .settled
        }
    }
}

/// Renders one fixed `BrewDeskMarkStage` — no animation of its own. The
/// caller (`LaunchRevealView`, or a plain `.settled`/reduced-motion render)
/// owns whatever transition gets it from one stage to the next.
private struct MarkFace: View {
    let tint: Color
    let stage: BrewDeskMarkStage

    var body: some View {
        ZStack {
            arc(index: 0, trim: stage.arc1Trim, glow: stage.glowOpacity)
            arc(index: 1, trim: stage.arc2Trim, glow: stage.glowOpacity)
            arc(index: 2, trim: stage.arc3Trim, glow: stage.glowOpacity)

            ZStack {
                BrewDeskMarkSaucer()
                BrewDeskMarkCupBody()
                BrewDeskMarkHandle()
                    .stroke(tint, style: StrokeStyle(lineWidth: BrewDeskMarkGeometry.resolved(BrewDeskMarkGeometry.handleLineWidth), lineCap: .round))
            }
            .foregroundStyle(tint)
            .opacity(stage.bodyOpacity)
            .scaleEffect(stage.bodyScale)

            BrewDeskMarkDot()
                .foregroundStyle(tint)
                .scaleEffect(stage.dotScale)
        }
    }

    @ViewBuilder
    private func arc(index: Int, trim: Double, glow: Double) -> some View {
        BrewDeskMarkArc(index: index)
            .trim(from: 0, to: trim)
            .stroke(tint, style: StrokeStyle(lineWidth: BrewDeskMarkGeometry.resolved(BrewDeskMarkGeometry.arcLineWidth), lineCap: .round))
            .shadow(color: tint.opacity(glow), radius: 10 * glow)
    }
}

/// The idle "signal" loop: the three arcs brighten in sequence via
/// `PhaseAnimator`, which owns its own repeat/cancel lifecycle — nothing
/// here retains a `Timer` or `Task` past this view's lifetime, and the
/// loop simply stops advancing once the view leaves the hierarchy.
private struct SignalLoopMark: View {
    let tint: Color

    fileprivate enum Pulse: CaseIterable {
        case rest, arc1, arc2, arc3
    }

    var body: some View {
        PhaseAnimator(Pulse.allCases) { phase in
            ZStack {
                arcView(index: 0, active: phase == .arc1)
                arcView(index: 1, active: phase == .arc2)
                arcView(index: 2, active: phase == .arc3)

                ZStack {
                    BrewDeskMarkSaucer()
                    BrewDeskMarkCupBody()
                    BrewDeskMarkHandle()
                        .stroke(tint, style: StrokeStyle(lineWidth: BrewDeskMarkGeometry.resolved(BrewDeskMarkGeometry.handleLineWidth), lineCap: .round))
                }
                .foregroundStyle(tint)

                BrewDeskMarkDot()
                    .foregroundStyle(tint)
            }
        } animation: { _ in
            .easeInOut(duration: 0.4)
        }
    }

    /// Low amplitude by design: arcs stay fully drawn throughout — only
    /// opacity/glow nudge up briefly, one ring at a time.
    @ViewBuilder
    private func arcView(index: Int, active: Bool) -> some View {
        BrewDeskMarkArc(index: index)
            .stroke(
                tint.opacity(active ? 1 : 0.78),
                style: StrokeStyle(lineWidth: BrewDeskMarkGeometry.resolved(BrewDeskMarkGeometry.arcLineWidth), lineCap: .round)
            )
            .shadow(color: tint.opacity(active ? 0.22 : 0), radius: active ? 6 : 0)
    }
}
