import SwiftUI
import VenueKit

public struct SavedCafesScreen: View {
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var model: SavedVenuesModel
    private let listing: (any VenueListing)?
    private let browseSpots: (() -> Void)?

    public init(
        savedVenues: SavedVenuesStore,
        venueDetails: any VenueDetailServing,
        listing: (any VenueListing)? = nil,
        browseSpots: (() -> Void)? = nil
    ) {
        self.savedVenues = savedVenues
        self.listing = listing
        self.browseSpots = browseSpots
        _model = State(initialValue: SavedVenuesModel(service: venueDetails))
    }

    public var body: some View {
        content
            .toolbar {
                // brewdesk#117: the Account entry point moved to the You
                // tab (AccountScreen is now that tab's root), so Saved's
                // toolbar carries only Import.
                if let listing {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ImportSavedScreen(savedVenues: savedVenues, listing: listing)
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("import-saved-entry")
                    }
                }
            }
    }

    private var content: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                if savedVenues.venueIDs.isEmpty {
                    emptyState
                } else {
                    ProgressView("Loading saved spots…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("saved-state-loading")
                }
            case .failed:
                ContentUnavailableView {
                    Label("Saved spots unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Retry") {
                        Task { await model.load(venueIDs: savedVenues.venueIDs) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("saved-retry")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("saved-state-error")
            default:
                if savedVenues.venueIDs.isEmpty {
                    emptyState
                } else {
                    List {
                        if model.failedCount > 0 {
                            partialFailureBanner
                        }
                        ForEach(model.venues) { venue in
                            NavigationLink(value: venue) {
                                VenueRow(venue: venue)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await model.load(venueIDs: savedVenues.venueIDs) }
                }
            }
        }
        // Cream page treatment for brand cohesion (finding 3).
        .background(BrewDeskPalette.page.ignoresSafeArea())
        .navigationTitle("saved_tab_title")
        .navigationDestination(for: Venue.self) { venue in
            VenueDetailScreen(venue: venue, savedVenues: savedVenues)
        }
        .task(id: savedVenues.venueIDs) {
            await model.load(venueIDs: savedVenues.venueIDs)
        }
    }

    /// Empty state with a way out: "go bookmark a cafe" now carries the
    /// button that gets you there (ui-review-2026-08-21 finding 5).
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Save your next work spot", systemImage: "bookmark")
        } description: {
            Text("Bookmark a spot from Explore or Nearby to keep it here.")
        } actions: {
            if let browseSpots {
                Button("Browse Spots") { browseSpots() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("saved-browse-spots")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-state-empty")
    }

    /// Some saved IDs failed to hydrate: show what loaded, say what didn't.
    private var partialFailureBanner: some View {
        HStack(spacing: 10) {
            Label("Some saved spots couldn't load.", systemImage: "exclamationmark.triangle")
            Spacer(minLength: 0)
            Button("Retry") {
                Task { await model.load(venueIDs: savedVenues.venueIDs) }
            }
            .accessibilityIdentifier("saved-partial-retry")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-partial-banner")
    }
}
