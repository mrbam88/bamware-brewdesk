import BamwareUI
import MapKit
import SwiftUI
import VenueKit

public struct VenueDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.venuePhotoService) private var photoService
    private let venue: Venue
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var photos: [VenuePhoto] = []
    @State private var expandedPhoto: VenuePhoto?
    @State private var photoLoad: PhotoLoad = .loading
    @State private var photoAttempt = 0
    @State private var failedThumbnailURLs: Set<String> = []

    private enum PhotoLoad { case loading, loaded, failed }

    public init(venue: Venue, savedVenues: SavedVenuesStore) {
        self.venue = venue
        self.savedVenues = savedVenues
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                photoSection
                workability
                if let hours = venue.hoursRaw {
                    informationCard(title: "Hours", systemImage: "clock") {
                        Text(hours)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 100)
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actionDock }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photoAttempt) {
            guard let photoService else { return }
            photoLoad = .loading
            do {
                photos = try await photoService.fetchPhotos(venueId: venue.id)
                photoLoad = .loaded
            } catch is CancellationError {
                // View went away; nothing to show.
            } catch {
                guard !Task.isCancelled else { return }
                photoLoad = .failed
            }
        }
    }

    /// Photos are optional content: while loading, or when the engine has none,
    /// the section collapses (no layout jump for the common case — same policy
    /// as the stat strip). A *failed* fetch is different: it gets a compact,
    /// intentional row with a Retry, never a silent gap.
    @ViewBuilder
    private var photoSection: some View {
        switch photoLoad {
        case .loaded where !photos.isEmpty:
            photoStrip
        case .failed:
            photoStripError
        default:
            EmptyView()
        }
    }

    private var photoStripError: some View {
        HStack(spacing: 10) {
            Label("Photos unavailable", systemImage: "photo")
            Spacer(minLength: 0)
            Button("Retry") { photoAttempt += 1 }
                .accessibilityIdentifier("photos-retry")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo-strip-error")
    }

    /// Google Places photos, display-only. Thumbnails omit author attribution
    /// (Places policy allows this for space-limited galleries) BECAUSE the
    /// tap-to-expand viewer shows the full attribution — keep both in sync.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(photos) { photo in
                    let thumbnailFailed = failedThumbnailURLs.contains(photo.url)
                    Button {
                        expandedPhoto = photo
                    } label: {
                        AsyncImage(url: URL(string: photo.url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                // Unloadable image: a glyph, not a forever-grey
                                // rectangle. Still tappable — the viewer has Retry.
                                ZStack {
                                    Rectangle().fill(.quaternary)
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear { failedThumbnailURLs.insert(photo.url) }
                            default:
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .frame(width: 210, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Photo of \(venue.name)"))
                    .accessibilityValue(thumbnailFailed ? Text("Photo unavailable") : Text(verbatim: ""))
                    .accessibilityHint(Text("Opens the full-size photo"))
                    .accessibilityIdentifier(thumbnailFailed ? "photo-thumb-failed" : "photo-thumb")
                }
            }
        }
        .frame(height: 140)
        .accessibilityIdentifier("venue-photo-strip")
        .sheet(item: $expandedPhoto) { photo in
            PhotoViewer(photo: photo, venueName: venue.name)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmartText(venue.name, theme: theme)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ScoreBadge(score: venue.workScore)
                    locationSummary
                }
                VStack(alignment: .leading, spacing: 10) {
                    ScoreBadge(score: venue.workScore)
                    locationSummary
                }
            }

            if !venue.vibeTags.isEmpty {
                VibeChips(tags: venue.vibeTags)
            }

            NavigationLink {
                MethodologyScreen()
            } label: {
                // ≥44pt hit region + espresso at footnote size: passes the
                // accessibility audit (hit area + contrast on foam) — bd#36.
                Label("How scoring works", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("methodology-link")
        }
        .padding(20)
        .background(BrewDeskPalette.foam.opacity(colorScheme == .dark ? 0.08 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(BrewDeskPalette.espresso.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var locationSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(venue.neighborhood) · \(venue.borough)")
                .font(.headline)
            if let address = venue.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workability: some View {
        informationCard(title: "Workability", systemImage: "checkmark.seal") {
            VStack(spacing: 14) {
                ClaimRow(title: "Wi-Fi", systemImage: "wifi", claim: venue.attributes.wifi)
                Divider()
                ClaimRow(title: "Outlets", systemImage: "powerplug", claim: venue.attributes.outlets)
                Divider()
                ClaimRow(
                    title: "Laptop policy",
                    systemImage: "laptopcomputer",
                    claim: venue.attributes.laptopPolicy
                )
                Divider()
                ClaimRow(title: "Noise", systemImage: "speaker.wave.2", claim: venue.attributes.noise)
            }
        }
    }

    private func informationCard<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(BrewDeskPalette.roast)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actionDock: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(spacing: 8) { actionButtons }
        }
        .padding(10)
        .brewDeskGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-dock")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            openDirections()
        } label: {
            actionLabel("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .accessibilityHint("Opens walking directions in Apple Maps")

        Button {
            savedVenues.toggle(venue.id)
        } label: {
            actionLabel(
                savedVenues.contains(venue.id) ? "saved_action_title" : "save_action_title",
                systemImage: savedVenues.contains(venue.id) ? "bookmark.fill" : "bookmark"
            )
        }
        .accessibilityValue(savedVenues.contains(venue.id) ? "Saved" : "Not saved")

        ShareLink(item: shareText) {
            actionLabel("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body.bold())
            Text(title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
        }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 8)
            .foregroundStyle(theme.primaryColor)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
    }

    private var shareText: String {
        "\(venue.name) · Work Fit \(venue.workScore) · \(venue.neighborhood)"
    }

    private func openDirections() {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
        )
        let item = MKMapItem(placemark: placemark)
        item.name = venue.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
