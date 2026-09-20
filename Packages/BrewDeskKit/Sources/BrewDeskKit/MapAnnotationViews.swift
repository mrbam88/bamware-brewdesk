import SwiftUI
import VenueKit

/// Styling for the map's markers (brewdesk#54, re-shaped bd#204/#209,
/// replaced outright by bd#212's "micro teardrops" — the design Bilal chose
/// after rejecting build 24's score-circle + count-stack markers. There is
/// no grouping/clustering representation left anywhere in the app; every
/// venue draws its OWN marker, sized by zoom and demoted to a small dot only
/// on a genuine screen-space collision with a better-scored marker.
///
/// Deliberately the ONLY place map-marker looks live — `MapAnnotationPlanner`
/// decides WHAT to draw (kind + diameter + selection), this file decides
/// what it LOOKS like.
///
/// Every view here stays composite-cheap on purpose: solid fills, one small
/// shadow, no materials, no per-marker `GeometryReader`, text only when the
/// head is big enough to read (bd#212 perf requirement — MapKit re-hosts
/// every annotation view on-camera-settle, so a cheap view is what keeps the
/// re-plan from itself becoming a hitch, same #54 lesson as before).

/// The classic map-pin silhouette: a round head with a pointed tail, tip at
/// the BOTTOM-CENTER of the view's own frame — paired with
/// `Annotation(..., anchor: .bottom)` in `CafeMapScreen` so the tip (not the
/// shape's visual center) lands exactly on the venue's coordinate.
struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + r)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        // The tail's two straight sides leave the circle this many degrees
        // either side of straight-down — a moderate angle keeps the tail
        // slim without pinching to a hairline at these tiny (4–30pt) sizes.
        let theta = Angle.degrees(55).radians
        let left = CGPoint(x: center.x - r * sin(theta), y: center.y + r * cos(theta))
        let right = CGPoint(x: center.x + r * sin(theta), y: center.y + r * cos(theta))

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        // The long way around the circle — through the TOP, never back
        // through the gap where the tail attaches.
        path.addArc(
            center: center,
            radius: r,
            startAngle: Angle(radians: atan2(left.y - center.y, left.x - center.x)),
            endAngle: Angle(radians: atan2(right.y - center.y, right.x - center.x)),
            clockwise: true
        )
        path.addLine(to: tip)
        path.closeSubpath()
        return path
    }
}

/// One unified marker view for EVERY venue on the map — teardrop, demoted
/// dot, or unrated speck all live here, driven purely by `MarkerPlacement`,
/// so `CafeMapScreen` hosts exactly one annotation VIEW TYPE per venue id
/// (bd#212's stable-identity/no-remove-insert perf requirement: a tier/size
/// change is a value change on an already-hosted view, never a different
/// view type MapKit would have to tear down and rebuild).
///
/// `Equatable` so SwiftUI can skip re-rendering a marker whose placement
/// didn't actually change between two `body` evaluations that aren't a real
/// re-plan (bd#212 perf requirement: "Equatable marker view").
struct TeardropMarkerView: View, Equatable {
    let placement: MarkerPlacement

    static func == (lhs: TeardropMarkerView, rhs: TeardropMarkerView) -> Bool {
        lhs.placement == rhs.placement
    }

    private var diameter: CGFloat { placement.kind.diameter }

    private var isTeardropShape: Bool {
        if case .teardrop = placement.kind { return true }
        return false
    }

    var body: some View {
        Group {
            switch placement.kind {
            case .teardrop, .dot:
                ratedHead
            case .speck:
                Circle()
                    .fill(BrewDeskPalette.markerSpeckFill)
                    .frame(width: diameter, height: diameter)
            }
        }
        // The shape/frame height differs (teardrop is taller than it is
        // wide, a dot/speck is square) — a fixed OUTER frame keeps every
        // marker's LAYOUT box (and therefore MapKit's own positioning of
        // it) a stable size for a given diameter, regardless of kind, so a
        // teardrop-to-dot demotion never itself shifts the annotation's
        // measured frame origin out from under `.bottom` anchoring.
        .frame(width: max(diameter, 4), height: max(diameter, 4) * MapAnnotationPlanner.tailHeightFactor, alignment: .bottom)
        .overlay(alignment: .top) {
            if placement.isSelected {
                selectedHalo
            }
        }
    }

    @ViewBuilder
    private var ratedHead: some View {
        let fill = BrewDeskPalette.markerFill(score: placement.venue.workScore)
        let numberSize = diameter * 0.58
        ZStack {
            if isTeardropShape {
                TeardropShape()
                    .fill(fill)
                    .overlay(TeardropShape().stroke(BrewDeskPalette.markerHairline, lineWidth: 0.75))
                    .frame(width: diameter, height: diameter * MapAnnotationPlanner.tailHeightFactor, alignment: .bottom)
                    .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            } else {
                Circle()
                    .fill(fill)
                    .overlay(Circle().stroke(BrewDeskPalette.markerHairline, lineWidth: 0.75))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            }
            if placement.showsNumber {
                Text(verbatim: "\(placement.venue.workScore)")
                    .font(BrewDeskFont.markerNumber(size: numberSize))
                    .foregroundStyle(BrewDeskPalette.markerNumberColor(score: placement.venue.workScore))
                    // The teardrop's visual centroid sits slightly above its
                    // frame's true vertical center (the tail pulls the
                    // frame's midpoint down) — nudge the number up into the
                    // round head rather than the tail.
                    .offset(y: isTeardropShape ? -diameter * 0.15 : 0)
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
            .offset(y: -diameter * 1.05)
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
