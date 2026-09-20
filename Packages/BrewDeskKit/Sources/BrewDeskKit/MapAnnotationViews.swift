import SwiftUI
import VenueKit

/// Styling for the three map representations (brewdesk#54). Deliberately the
/// ONLY place map-annotation looks live — the representation logic is
/// `MapAnnotationPlanner`, so the brewdesk#55 visual pass edits this file
/// without touching planning or `CafeMapScreen`.
///
/// Every view here is composite-cheap on purpose: solid fills, no materials,
/// no shadows, no SF Symbol per pin. MapKit repositions annotation views every
/// frame of a pan; blur-backed or shadowed views made that the #54 stutter.

/// Full pin: score-forward solid capsule (fewer, smarter pins — #55).
///
/// Unobserved venues (bd#159, `!venue.isObserved`) render a neutral grey
/// outline pin with no number instead of the engine's flat fallback score —
/// the fill is a fixed grey, never red or green (founder is red-green
/// colorblind), so it can never be mistaken for a low/high tier.
struct VenueScorePin: View {
    let venue: Venue
    let isSelected: Bool

    var body: some View {
        Group {
            if venue.isObserved {
                Text("\(venue.workScore)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(venue.scoreTier.color, in: Capsule())
            } else {
                Image(systemName: "questionmark")
                    .font(.caption.bold())
                    .foregroundStyle(BrewDeskPalette.unobserved)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(BrewDeskPalette.unobserved, lineWidth: 1.5))
            }
        }
        .overlay(Capsule().stroke(.white, lineWidth: isSelected ? 2.5 : 1))
        .scaleEffect(isSelected ? 1.12 : 1)
    }
}

/// Mid-density venue: a score-tier dot with a comfortable tap frame.
/// Unobserved venues get a neutral grey dot instead of a tier fill (bd#159)
/// — same neutral, non-red/green treatment as `VenueScorePin`.
///
/// bd#209: unobserved used to be `.white` fill + `.white` stroke — at
/// street-level density, dozens of overlapping unobserved dots had the SAME
/// fill and edge color as their neighbours, so the pile read as one
/// borderless white blob ("worm") instead of individual cafés. Now a
/// neutral mid-grey fill with a hairline DARKER grey stroke, so each dot
/// keeps a visible edge against both the basemap and its neighbours even
/// when several sit close together. `MapAnnotationPlanner`'s collision pass
/// also now guarantees ≥14pt centre-to-centre spacing between any two
/// placed dots, so true full overlap can no longer happen at all — this
/// styling fix is what keeps a near-miss legible on top of that.
///
/// bd#211: observed used to tint by `venue.scoreTier.color` directly — four
/// DIFFERENT hues (green/sage/olive/brick) with no number to anchor them,
/// exactly the signal a red-green colorblind viewer can't read reliably.
/// Now a SINGLE hue at three lightness steps (`BrewDeskPalette
/// .observedDotColor(for:)`) — darkest/most saturated wins, lightest
/// loses. Unobserved and observed are ALSO now differentiated by shape,
/// not just color/lightness: unobserved is a hollow ring (no fill),
/// observed is a filled disc — so even the lightest observed step reads as
/// unmistakably different from "not checked yet" at a glance.
struct VenueScoreDot: View {
    let venue: Venue

    var body: some View {
        Group {
            if venue.isObserved {
                Circle()
                    .fill(BrewDeskPalette.observedDotColor(for: venue.scoreTier))
                    .overlay(Circle().stroke(BrewDeskPalette.observedDotStroke, lineWidth: 1))
            } else {
                Circle()
                    .strokeBorder(BrewDeskPalette.unobservedDotStroke, lineWidth: 2)
            }
        }
        .frame(width: 14, height: 14)
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }
}

/// Apple-only gap-fill marker (bd#182, feature-flagged — `AppleGapFillService
/// .isEnabled`, default OFF): a grey outline café glyph, deliberately unlike
/// every scored representation above (no capsule/number, no tier fill, a
/// dashed rather than solid ring) — Apple's own unverified suggestion must
/// never be mistaken for one of our claims at a glance. Grey only, never red
/// or green (founder is red-green colorblind) — same `.unobserved` token
/// `VenueScorePin`/`VenueScoreDot`/`VenueClusterPill` use for "not checked
/// yet", reused here for "not even ours".
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

/// High-density cell: a "stack" of grouped cafés, deliberately UNLIKE a
/// score pin in both shape and color (bd#204 — Bilal read cluster counts as
/// out-of-range scores because the old pill was a tier-tinted capsule
/// indistinguishable from `VenueScorePin`). Never a `ScoreTier` color, never
/// a circle/capsule: a rounded-rectangle silhouette with a second, offset
/// rect behind it to read as a pile of pins, a `square.stack` glyph, and the
/// count — never the cell's best score, however evidenced the cell is. The
/// shape difference (rect stack vs. circle) is what keeps the two legible in
/// greyscale, not just the color (founder is red-green colorblind).
struct VenueClusterPill: View {
    let cluster: VenueCluster

    /// "128", capped to "999+" only once the pill genuinely can't spell out
    /// the count. bd#209: "99+" was hiding real information at exactly the
    /// density where the count matters most (a "99+" versus "128" versus
    /// "342" is a meaningfully different amount of café evidence behind one
    /// stack) — the honest number now shows up to three digits, and only
    /// four-digit-or-more density (unreachable in practice: `plan()` caps
    /// total annotations at `MapAnnotationPlanner.maxAnnotations`, and a
    /// stack's member count is bounded by whatever's left in view) falls
    /// back to a capped display at all.
    private var displayCount: String {
        cluster.count > 999 ? "999+" : "\(cluster.count)"
    }

    var body: some View {
        ZStack {
            // The second, offset rect behind the front face — reads as a
            // pile of grouped pins rather than one flat badge. Solid fill,
            // no shadow/material (map annotations re-host every pan frame;
            // see the file-level perf note above).
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrewDeskPalette.clusterSurface)
                .frame(width: 40, height: 40)
                .offset(x: 5, y: 5)

            // Content drives sizing (not the other way around, bd#204 fix):
            // an `.overlay`'d shape stays pinned to the frame's minimum, so
            // "99+" wrapped onto a second line at the 44pt minimum. Sizing
            // the HStack first and hanging the shape off its `.background`
            // lets the pill grow past 44pt when the capped label needs it.
            HStack(spacing: 3) {
                Image(systemName: "square.stack")
                    .font(.caption2.bold())
                Text(displayCount)
                    .font(.caption.monospacedDigit().bold())
                    .fixedSize()
            }
            .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BrewDeskPalette.clusterSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(BrewDeskPalette.clusterSurfaceStroke, lineWidth: 1)
                    )
            )
        }
    }
}
