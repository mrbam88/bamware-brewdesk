import SwiftUI
import VenueKit

extension ScoreTier {
    public var color: Color {
        switch self {
        case .great: .green
        case .good: .teal
        case .mixed: .orange
        case .weak: .red
        }
    }
}

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.subheadline.monospacedDigit().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ScoreTier(score: score).color, in: Capsule())
            .accessibilityLabel("Work score \(score)")
    }
}

struct AttributeGlyph: View {
    let systemImage: String
    let text: String
    var dimmed = false

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(dimmed ? .tertiary : .secondary)
    }
}

/// One attribute row with full provenance — the trust UI.
struct ClaimRow: View {
    let title: String
    let systemImage: String
    let claim: Claim

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Spacer()
                Text(displayValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(claim.isEstimate ? Color.orange : Color.primary)
            }
            Text("\(claim.sourceLabel) · \(claim.confidencePercent)% confidence · \(claim.observedAt.prefix(10))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let detail = claim.detail, !claim.isEstimate, detail != claim.sourceLabel {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let window = claim.timeWindow {
                Text("applies: \(window)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayValue: String {
        if let range = claim.mbpsRange, range.count == 2 {
            return range[0] == range[1]
                ? "\(claim.value) · \(range[0].formatted(.number.precision(.fractionLength(0)))) Mbps"
                : "\(claim.value) · \(range[0].formatted(.number.precision(.fractionLength(0))))–\(range[1].formatted(.number.precision(.fractionLength(0)))) Mbps"
        }
        return claim.value.replacingOccurrences(of: "_", with: " ")
    }
}

struct VibeChips: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}
