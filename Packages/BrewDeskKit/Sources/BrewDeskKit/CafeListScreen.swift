import SwiftUI
import VenueKit

public struct CafeListScreen: View {
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
                case .idle, .loading:
                    ProgressView("Finding work-friendly cafes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    ContentUnavailableView {
                        Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { model.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                case .loaded:
                    if model.venues.isEmpty {
                        ContentUnavailableView {
                            Label("No cafes found", systemImage: "cup.and.saucer")
                        } description: {
                            Text("Try widening your filters or search area.")
                        } actions: {
                            Button("Browse NYC") { model.browseCoverageCenter() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        List {
                            DatasetStatStrip(model: model)
                                .listRowSeparator(.hidden)
                            venueRows
                        }
                        .listStyle(.plain)
                        .refreshable { model.retry() }
                    }
                }
            }
            .navigationTitle("Nearby")
            .navigationDestination(for: Venue.self) { venue in
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
            }
            .searchable(text: $model.searchQuery, prompt: "Search cafés")
            .onSubmit(of: .search) { model.submitSearch() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
        }
    }

    private var venueRows: some View {
        ForEach(model.venues) { venue in
            NavigationLink(value: venue) {
                VenueRow(venue: venue)
            }
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

    private var filterMenu: some View {
        Menu {
            Toggle("Laptop-friendly only", isOn: $model.laptopFriendlyOnly)
            Picker("Wifi", selection: $model.minWifi) {
                Text("Any Wi-Fi").tag(WifiMinimum?.none)
                Text("OK or better").tag(WifiMinimum?.some(.ok))
                Text("Fast only").tag(WifiMinimum?.some(.fast))
            }
            Picker("Outlets", selection: $model.minOutlets) {
                Text("Any outlets").tag(OutletMinimum?.none)
                Text("Some or better").tag(OutletMinimum?.some(.some))
                Text("Plenty").tag(OutletMinimum?.some(.plenty))
            }
            Picker("Seating", selection: $model.minSeating) {
                Text("Any seating").tag(SeatingMinimum?.none)
                Text("Some or better").tag(SeatingMinimum?.some(.some))
                Text("Plenty").tag(SeatingMinimum?.some(.plenty))
            }
            if model.venueTypesAvailable {
                Picker("Spot type", selection: $model.venueType) {
                    Text("All spots").tag(VenueTypeFilter?.none)
                    ForEach(VenueTypeFilter.allCases, id: \.rawValue) { type in
                        Text(LocalizedStringKey(type.rawValue)).tag(VenueTypeFilter?.some(type))
                    }
                }
            }
        } label: {
            Label("Filters", systemImage: filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }

    private var filtersActive: Bool {
        model.laptopFriendlyOnly || model.minWifi != nil || model.minOutlets != nil
            || model.minSeating != nil || model.venueType != nil
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
                ProvenanceStamp(attributes: venue.attributes)
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
                .foregroundStyle(BrewDeskPalette.berry)
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
