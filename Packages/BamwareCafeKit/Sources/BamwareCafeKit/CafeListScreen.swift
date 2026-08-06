import SwiftUI
import VenueKit

public struct CafeListScreen: View {
    @Bindable private var model: VenuesModel

    public init(model: VenuesModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .loading:
                    ProgressView("Finding work-friendly cafes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    ContentUnavailableView {
                        Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                case .loaded:
                    if model.venues.isEmpty {
                        ContentUnavailableView(
                            "No cafes found",
                            systemImage: "cup.and.saucer",
                            description: Text("Try widening your filters or search area.")
                        )
                    } else {
                        List(model.venues) { venue in
                            NavigationLink(value: venue) {
                                VenueRow(venue: venue)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await model.load() }
                    }
                }
            }
            .navigationTitle("Nearby")
            .navigationDestination(for: Venue.self) { venue in
                VenueDetailScreen(venue: venue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Laptop-friendly only", isOn: $model.laptopFriendlyOnly)
            Picker("Wifi", selection: $model.minWifi) {
                Text("Any wifi").tag(String?.none)
                Text("OK or better").tag(String?.some("ok"))
                Text("Fast only").tag(String?.some("fast"))
            }
            Picker("Outlets", selection: $model.minOutlets) {
                Text("Any outlets").tag(String?.none)
                Text("Some or better").tag(String?.some("some"))
                Text("Plenty").tag(String?.some("plenty"))
            }
        } label: {
            Label("Filters", systemImage: filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .onChange(of: model.laptopFriendlyOnly) { Task { await model.load() } }
        .onChange(of: model.minWifi) { Task { await model.load() } }
        .onChange(of: model.minOutlets) { Task { await model.load() } }
    }

    private var filtersActive: Bool {
        model.laptopFriendlyOnly || model.minWifi != nil || model.minOutlets != nil
    }
}

struct VenueRow: View {
    let venue: Venue

    var body: some View {
        HStack(spacing: 12) {
            ScoreBadge(score: venue.workScore)
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(venue.neighborhood)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let d = venue.distanceM {
                        Text(d < 1000 ? "\(d) m" : String(format: "%.1f km", Double(d) / 1000))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 12) {
                    AttributeGlyph(
                        systemImage: "wifi",
                        text: venue.attributes.wifi.value,
                        dimmed: venue.attributes.wifi.value == "unknown"
                    )
                    AttributeGlyph(
                        systemImage: "powerplug",
                        text: venue.attributes.outlets.value,
                        dimmed: venue.attributes.outlets.value == "unknown"
                    )
                    if venue.attributes.wifi.isEstimate {
                        Text("est.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if venue.attributes.wifi.isMeasured {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
