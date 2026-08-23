import SwiftUI
import UIKit
import VenueKit

extension ScoreTier {
    /// Warm Utilitarian re-map (brewdesk#98): tier colours now progress
    /// green → sage → sand → destructive (was moss/ocean/clay/berry). Fill
    /// only — these sit behind fixed white badge/pin text in both
    /// appearances, so each value stays static rather than adaptive.
    public var color: Color {
        switch self {
        case .great: BrewDeskPalette.roast
        case .good: BrewDeskPalette.moss
        case .mixed: BrewDeskPalette.sand
        case .weak: BrewDeskPalette.berry
        }
    }
}

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(BrewDeskFont.label(.subheadline))
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
/// "Updated Aug 15 · curated" — the newest observation date across a venue's
/// claims plus its source kind. Says "updated", never "verified": data is
/// AI-researched unless a human source stands behind the claim (seal icon).
/// A venue whose tier is `osm-baseline`, or whose newest claim is
/// `source: "osm"`, renders "OSM baseline · updated <date>" instead (ve#46,
/// bd#108) — the OSM tier-0 import is real venues with unverified
/// attributes, never "curated".
struct ProvenanceStamp: View {
    let attributes: VenueAttributes
    var tier: String?

    var body: some View {
        if let newest = Self.newestClaim(in: attributes),
           let date = Self.observationDate(of: newest) {
            Label {
                if Self.isOSMBaseline(tier: tier, source: newest.source) {
                    Text("OSM baseline · updated \(date, format: .dateTime.month(.abbreviated).day())")
                } else {
                    Text("Updated \(date, format: .dateTime.month(.abbreviated).day()) · \(Self.sourceKind(of: newest))")
                }
            } icon: {
                Image(systemName: Self.humanSources.contains(newest.source)
                    ? "checkmark.seal.fill"
                    : "clock.badge.checkmark")
            }
            .font(.caption2)
            .foregroundStyle(Self.humanSources.contains(newest.source) ? BrewDeskPalette.mossText : .secondary)
            .accessibilityLabel(
                Self.isOSMBaseline(tier: tier, source: newest.source)
                    ? Text("OSM baseline · updated \(date, format: .dateTime.month(.wide).day())")
                    : Text("Updated \(date, format: .dateTime.month(.wide).day()), \(Self.sourceKind(of: newest))")
            )
            .accessibilityIdentifier("provenance-stamp")
        }
    }

    static func isOSMBaseline(tier: String?, source: String) -> Bool {
        tier == "osm-baseline" || source == "osm"
    }

    static func newestClaim(in attributes: VenueAttributes) -> Claim? {
        [attributes.wifi, attributes.outlets, attributes.laptopPolicy, attributes.noise]
            .compactMap { claim in observationDate(of: claim).map { (claim, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func observationDate(of claim: Claim) -> Date? {
        guard claim.observedAt.count >= 10 else { return nil }
        return Self.dayFormatter.date(from: String(claim.observedAt.prefix(10)))
    }

    static func sourceKind(of claim: Claim) -> String {
        switch claim.source {
        case "curated": String(localized: "curated")
        case "osm": "OSM"
        case "estimate": String(localized: "estimate")
        case "speed_test": String(localized: "measured")
        case "user_report": String(localized: "community")
        case "field_visit", "site_visit": String(localized: "site visit")
        case "owner": String(localized: "owner")
        case "agent": String(localized: "web research")
        default: claim.source
        }
    }

    /// Sources where a human stands behind the claim — these earn the seal.
    static let humanSources: Set<String> = ["curated", "field_visit", "site_visit", "speed_test", "owner"]

    nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

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
            .foregroundStyle(claim.isEstimate ? BrewDeskPalette.clayText : Color.primary)
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

func localizedWorkSpotCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "one_work_spot_count")
    }
    return String(
        format: String(localized: "%@ work spots"),
        locale: .current,
        count.formatted()
    )
}

/// Shown when location permission is denied or restricted. The app is already
/// serving NYC coverage at that point; the banner only says why "near me"
/// isn't, and offers the one fix. Never blocks content.
struct LocationDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            Label("Location is off — showing NYC.", systemImage: "location.slash")
                .font(.caption.bold())
            Spacer(minLength: 0)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.caption.bold())
            .accessibilityIdentifier("location-open-settings")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .brewDeskGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("location-denied-banner")
    }
}

/// Honest banner for a viewport the engine only has OSM tier-0 data for
/// (ve#46, bd#108) — shown whenever `VenuesModel.coverage == .baseline`.
/// Never claims "verified"; the methodology link explains what "baseline"
/// means. Replaces brewdesk#1's "You're outside NYC" fallback banner, which
/// used to substitute the NYC dataset for any far-away viewport instead of
/// querying it for real.
struct CoverageBaselineBanner: View {
    @State private var showMethodology = false

    var body: some View {
        HStack(spacing: 10) {
            Label("Baseline data here — not yet researched. NYC is fully researched.", systemImage: "map")
                .font(.caption.bold())
            Spacer(minLength: 0)
            Button("How scoring works") { showMethodology = true }
                .font(.caption.bold())
                .accessibilityIdentifier("methodology-link")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .brewDeskGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coverage-banner")
        .sheet(isPresented: $showMethodology) {
            NavigationStack { MethodologyScreen() }
        }
    }
}

/// Cold-start companion to the list/map (brewdesk#28): the rows on screen are
/// the bundled snapshot — say so, and say whether live data is on its way or
/// unreachable. Same glass capsule as `LocationDeniedBanner`.
struct SnapshotBanner: View {
    let state: VenuesModel.SnapshotBannerState
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text("Updating from live data…")
                    .font(.caption.bold())
            case .offline:
                Label("Offline — showing saved snapshot", systemImage: "wifi.exclamationmark")
                    .font(.caption.bold())
            }
            Spacer(minLength: 0)
            if state == .offline {
                Button("Retry", action: retry)
                    .font(.caption.bold())
                    .accessibilityIdentifier("snapshot-retry")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .brewDeskGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(state == .offline ? "snapshot-banner-offline" : "snapshot-banner-loading")
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
