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
struct VenueScorePin: View {
    let venue: Venue
    let isSelected: Bool

    var body: some View {
        Text("\(venue.workScore)")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 44)
            .background(venue.scoreTier.color, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: isSelected ? 2.5 : 1))
            .scaleEffect(isSelected ? 1.12 : 1)
    }
}

/// Mid-density venue: a score-tier dot with a comfortable tap frame.
struct VenueScoreDot: View {
    let venue: Venue

    var body: some View {
        Circle()
            .fill(venue.scoreTier.color)
            .stroke(.white, lineWidth: 1.5)
            .frame(width: 14, height: 14)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }
}

/// High-density cell: count pill tinted by the cell's best score.
struct VenueClusterPill: View {
    let cluster: VenueCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 34, minHeight: 34)
            .background(ScoreTier(score: cluster.bestScore).color, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
    }
}
