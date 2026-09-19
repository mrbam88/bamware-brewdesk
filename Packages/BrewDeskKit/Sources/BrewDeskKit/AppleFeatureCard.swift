import CoreLocation
import MapKit
import SwiftUI
import VenueKit

/// "Not in BrewDesk yet" card (bd#182) for a tapped Apple base-map café
/// label — or a tapped gap-fill marker — that didn't match one of our
/// venues. Presented as a `.sheet` from `CafeMapScreen`, same detent
/// mechanism `VenueDetailScreen`'s sheet uses, just a short fixed height:
/// name, distance, the badge, Directions, and Suggest — nothing else, by
/// design (this is Apple's own free data, not one of our researched venues).
struct AppleFeatureCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.launchEnvironment) private var launchEnvironment
    let candidate: AppleCafeCandidate
    /// Distance is measured from here — the map's current viewport center
    /// (real location once permitted, the NYC anchor otherwise), the same
    /// reference `VenuesModel` already uses for `distanceM` elsewhere.
    let referenceCoordinate: CLLocationCoordinate2D
    /// Resolved async by `CafeMapScreen` (`AppleCafeDetailsResolver`); `nil`
    /// until it lands, or forever on the UI-test fixture path. Directions
    /// works either way.
    let resolvedMapItem: MKMapItem?
    let suggesting: any CafeSuggesting

    enum SuggestState: Equatable { case idle, sending, sent, failed }
    @State private var suggestState: SuggestState = .idle

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.name)
                    .font(.title3.bold())
                    .accessibilityIdentifier("apple-feature-name")
                Text(distanceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("apple-feature-distance")
            }

            notInBrewDeskBadge

            HStack(spacing: 10) {
                Button {
                    openDirections()
                } label: {
                    actionLabel("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .accessibilityHint("Opens walking directions in Apple Maps")
                .accessibilityIdentifier("apple-feature-directions")

                Button {
                    Task { await suggest() }
                } label: {
                    actionLabel(suggestTitle, systemImage: suggestSystemImage)
                }
                .disabled(suggestState == .sending || suggestState == .sent)
                .accessibilityIdentifier("apple-feature-suggest")
                .accessibilityValue(suggestState == .sent ? "Sent" : "")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("apple-feature-card")
    }

    private var notInBrewDeskBadge: some View {
        // `BrewDeskPalette.unobserved`: the same neutral grey "not checked
        // yet" uses (bd#159) — deliberately never red/green (the founder is
        // red-green colorblind), and here it doubles as "not even ours yet".
        Text("Not in BrewDesk yet")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(BrewDeskPalette.unobserved, in: Capsule())
            .accessibilityIdentifier("apple-feature-not-in-brewdesk-badge")
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body.bold())
            Text(title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(theme.primaryColor)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    private var distanceLabel: String {
        let meters = VenuesModel.metersBetween(
            referenceCoordinate.latitude, referenceCoordinate.longitude,
            candidate.coordinate.latitude, candidate.coordinate.longitude
        )
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }

    private var suggestTitle: String {
        switch suggestState {
        case .idle, .failed: "Suggest this café"
        case .sending: "Suggesting…"
        case .sent: "Suggested"
        }
    }

    private var suggestSystemImage: String {
        suggestState == .sent ? "checkmark.circle.fill" : "plus.circle"
    }

    private func openDirections() {
        // Same UI-test seam `VenueDetailScreen.openDirections()` uses: a
        // scenario launch never hands off to Apple Maps (flaky at best,
        // fatal to the test runner at worst).
        guard launchEnvironment.scenario == nil else { return }
        let item: MKMapItem
        if let resolvedMapItem {
            item = resolvedMapItem
        } else {
            let placemark = MKPlacemark(coordinate: candidate.coordinate)
            item = MKMapItem(placemark: placemark)
            item.name = candidate.name
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func suggest() async {
        guard suggestState != .sending, suggestState != .sent else { return }
        suggestState = .sending
        do {
            try await suggesting.suggestCafe(
                CafeSuggestion(
                    name: candidate.name,
                    lat: candidate.coordinate.latitude,
                    lng: candidate.coordinate.longitude
                )
            )
            suggestState = .sent
        } catch {
            suggestState = .failed
        }
    }
}
