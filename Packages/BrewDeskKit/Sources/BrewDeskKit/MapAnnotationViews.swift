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

    // bd#221 perf fallback: `MarkerBodyImageCache` needs to know which of
    // the TWO pre-rendered images (light/dark) to hand back, since a cached
    // `UIImage` — unlike a `BrewDeskPalette` adaptive `Color` — can't
    // resolve itself against the current trait collection at draw time.
    @Environment(\.colorScheme) private var colorScheme

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

    /// bd#221 "names on": the `Annotation` this view sits inside anchors
    /// by a `UnitPoint` fraction of the content's OWN reported bounds — a
    /// plain `.overlay()`/`.offset()` label (this view's FIRST
    /// implementation) draws outside those bounds, which MapKit does not
    /// measure: the reference sheet's own supervisor review caught this as
    /// a corrupted/garbled render (the label's pixels got clipped and
    /// mis-composited at the edge of MapKit's rasterized annotation
    /// buffer), not a font or Unicode problem. The fix is to give the
    /// label REAL layout space — an `HStack` sibling of the pin, not an
    /// overlay — so the reported content size actually includes it, and
    /// to anchor the `Annotation` at the PIN's fraction of that now-wider
    /// content instead of a fixed `.bottom`, via `annotationAnchor(for:)`
    /// below (used by `CafeMapScreen.annotations(for:)`).
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if placement.nameLabelSide == .leading {
                labelSlot(side: .leading)
            }
            pinBody
            if placement.nameLabelSide == .trailing {
                labelSlot(side: .trailing)
            }
        }
        .overlay(alignment: .top) {
            // Never fires alongside a label — `nameLabelSide` is always
            // `nil` for the selected marker (bd#221 spec), so the HStack
            // above is just the pin alone here and this still centers
            // correctly over it.
            if placement.isSelected {
                selectedHalo
            }
        }
    }

    private var pinBody: some View {
        let score = placement.venue.workScore
        return ZStack {
            // bd#221 perf fallback: the "depth" finish's gradient + inner
            // highlight + rim + shadow measurably cost fill-rate at map-pan
            // density (MAP-PERF evidence in the PR — scripted-pan
            // hitchRatio came in above the accepted 0.02 regression budget
            // against origin/main with this drawn live every frame). Per
            // the ticket's own contingency, that STATIC part of the body is
            // rendered ONCE per (tier, size bucket, appearance) into a
            // `UIImage` by `MarkerBodyImageCache` and reused as a plain
            // `Image` — only the live score `Text` below (and the name
            // label, when present) still draws fresh.
            Image(uiImage: MarkerBodyImageCache.image(score: score, diameter: diameter, isDark: colorScheme == .dark))
            if placement.showsNumber {
                // brewdesk#213: `showsNumber` is only ever true for a rated
                // venue (`isRated`), so `displayScore` is never nil here —
                // the `workScore` fallback only guards the type, it never
                // actually fires.
                Text(verbatim: "\(placement.venue.displayScore ?? score)")
                    .font(BrewDeskFont.markerNumber(size: diameter * 0.58))
                    .foregroundStyle(BrewDeskPalette.markerNumberColor(score: score))
                    .offset(y: numberVerticalOffset)
            }
        }
        .frame(width: diameter, height: frameHeight, alignment: .bottom)
    }

    /// bd#221 "names on": the café name beside this pin's head — a real
    /// `HStack` sibling (see `body`'s doc comment for why), fixed at
    /// `labelMaxWidth` × the pin's own `frameHeight` so `annotationAnchor
    /// (for:)` can compute a stable fraction and the pin's own bottom edge
    /// (its tip) stays exactly where `HStack(alignment: .bottom)` puts it
    /// regardless of the label's actual text height. The text itself hugs
    /// the near edge (against the gap) and grows away from the head,
    /// vertically re-centered onto the HEAD (not the frame) with the same
    /// `numberVerticalOffset` geometry the score number uses. Not hit-
    /// testable and hidden from accessibility — `markerButton`'s own
    /// `.accessibilityLabel` already carries the café name for VoiceOver.
    private func labelSlot(side: NameLabelSide) -> some View {
        HaloText(
            text: placement.venue.name,
            color: BrewDeskPalette.markerLabelText,
            halo: BrewDeskPalette.markerLabelHalo
        )
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(
            width: MapAnnotationPlanner.labelMaxWidth, height: frameHeight,
            alignment: side == .trailing ? .leading : .trailing
        )
        .offset(y: numberVerticalOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The `Annotation` anchor this placement needs — see `body`'s doc
    /// comment. `.bottom` (the pin's own tip, centered) when there's no
    /// label; otherwise the pin's fraction of the wider (label + pin)
    /// content, so the TIP still lands exactly on the venue's coordinate
    /// instead of sliding sideways by roughly half the label's reserved
    /// width.
    static func annotationAnchor(for placement: MarkerPlacement) -> UnitPoint {
        guard let side = placement.nameLabelSide else { return .bottom }
        let diameter = placement.kind.teardropDiameter ?? MapAnnotationPlanner.selectedDiameter
        let labelWidth = MapAnnotationPlanner.labelMaxWidth
        let totalWidth = diameter + labelWidth
        let pinCenterX = side == .trailing ? diameter / 2 : labelWidth + diameter / 2
        return UnitPoint(x: pinCenterX / totalWidth, y: 1)
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

/// bd#221 finish `"depth"`: the STATIC part of a teardrop's body — gradient
/// fill, inner top highlight, rim, shadow — factored out of
/// `TeardropMarkerView.body` so the exact same visuals can be drawn either
/// live (cheap: nothing else references this type directly any more, but it
/// stays the single source of truth for what the cached image below
/// captures) or once into `MarkerBodyImageCache`'s cached `UIImage`.
private struct MarkerBodyShape: View {
    let score: Int
    let diameter: CGFloat
    let frameHeight: CGFloat

    /// bd#221 rim `"tone"`: 1pt in BOTH appearances — Bilal's saved
    /// design-review selection has no per-appearance width split (that was
    /// bd#217's fixed-hairline-color era; the rim COLOR now carries the
    /// per-appearance difference instead, via `BrewDeskPalette
    /// .markerRim(score:)`).
    private let hairlineWidth: CGFloat = 1.0

    var body: some View {
        TeardropShape()
            .fill(markerGradient)
            .overlay(
                // The 0.5pt inner top highlight (mock's own `inset 0 .5px
                // 0 rgba(255,255,255,…)`) — a soft white fade from the
                // very top of the head down to about a fifth of its
                // height, clipped to the teardrop's own silhouette.
                // `TeardropShape` isn't `InsettableShape` (its path is
                // built directly via a `UIBezierPath` bridge, not
                // SwiftUI's rounded-rect primitives), so this reads as a
                // fading fill rather than a literal inset stroke — same
                // visual effect, no shape-protocol conformance needed.
                TeardropShape().fill(
                    LinearGradient(
                        colors: [BrewDeskPalette.markerHighlight, BrewDeskPalette.markerHighlight.opacity(0)],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.24)
                    )
                )
            )
            .overlay(
                TeardropShape().stroke(BrewDeskPalette.markerRim(score: score), lineWidth: hairlineWidth)
            )
            .shadow(color: BrewDeskPalette.markerShadow, radius: 1.5, x: 0, y: 1.5)
            .frame(width: diameter, height: frameHeight, alignment: .bottom)
    }

    /// Vertical gradient read top-to-bottom ON SCREEN — `TeardropShape
    /// .path(in:)` already builds its final path points directly in the
    /// view's own (screen-space) frame rect rather than in some pre-
    /// rotation local space (see its own doc comment: the 45°-rotation
    /// happens INSIDE the path math, not as a `View`-level
    /// `.rotationEffect`), so a plain `.top`→`.bottom` `LinearGradient`
    /// already reads correctly with no extra rotation trick needed the way
    /// the design-review mock's CSS (`rotate(-45deg)` on the whole div)
    /// required.
    private var markerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: BrewDeskPalette.markerGradientTop(score: score), location: 0),
                .init(color: BrewDeskPalette.markerFill(score: score), location: 0.52),
                .init(color: BrewDeskPalette.markerGradientBottom(score: score), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// bd#221 perf fallback (ticket's own contingency clause): renders
/// `MarkerBodyShape` ONCE per (tier, size bucket, appearance) into a
/// `UIImage` and reuses it — MAP-PERF evidence in the PR showed the live
/// gradient/highlight/shadow draw pushed scripted-pan `hitchRatio` outside
/// the accepted 0.02 regression budget against origin/main at the fixture's
/// 220-annotation density. Only the live score `Text` (and, when present,
/// the name label) still draws fresh every frame — see `TeardropMarkerView
/// .body`.
@MainActor
enum MarkerBodyImageCache {
    private struct Key: Hashable {
        let tierIndex: Int
        let sizeBucket: Int
        let isDark: Bool
    }

    private static var cache: [Key: UIImage] = [:]

    /// Rounds a continuous head diameter (the planner interpolates on a LOG
    /// scale, so a settled camera can land on almost any value between the
    /// size stops) to the nearest half-point — visually identical to the
    /// exact value, but bounds the cache to a small, fixed set of images
    /// (roughly 4pt–30pt in 0.5pt steps × 4 tiers × 2 appearances) instead
    /// of a fresh entry per exact pinch-zoom frame.
    private static func sizeBucket(_ diameter: CGFloat) -> Int { Int((diameter * 2).rounded()) }

    static func image(score: Int, diameter: CGFloat, isDark: Bool) -> UIImage {
        let key = Key(tierIndex: BrewDeskPalette.markerTierIndex(score: score), sizeBucket: sizeBucket(diameter), isDark: isDark)
        if let cached = cache[key] { return cached }
        let frameHeight = diameter * MapAnnotationPlanner.tailHeightFactor
        let renderer = ImageRenderer(content:
            MarkerBodyShape(score: score, diameter: diameter, frameHeight: frameHeight)
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        let image = renderer.uiImage ?? UIImage()
        cache[key] = image
        return image
    }
}

/// bd#221 "names on": a haloed text label — the design-review mock's own
/// multi-direction `text-shadow` halo (no solid background pill, so a
/// label reads over any basemap detail without ever looking like its own
/// chrome element). Eight halo copies offset a hair in every direction
/// behind one solid-color copy on top — cheap (all `Text`, no `Canvas`/
/// blur filter) and correct in both appearances since both colors are
/// already adaptive `BrewDeskPalette` tokens.
private struct HaloText: View {
    let text: String
    let color: Color
    let halo: Color

    private static let haloOffsets: [(CGFloat, CGFloat)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0), (1, 0),
        (-1, 1), (0, 1), (1, 1),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.haloOffsets.enumerated()), id: \.offset) { _, o in
                Text(verbatim: text).foregroundStyle(halo).offset(x: o.0, y: o.1)
            }
            Text(verbatim: text).foregroundStyle(color)
        }
        .font(BrewDeskFont.markerLabel())
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
