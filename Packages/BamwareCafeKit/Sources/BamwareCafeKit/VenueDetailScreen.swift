import SwiftUI
import VenueKit
import BamwareUI

public struct VenueDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var venue: Venue
    @State private var testing = false
    @State private var testResult: String?
    private let model: VenuesModel

    public init(venue: Venue, model: VenuesModel) {
        self._venue = State(initialValue: venue)
        self.model = model
    }

    private var theme: CafeTheme { CafeTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // Shared bamware-ios component, cafe-tenant theme — tenant #3 in action.
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

            Section {
                Button {
                    runSpeedTest()
                } label: {
                    HStack {
                        if testing {
                            ProgressView().padding(.trailing, 6)
                        } else {
                            Image(systemName: "gauge.with.needle")
                        }
                        Text(testing ? "Measuring…" : "Run speed test here")
                    }
                }
                .disabled(testing || !model.supportsSpeedTest)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(model.supportsSpeedTest
                    ? "Submits a measured observation. The engine updates the wifi claim and rescores this venue live."
                    : "Speed observations are disabled while using the local development engine.")
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

    private func runSpeedTest() {
        testing = true
        testResult = nil
        Task {
            defer { testing = false }
            do {
                let updated = try await model.runSpeedTest(for: venue)
                venue = updated
                if let range = updated.attributes.wifi.mbpsRange, let first = range.first {
                    testResult = "Measured ~\(first.formatted(.number.precision(.fractionLength(0)))) Mbps → wifi is now “\(updated.attributes.wifi.value)” · score \(updated.workScore)"
                } else {
                    testResult = "Submitted — score is now \(updated.workScore)"
                }
            } catch {
                testResult = "Speed test failed: \(String(describing: error))"
            }
        }
    }
}
