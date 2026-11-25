import SwiftUI
import VenueKit

// Bamware Picks (bamware-ai#301) on the Saved tab: a short, ranked list of
// work cafés the founder has sat in, above the user's own saved spots.
//
// The views here are rows for the Saved tab's `List`; `SavedCafesScreen`
// decides whether they appear at all (`PicksModel.isVisible`). Colours are
// `BrewDeskPalette` tokens only, all neutral: the one hue on a row is the
// Work Fit badge's own ring, exactly as it is everywhere else.

/// "Bamware Picks" / "Hand-picked by us. Never paid for." / "Updated Nov 24".
struct PicksSectionHeader: View {
    let updatedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Bamware Picks")
                    .font(BrewDeskFont.headline(.title3))
                    .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
            } icon: {
                Image(systemName: "rosette")
                    .font(.title3)
                    .foregroundStyle(BrewDeskPalette.primaryText)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("picks-title")

            Text("Hand-picked by us. Never paid for.")
                .font(.subheadline)
                .foregroundStyle(BrewDeskPalette.secondaryText)
                .accessibilityIdentifier("picks-subline")

            if let updated = PicksWording.updated(updatedAt) {
                Text(updated)
                    .font(.caption)
                    .foregroundStyle(BrewDeskPalette.secondaryText)
                    .accessibilityIdentifier("picks-updated")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picks-section-header")
    }
}

/// One pick: rank numeral, café name, neighbourhood, the line in quotes,
/// the Work Fit badge as shown elsewhere (or "Not rated yet"), the visit
/// date, and a bookmark.
struct PickRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pick: Pick
    let isSaved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(pick.rank)")
                .font(BrewDeskFont.headline(.title2).monospacedDigit())
                .foregroundStyle(BrewDeskPalette.primaryText)
                // Wide enough for "10", so one to nine line up with it.
                .frame(minWidth: 30, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(pick.venue.name)
                    .font(.headline)
                    .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                HStack(spacing: 6) {
                    if let neighborhood = pick.venue.neighborhood, !neighborhood.isEmpty {
                        Text(neighborhood)
                            .font(.caption)
                            .foregroundStyle(BrewDeskPalette.secondaryText)
                    }
                    // Conditional here, unlike the shelf card: the badge's
                    // collapsed (zero-width) form still wraps its hidden
                    // label one letter per line and made every café row
                    // about 30pt taller than its content.
                    if pick.venue.typeBadge.showsBadge {
                        VenueTypeBadgeView(type: pick.venue.typeBadge)
                    }
                }

                Text(PicksWording.quoted(pick.blurb))
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
                    // The whole line always shows: it is the point of the row.
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ScoreBadge(displayScore: pick.venue.displayScore)
                        visited
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ScoreBadge(displayScore: pick.venue.displayScore)
                        visited
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element for the row's words; the bookmark beside it stays
            // its own button. The identifier lives here, not on the outer
            // HStack, where it would overwrite the bookmark's.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("pick-row-\(pick.rank)")

            Button(action: toggleSaved) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .foregroundStyle(BrewDeskPalette.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            // Borderless, so the bookmark is its own tap target inside the
            // row's navigation link instead of opening the detail screen.
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("save_action_title") + Text(verbatim: ", \(pick.venue.name)"))
            .accessibilityValue(isSaved ? "Saved" : "Not saved")
            .accessibilityIdentifier("pick-save-\(pick.rank)")
            .sensoryFeedback(.selection, trigger: isSaved)
        }
        .padding(.vertical, 8)
        // One left edge for every divider; the default follows each row's
        // first text and wandered from row to row.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    @ViewBuilder
    private var visited: some View {
        if let text = PicksWording.visited(pick.visitedAt) {
            Text(text)
                .font(.caption)
                .foregroundStyle(BrewDeskPalette.secondaryText)
        }
    }

    private var accessibilityLabel: String {
        var parts = [PicksWording.badgeAccessibilityLabel(rank: pick.rank), pick.venue.name]
        if let neighborhood = pick.venue.neighborhood, !neighborhood.isEmpty { parts.append(neighborhood) }
        if pick.venue.typeBadge.showsBadge { parts.append(pick.venue.typeBadge.displayName) }
        parts.append(
            pick.venue.displayScore.map { "Work Fit \($0)" } ?? String(localized: "Not rated yet")
        )
        parts.append(pick.blurb)
        if let visited = PicksWording.visited(pick.visitedAt) { parts.append(visited) }
        return parts.joined(separator: ", ")
    }
}

/// Small heading between Picks and the user's own list, so it is clear
/// where the curated list ends.
struct SavedSpotsSubheader: View {
    var body: some View {
        Text("Your saved spots")
            .font(BrewDeskFont.headline(.title3))
            .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("saved-spots-subheader")
    }
}

/// Opens a pick in the existing detail screen. A `/v1/picks` row carries
/// the compact venue (no claims, hours or links), so the full venue is
/// fetched by id first; `preloaded` skips the request when the Saved list
/// already holds it.
struct PickDetailLoader: View {
    let pick: Pick
    let service: any VenueDetailServing
    let savedVenues: SavedVenuesStore
    let preloaded: Venue?

    private enum Phase { case loading, loaded(Venue), failed }
    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loaded(let venue):
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrewDeskPalette.page.ignoresSafeArea())
                    .navigationTitle(pick.venue.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .accessibilityIdentifier("pick-detail-loading")
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't open this spot", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pick-detail-retry")
                }
                .background(BrewDeskPalette.page.ignoresSafeArea())
                .navigationTitle(pick.venue.name)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("pick-detail-error")
            }
        }
        .task { await load() }
    }

    private func load() async {
        if case .loaded = phase { return }
        if let preloaded {
            phase = .loaded(labelled(preloaded))
            return
        }
        phase = .loading
        do {
            let venue = try await service.fetchVenue(id: pick.venue.id)
            phase = .loaded(labelled(venue))
        } catch is CancellationError {
            // Left the screen; nothing to show.
        } catch {
            if !Task.isCancelled { phase = .failed }
        }
    }

    /// The detail screen draws its badge and line from `venue.pick`. The
    /// engine sends it on the detail response; if this one did not, the row
    /// the user tapped still says which pick it is.
    private func labelled(_ venue: Venue) -> Venue {
        venue.pick == nil ? venue.settingPick(pick.label) : venue
    }
}
