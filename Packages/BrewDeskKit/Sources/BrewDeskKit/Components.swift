import SwiftUI
import VenueKit

extension ScoreTier {
    public var color: Color {
        switch self {
        case .great: BrewDeskPalette.moss
        case .good: BrewDeskPalette.ocean
        case .mixed: BrewDeskPalette.clay
        case .weak: BrewDeskPalette.berry
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
            .padding(.vertical, 6)
            .background(ScoreTier(score: score).color, in: Capsule())
            .accessibilityLabel("Work Fit \(score) out of 100")
    }
}

struct AttributeGlyph: View {
    let systemImage: String
    let text: String
    var dimmed = false

    var body: some View {
        Label(localizedAttributeValue(text), systemImage: systemImage)
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    claimTitle
                    Spacer()
                    claimValue
                }
                VStack(alignment: .leading, spacing: 4) {
                    claimTitle
                    claimValue
                }
            }
            Text(evidenceSummary)
                .font(.caption2)
                .foregroundStyle(.primary)
            if let detail = claim.detail, !claim.isEstimate, detail != claim.sourceLabel {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            if let window = claim.timeWindow {
                Text("applies: \(window)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(displayValue), \(sourceLabel), " +
            "\(claim.confidencePercent) percent confidence, observed \(claim.observedAt.prefix(10))"
        )
    }

    private var claimTitle: some View {
        Label {
            Text(LocalizedStringKey(title))
                .font(.subheadline)
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var claimValue: some View {
        Text(displayValue)
            .font(.subheadline.bold())
            .foregroundStyle(claim.isEstimate ? BrewDeskPalette.clay : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var displayValue: String {
        if let range = claim.mbpsRange, range.count == 2 {
            return range[0] == range[1]
                ? "\(localizedAttributeValue(claim.value)) · \(range[0].formatted(.number.precision(.fractionLength(0)))) Mbps"
                : "\(localizedAttributeValue(claim.value)) · \(range[0].formatted(.number.precision(.fractionLength(0))))–\(range[1].formatted(.number.precision(.fractionLength(0)))) Mbps"
        }
        return localizedAttributeValue(claim.value)
    }

    private var sourceLabel: String {
        switch claim.source {
        case "curated": String(localized: "Curated")
        case "osm": String(localized: "OpenStreetMap")
        case "estimate": String(localized: "Unverified estimate")
        case "speed_test": String(localized: "Measured in app")
        case "user_report": String(localized: "User report")
        case "field_visit": String(localized: "Field verified")
        default: claim.source
        }
    }

    private var evidenceSummary: String {
        String(
            format: String(localized: "%1$@ · %2$lld%% confidence · %3$@"),
            locale: .current,
            sourceLabel,
            claim.confidencePercent,
            String(claim.observedAt.prefix(10))
        )
    }
}

func localizedAttributeValue(_ value: String) -> String {
    switch value {
    case "fast": String(localized: "Fast")
    case "ok": String(localized: "OK")
    case "slow": String(localized: "Slow")
    case "plenty": String(localized: "Plenty")
    case "some": String(localized: "Some")
    case "scarce": String(localized: "Scarce")
    case "unrestricted": String(localized: "Unrestricted")
    case "time_limited": String(localized: "Time limited")
    case "weekend_banned": String(localized: "No laptops on weekends")
    case "discouraged": String(localized: "Discouraged")
    case "quiet": String(localized: "Quiet")
    case "moderate": String(localized: "Moderate")
    case "lively": String(localized: "Lively")
    case "unknown": String(localized: "Unknown")
    default: value.replacingOccurrences(of: "_", with: " ")
    }
}

func localizedWorkCafeCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "one_work_cafe_count")
    }
    return String(
        format: String(localized: "%@ work cafés"),
        locale: .current,
        count.formatted()
    )
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
