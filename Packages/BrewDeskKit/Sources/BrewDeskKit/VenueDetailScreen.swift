import SwiftUI
import VenueKit
import BamwareUI

public struct VenueDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    private let venue: Venue

    public init(venue: Venue) {
        self.venue = venue
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // Shared bamware-ios component with BrewDesk's theme.
                    SmartText(venue.name, theme: theme)
                        .font(.title2.bold())
                    HStack(spacing: 8) {
                        ScoreBadge(score: venue.workScore)
                        Text("\(venue.neighborhood) · \(venue.borough)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let address = venue.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !venue.vibeTags.isEmpty {
                        VibeChips(tags: venue.vibeTags)
                            .padding(.top, 4)
                    }
                }
                .listRowBackground(theme.backgroundColor)
            }

            Section("Workability") {
                ClaimRow(title: "Wifi", systemImage: "wifi", claim: venue.attributes.wifi)
                ClaimRow(title: "Outlets", systemImage: "powerplug", claim: venue.attributes.outlets)
                ClaimRow(title: "Laptop policy", systemImage: "laptopcomputer", claim: venue.attributes.laptopPolicy)
                ClaimRow(title: "Noise", systemImage: "speaker.wave.2", claim: venue.attributes.noise)
            }

            if let hours = venue.hoursRaw {
                Section("Hours (OSM)") {
                    Text(hours).font(.caption)
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }

}
