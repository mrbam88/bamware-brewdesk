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

    public init(venue: Venue, savedVenues: SavedVenuesStore) {
        self.venue = venue
        self.savedVenues = savedVenues
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                if !photos.isEmpty {
                    photoStrip
                }
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
        .task {
            guard let photoService else { return }
            photos = (try? await photoService.fetchPhotos(venueId: venue.id)) ?? []
        }
    }

    /// Google Places photos, display-only. Attribution overlays are a
    /// licensing requirement, not decoration.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(photos) { photo in
                    AsyncImage(url: URL(string: photo.url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 210, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if let attribution = photo.attribution {
                            Text(verbatim: attribution)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                    .accessibilityLabel(Text("Photo of \(venue.name)"))
                }
            }
        }
        .frame(height: 140)
        .accessibilityIdentifier("venue-photo-strip")
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
                Label("How scoring works", systemImage: "info.circle")
                    .font(.caption.bold())
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
            .foregroundStyle(BrewDeskPalette.espresso)
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
