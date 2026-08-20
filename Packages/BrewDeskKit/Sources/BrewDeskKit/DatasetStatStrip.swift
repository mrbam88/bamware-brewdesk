import SwiftUI
import VenueKit

/// One line of dataset-level provenance: "127 cafés · 480 observations ·
/// updated Aug 15". Renders what the health payload provides and nothing
/// when it is absent — the screens must not shift when the strip hides.
struct DatasetStatStrip: View {
    @Bindable var model: VenuesModel

    var body: some View {
        Group {
            if let health = model.health, health.ok {
                Text(text(for: health))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("dataset-stat-strip")
            }
        }
        .task { await model.loadHealth() }
    }

    private func text(for health: HealthResponse) -> String {
        let updated = ProvenanceStamp.observationDate(of: Claim(
            value: "", source: "", confidence: 0, observedAt: health.seededAt
        ))
        switch (health.observationCount, updated) {
        case let (.some(observations), .some(date)):
            return String(
                format: String(localized: "%1$lld cafés · %2$lld observations · updated %3$@"),
                locale: .current,
                health.venueCount,
                observations,
                date.formatted(.dateTime.month(.abbreviated).day())
            )
        case let (nil, .some(date)):
            return String(
                format: String(localized: "%1$lld cafés · updated %2$@"),
                locale: .current,
                health.venueCount,
                date.formatted(.dateTime.month(.abbreviated).day())
            )
        default:
            return String(
                format: String(localized: "%lld cafés"),
                locale: .current,
                health.venueCount
            )
        }
    }
}
