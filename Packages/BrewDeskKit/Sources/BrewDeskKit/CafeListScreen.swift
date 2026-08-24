import SwiftUI
import VenueKit

public struct CafeListScreen: View {
    @Environment(\.locationDenied) private var locationDenied
    @Bindable private var model: VenuesModel
    @Bindable private var savedVenues: SavedVenuesStore

    public init(model: VenuesModel, savedVenues: SavedVenuesStore) {
        self.model = model
        self.savedVenues = savedVenues
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                // With the bundled snapshot on screen, loading and failure are
                // banners over real rows — never a spinner or a wall.
                case .idle where !model.venues.isEmpty, .loading where !model.venues.isEmpty,
                     .failed where !model.venues.isEmpty:
                    venueList
                case .idle, .loading:
                    ProgressView("Finding work spots…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("list-state-loading")
                case .failed:
                    ContentUnavailableView {
                        Label("Spot service unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { model.retry() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("list-retry")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("list-state-error")
                case .loaded:
                    if model.venues.isEmpty {
                        ContentUnavailableView {
                            Label("No spots found", systemImage: "cup.and.saucer")
                        } description: {
                            Text("Try widening your filters or search area.")
                        } actions: {
                            Button("Browse NYC") { model.browseCoverageCenter() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("list-browse-nyc")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("list-state-empty")
                    } else {
                        venueList
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if locationDenied || model.snapshotBanner != nil {
                    VStack(spacing: 6) {
                        if let state = model.snapshotBanner {
                            SnapshotBanner(state: state) { model.retry() }
                        }
                        if locationDenied {
                            LocationDeniedBanner()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            // Cream page treatment: Nearby spoke stock system gray while
            // Explore spoke the brand (ui-review-2026-08-21 finding 3).
            .background(BrewDeskPalette.page.ignoresSafeArea())
            .navigationTitle("Nearby")
            .navigationDestination(for: Venue.self) { venue in
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
            }
            .searchable(text: $model.searchQuery, prompt: "Search spots")
            .onSubmit(of: .search) { model.submitSearch() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WorkFitFilterButton(model: model)
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MethodologyScreen()
                    } label: {
                        Label("How scoring works", systemImage: "info.circle")
                    }
                }
            }
        }
    }

    private var venueList: some View {
        List {
            DatasetStatStrip(model: model)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            venueRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { model.retry() }
    }

    private var venueRows: some View {
        ForEach(model.venues) { venue in
            NavigationLink(value: venue) {
                VenueRow(venue: venue)
            }
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                Button {
                    savedVenues.toggle(venue.id)
                } label: {
                    Label(
                        savedVenues.contains(venue.id) ? "Unsave" : "Save",
                        systemImage: savedVenues.contains(venue.id)
                            ? "bookmark.slash"
                            : "bookmark"
                    )
                }
                .tint(BrewDeskPalette.moss)
            }
        }
    }

}

struct VenueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let venue: Venue

    var body: some View {
        HStack(spacing: 12) {
            ScoreBadge(score: venue.workScore)
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                HStack(spacing: 10) {
                    Text(venue.neighborhood)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let d = venue.distanceM {
                        Text(distance(d))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    AttributeGlyph(
                        systemImage: "wifi",
                        text: venue.attributes.wifi.value,
                        dimmed: venue.attributes.wifi.value == "unknown"
                    )
                    AttributeGlyph(
                        systemImage: "powerplug",
                        text: venue.attributes.outlets.value,
                        dimmed: venue.attributes.outlets.value == "unknown"
                    )
                    if venue.attributes.wifi.isEstimate {
                        Text("est.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    laptopPolicyMarker
                }
                ProvenanceStamp(attributes: venue.attributes, tier: venue.tier)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood), " +
            "Wi-Fi \(localizedAttributeValue(venue.attributes.wifi.value)), " +
            "outlets \(localizedAttributeValue(venue.attributes.outlets.value))"
        )
    }

    /// Laptop hostility is shown openly, never hidden: red "No laptops" for
    /// discouraged venues, orange time markers for conditional policies.
    @ViewBuilder
    private var laptopPolicyMarker: some View {
        switch venue.attributes.laptopPolicy.value {
        case "discouraged":
            Label("No laptops", systemImage: "laptopcomputer.slash")
                .font(.caption2.bold())
                .foregroundStyle(BrewDeskPalette.berryText)
                .accessibilityIdentifier("laptop-banned-marker")
        case "time_limited":
            Label("Time-limited", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.orange)
        case "weekends_banned":
            Label("No weekend laptops", systemImage: "clock.badge.exclamationmark")
                .font(.caption2)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private func distance(_ meters: Int) -> String {
        Measurement(value: Double(meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
