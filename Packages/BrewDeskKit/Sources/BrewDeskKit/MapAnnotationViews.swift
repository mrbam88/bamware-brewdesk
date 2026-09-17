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
/// Unobserved venues get a hollow grey/white dot instead of a tier fill
/// (bd#159) — same neutral, non-red/green treatment as `VenueScorePin`.
struct VenueScoreDot: View {
    let venue: Venue

    var body: some View {
        Circle()
            .fill(venue.isObserved ? venue.scoreTier.color : .white)
            .stroke(venue.isObserved ? .white : BrewDeskPalette.unobserved, lineWidth: 1.5)
            .frame(width: 14, height: 14)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }
}

/// High-density cell: count pill tinted by the cell's best score.
/// A cell with no observed venues at all (bd#159, `!hasObservedVenue`)
/// tints neutral grey instead of a fabricated tier color from the flat
/// fallback score.
struct VenueClusterPill: View {
    let cluster: VenueCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 34, minHeight: 34)
            .background(
                cluster.hasObservedVenue ? ScoreTier(score: cluster.bestScore).color : BrewDeskPalette.unobserved,
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
    }
}
