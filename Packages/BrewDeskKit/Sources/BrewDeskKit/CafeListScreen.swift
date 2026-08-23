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
                    ProgressView("Finding work-friendly cafes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("list-state-loading")
                case .failed:
                    ContentUnavailableView {
                        Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
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
                            Label("No cafes found", systemImage: "cup.and.saucer")
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
            .searchable(text: $model.searchQuery, prompt: "Search cafés")
            .onSubmit(of: .search) { model.submitSearch() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
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

    /// Each filter group is a labeled submenu naming its dimension (the menu
    /// picker style also surfaces the current selection on the row), and a
    /// Reset row clears everything — the old menu was nine unlabeled options
    /// the user had to decode (ui-review-2026-08-21 finding 10).
    /// `Section("…")` headers were tried first but `Menu` does not render
    /// them; labeled submenu pickers carry the same information.
    private var filterMenu: some View {
        Menu {
            Toggle("Laptop-friendly only", isOn: $model.laptopFriendlyOnly)
            Picker("Wi-Fi", selection: $model.minWifi) {
                Text("Any Wi-Fi").tag(WifiMinimum?.none)
                Text("OK or better").tag(WifiMinimum?.some(.ok))
                Text("Fast only").tag(WifiMinimum?.some(.fast))
            }
            .pickerStyle(.menu)
            Picker("Outlets", selection: $model.minOutlets) {
                Text("Any outlets").tag(OutletMinimum?.none)
                Text("Some or better").tag(OutletMinimum?.some(.some))
                Text("Plenty").tag(OutletMinimum?.some(.plenty))
            }
            .pickerStyle(.menu)
            Picker("Seating", selection: $model.minSeating) {
                Text("Any seating").tag(SeatingMinimum?.none)
                Text("Some or better").tag(SeatingMinimum?.some(.some))
                Text("Plenty").tag(SeatingMinimum?.some(.plenty))
            }
            .pickerStyle(.menu)
            if model.venueTypesAvailable {
                Picker("Spot type", selection: $model.venueType) {
                    Text("All spots").tag(VenueTypeFilter?.none)
                    ForEach(VenueTypeFilter.allCases, id: \.rawValue) { type in
                        Text(LocalizedStringKey(type.rawValue)).tag(VenueTypeFilter?.some(type))
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button("Reset all filters", systemImage: "arrow.counterclockwise") {
                    resetFilters()
                }
                .disabled(!filtersActive)
                .accessibilityIdentifier("filters-reset")
            }
        } label: {
            Label("Filters", systemImage: filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        // One light tick per dimension change — covers apply AND reset,
        // since reset is only enabled when a dimension is active, so it
        // always flips at least one of these (brewdesk#75). `.sensoryFeedback`
        // already no-ops under Reduce Motion.
        .sensoryFeedback(.selection, trigger: model.laptopFriendlyOnly)
        .sensoryFeedback(.selection, trigger: model.minWifi)
        .sensoryFeedback(.selection, trigger: model.minOutlets)
        .sensoryFeedback(.selection, trigger: model.minSeating)
        .sensoryFeedback(.selection, trigger: model.venueType)
    }

    private func resetFilters() {
        model.laptopFriendlyOnly = false
        model.minWifi = nil
        model.minOutlets = nil
        model.minSeating = nil
        model.venueType = nil
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
