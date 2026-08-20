import SwiftUI
import VenueKit

public struct SavedCafesScreen: View {
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var model: SavedVenuesModel
    private let listing: (any VenueListing)?

    public init(
        savedVenues: SavedVenuesStore,
        venueDetails: any VenueDetailServing,
        listing: (any VenueListing)? = nil
    ) {
        self.savedVenues = savedVenues
        self.listing = listing
        _model = State(initialValue: SavedVenuesModel(service: venueDetails))
    }

    public var body: some View {
        content
            .toolbar {
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
                }
            default:
                if savedVenues.venueIDs.isEmpty {
                    emptyState
                } else {
                    List(model.venues) { venue in
                        NavigationLink(value: venue) {
                            VenueRow(venue: venue)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await model.load(venueIDs: savedVenues.venueIDs) }
                }
            }
        }
        .navigationTitle("saved_tab_title")
        .navigationDestination(for: Venue.self) { venue in
            VenueDetailScreen(venue: venue, savedVenues: savedVenues)
        }
        .task(id: savedVenues.venueIDs) {
            await model.load(venueIDs: savedVenues.venueIDs)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Save your next work spot", systemImage: "bookmark")
        } description: {
            Text("Bookmark a café from Explore or Nearby to keep it here.")
        }
    }
}
