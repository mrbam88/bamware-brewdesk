import SwiftUI
import VenueKit

public struct SavedCafesScreen: View {
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var model: SavedVenuesModel
    private let listing: (any VenueListing)?
    private let browseNearby: (() -> Void)?

    public init(
        savedVenues: SavedVenuesStore,
        venueDetails: any VenueDetailServing,
        listing: (any VenueListing)? = nil,
        browseNearby: (() -> Void)? = nil
    ) {
        self.savedVenues = savedVenues
        self.listing = listing
        self.browseNearby = browseNearby
        _model = State(initialValue: SavedVenuesModel(service: venueDetails))
    }

    public var body: some View {
        content
            .toolbar {
                // Account entry (brewdesk#48). AccountScreen resolves its own
                // services, so this stays a single additive toolbar item.
                // Hidden in the store-submission build (brewdesk#67).
                if !StoreSurface.isGated {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            AccountScreen()
                        } label: {
                            Label("Account", systemImage: "person.circle")
                        }
                        .accessibilityIdentifier("account-entry")
                    }
                }
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
                    ProgressView("Loading saved cafés…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("saved-state-loading")
                }
            case .failed:
                ContentUnavailableView {
                    Label("Saved cafés unavailable", systemImage: "wifi.exclamationmark")
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
            Text("Bookmark a café from Explore or Nearby to keep it here.")
        } actions: {
            if let browseNearby {
                Button("Browse Nearby") { browseNearby() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("saved-browse-nearby")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-state-empty")
    }

    /// Some saved IDs failed to hydrate: show what loaded, say what didn't.
    private var partialFailureBanner: some View {
        HStack(spacing: 10) {
            Label("Some saved cafés couldn't load.", systemImage: "exclamationmark.triangle")
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
