import SwiftUI
import VenueKit

public struct SavedCafesScreen: View {
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var model: SavedVenuesModel
    /// Bamware Picks (bamware-ai#301). Hidden unless the engine serves at
    /// least one pick; see `PicksModel`.
    @State private var picksModel: PicksModel
    private let venueDetails: any VenueDetailServing
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
        self.venueDetails = venueDetails
        _model = State(initialValue: SavedVenuesModel(service: venueDetails))
        // The live client and the fixture service both serve picks; a
        // service that cannot simply has no Picks section.
        _picksModel = State(initialValue: PicksModel(service: venueDetails as? any PicksServing))
    }

    public var body: some View {
        content
            .safeAreaInset(edge: .top) { syncStatusLine }
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
            if picksModel.isVisible {
                listWithPicks
            } else {
                savedOnly
            }
        }
        // Cream page treatment for brand cohesion (finding 3).
        .background(BrewDeskPalette.page.ignoresSafeArea())
        .navigationTitle("saved_tab_title")
        .navigationDestination(for: Venue.self) { venue in
            VenueDetailScreen(venue: venue, savedVenues: savedVenues)
        }
        .navigationDestination(for: Pick.self) { pick in
            PickDetailLoader(
                pick: pick,
                service: venueDetails,
                savedVenues: savedVenues,
                preloaded: model.venues.first { $0.id == pick.venue.id }
            )
        }
        .task(id: savedVenues.venueIDs) {
            await model.load(venueIDs: savedVenues.venueIDs)
        }
        .task { await picksModel.load() }
    }

    /// Picks above the user's own saved spots, in one scrolling list. With
    /// nothing saved yet, Picks fills the screen and the "save your next
    /// work spot" prompt sits underneath as a compact row.
    private var listWithPicks: some View {
        List {
            PicksSectionHeader(updatedAt: picksModel.updatedAt)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(picksModel.picks) { pick in
                NavigationLink(value: pick) {
                    PickRow(
                        pick: pick,
                        isSaved: savedVenues.contains(pick.venue.id),
                        toggleSaved: { savedVenues.toggle(pick.venue.id) }
                    )
                }
                .listRowBackground(Color.clear)
            }

            SavedSpotsSubheader()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            savedRowsUnderPicks
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await picksModel.load()
            await model.load(venueIDs: savedVenues.venueIDs)
        }
        .accessibilityIdentifier("saved-list-with-picks")
    }

    /// The user's own list as rows under Picks. Each state is a row, never
    /// a full-screen takeover, so Picks stays put while saved spots load,
    /// fail or sit empty.
    @ViewBuilder
    private var savedRowsUnderPicks: some View {
        if savedVenues.venueIDs.isEmpty {
            compactEmptyState
        } else if case .failed = model.phase {
            HStack(spacing: 10) {
                Label("Saved spots unavailable", systemImage: "wifi.exclamationmark")
                Spacer(minLength: 0)
                Button("Retry") {
                    Task { await model.load(venueIDs: savedVenues.venueIDs) }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("saved-retry")
            }
            .font(.subheadline)
            .foregroundStyle(BrewDeskPalette.secondaryText)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("saved-state-error")
        } else if model.venues.isEmpty {
            ProgressView("Loading saved spots…")
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("saved-state-loading")
        } else {
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
    }

    /// The empty state when Picks is on screen: same words and the same way
    /// out as the full-screen one, sized as a row.
    private var compactEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Save your next work spot", systemImage: "bookmark")
                .font(.headline)
                .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
            Text("Bookmark a spot from Spots to keep it here.")
                .font(.subheadline)
                .foregroundStyle(BrewDeskPalette.secondaryText)
            if let browseSpots {
                Button("Browse Spots") { browseSpots() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                    .accessibilityIdentifier("saved-browse-spots")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-state-empty")
    }

    /// The Saved tab exactly as it was before Picks: what shows whenever
    /// there are no picks to show.
    private var savedOnly: some View {
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
    }

    /// The Saved tab's one-line sync status (bamware-brewdesk#175) —
    /// nothing else: no per-spot sync UI, no conflict UI, no nag to sign
    /// in. `SavedVenuesStore.syncStatus` reports `.localOnly` for both
    /// "signed out" and "signed in but not synced yet/right now", which is
    /// exactly what this line is allowed to say.
    private var syncStatusLine: some View {
        Text(savedVenues.syncStatus == .synced ? "Synced" : "Local only")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 6)
            // Opaque, full width: with Picks the list is long enough to
            // scroll under this pinned line, and rows showed through it.
            .frame(maxWidth: .infinity)
            .background(BrewDeskPalette.page)
            .accessibilityIdentifier("saved-sync-status")
    }

    /// Empty state with a way out: "go bookmark a cafe" now carries the
    /// button that gets you there (ui-review-2026-08-21 finding 5).
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Save your next work spot", systemImage: "bookmark")
        } description: {
            Text("Bookmark a spot from Spots to keep it here.")
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
