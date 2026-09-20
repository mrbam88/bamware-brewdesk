import SwiftUI
import UIKit
import VenueKit

/// Styling for the map's markers (brewdesk#54, re-shaped bd#204/#209,
/// replaced outright by bd#212's "micro teardrops" — the design Bilal chose
/// after rejecting build 24's score-circle + count-stack markers. There is
/// no grouping/clustering representation left anywhere in the app.
///
/// Only the numbered TEARDROP lives here as a SwiftUI view any more — a
/// demoted rated dot and an unrated speck are native MapKit `MapCircle`
/// overlay content built directly in `CafeMapScreen` (supervisor review:
/// hosting ~200 unrated specks as SwiftUI annotation views, each wrapped in
/// its own 44pt `Button`, was the real cost behind the missed perf target —
/// a `MapCircle` is MapKit's own cheap overlay primitive, never a hosted
/// SwiftUI view).

/// The classic map-pin silhouette: a round head with a pointed tail, tip at
/// the BOTTOM-CENTER of the view's own frame — paired with
/// `Annotation(..., anchor: .bottom)` in `CafeMapScreen` so the tip (not the
/// shape's visual center) lands exactly on the venue's coordinate.
///
/// Built the same way the design mock's own CSS does (`border-radius: 50%
/// 50% 50% 0; transform: rotate(-45deg)`): round three corners of a square
/// at their maximum radius (side/2 — which makes those three corners trace
/// a true circle of diameter `side` centered on the square's own center),
/// leave the fourth corner sharp, then rotate the whole square -45° around
/// its center. The sharp corner swings straight down to become the tip, at
/// distance `side/2 · (1 + √2) ≈ 0.7071·side` below the head's center — a
/// pure affine rotation, not a hand-derived arc-sweep direction (the
/// PREVIOUS implementation built the outline from a manual circular arc
/// with a `clockwise` flag guessed without ever rendering it; the guess was
/// wrong, so every teardrop rendered as a near-invisible sliver instead of
/// a filled head — this construction has no such direction ambiguity: it's
/// one multiplication).
struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = rect.width
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + side / 2)
        let squareRect = CGRect(
            x: headCenter.x - side / 2, y: headCenter.y - side / 2,
            width: side, height: side
        )
        // `Path` has no rounded-corners-per-corner initializer — build via
        // `UIBezierPath` (which does) and bridge its `CGPath`.
        var square = Path(
            UIBezierPath(
                roundedRect: squareRect,
                byRoundingCorners: [.topLeft, .topRight, .bottomRight],
                cornerRadii: CGSize(width: side / 2, height: side / 2)
            ).cgPath
        )
        let toOrigin = CGAffineTransform(translationX: -headCenter.x, y: -headCenter.y)
        let rotate = CGAffineTransform(rotationAngle: -45 * .pi / 180)
        let back = CGAffineTransform(translationX: headCenter.x, y: headCenter.y)
        square = square.applying(toOrigin.concatenating(rotate).concatenating(back))
        return square
    }
}

/// The numbered teardrop marker — the ONLY per-venue SwiftUI view left on
/// the map. `Equatable` so SwiftUI can skip re-rendering a marker whose
/// placement didn't actually change between two `body` evaluations that
/// aren't a real re-plan (bd#212 perf requirement).
struct TeardropMarkerView: View, Equatable {
    let placement: MarkerPlacement

    static func == (lhs: TeardropMarkerView, rhs: TeardropMarkerView) -> Bool {
        lhs.placement == rhs.placement
    }

    private var diameter: CGFloat { placement.kind.teardropDiameter ?? MapAnnotationPlanner.selectedDiameter }
    /// Total frame height (head + tail) — see `MapAnnotationPlanner
    /// .tailHeightFactor`'s doc comment for the `TeardropShape` geometry
    /// this matches exactly.
    private var frameHeight: CGFloat { diameter * MapAnnotationPlanner.tailHeightFactor }
    /// How far the number must shift UP from the frame's own vertical
    /// center to land at the HEAD's true center (the tail pulls the
    /// frame's midpoint down) — the closed-form version of the geometry
    /// `TeardropShape` draws: head center sits at `diameter/2` from the
    /// frame's top; the frame's own center sits at `frameHeight/2`.
    private var numberVerticalOffset: CGFloat { (diameter - frameHeight) / 2 }

    var body: some View {
        let fill = BrewDeskPalette.markerFill(score: placement.venue.workScore)
        ZStack {
            TeardropShape()
                .fill(fill)
                .overlay(TeardropShape().stroke(BrewDeskPalette.markerHairline, lineWidth: 0.75))
                .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            if placement.showsNumber {
                // brewdesk#213: `showsNumber` is only ever true for a rated
                // venue (`isRated`), so `displayScore` is never nil here —
                // the `workScore` fallback only guards the type, it never
                // actually fires.
                Text(verbatim: "\(placement.venue.displayScore ?? placement.venue.workScore)")
                    .font(BrewDeskFont.markerNumber(size: diameter * 0.58))
                    .foregroundStyle(BrewDeskPalette.markerNumberColor(score: placement.venue.workScore))
                    .offset(y: numberVerticalOffset)
            }
        }
        .frame(width: diameter, height: frameHeight, alignment: .bottom)
        .overlay(alignment: .top) {
            if placement.isSelected {
                selectedHalo
            }
        }
    }

    private var selectedHalo: some View {
        Text(placement.venue.name)
            .font(BrewDeskFont.label(.caption2, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BrewDeskPalette.markerHaloBackground, in: Capsule())
            .foregroundStyle(BrewDeskPalette.markerHaloText)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .fixedSize()
            .offset(y: -diameter * 0.35)
    }
}

/// Apple-only gap-fill marker (bd#182, feature-flagged — `AppleGapFillService
/// .isEnabled`, default OFF): a grey outline café glyph, deliberately unlike
/// every scored marker above — Apple's own unverified suggestion must never
/// be mistaken for one of our claims at a glance. Grey only, never red or
/// green (founder is red-green colorblind).
struct AppleUnverifiedPin: View {
    var body: some View {
        Image(systemName: "cup.and.saucer")
            .font(.caption2.bold())
            .foregroundStyle(BrewDeskPalette.unobserved)
            .padding(6)
            .frame(minWidth: 30, minHeight: 30)
            .background(.white, in: Circle())
            .overlay(
                Circle().strokeBorder(
                    BrewDeskPalette.unobserved,
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                )
            )
    }
}
