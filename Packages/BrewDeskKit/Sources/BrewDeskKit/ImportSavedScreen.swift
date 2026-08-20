import SwiftUI
import UniformTypeIdentifiers
import VenueKit

/// Imports a Google Takeout "Saved Places" file (CSV or GeoJSON), matches it
/// against the venue dataset, and saves the matches locally. Everything is
/// parsed on-device; nothing is uploaded. Accountless by design.
public struct ImportSavedScreen: View {
    private enum ImportState {
        case idle
        case working
        case done(matched: [Venue], unmatched: [TakeoutPlace])
        case failed
    }

    @Bindable private var savedVenues: SavedVenuesStore
    private let listing: any VenueListing
    @State private var state: ImportState = .idle
    @State private var showFilePicker = false

    public init(savedVenues: SavedVenuesStore, listing: any VenueListing) {
        self.savedVenues = savedVenues
        self.listing = listing
    }

    public var body: some View {
        List {
            switch state {
            case .idle, .working:
                instructions
            case .failed:
                Section {
                    Label("That file couldn't be read", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(BrewDeskPalette.berry)
                    Text("Export your Saved Places from Google Takeout and pick the CSV or GeoJSON file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                instructions
            case let .done(matched, unmatched):
                if !matched.isEmpty {
                    Section("Saved to BrewDesk") {
                        ForEach(matched) { venue in
                            Label(venue.name, systemImage: "bookmark.fill")
                                .foregroundStyle(BrewDeskPalette.moss)
                        }
                    }
                }
                if !unmatched.isEmpty {
                    Section("Not in BrewDesk yet") {
                        ForEach(unmatched, id: \.name) { place in
                            Text(place.name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("Import saved places"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilePicker = true
                } label: {
                    if case .working = state {
                        ProgressView()
                    } else {
                        Text("Choose file")
                    }
                }
                .disabled({ if case .working = state { true } else { false } }())
                .accessibilityIdentifier("import-choose-file")
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .json, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await runImport(from: url) }
        }
    }

    private var instructions: some View {
        Section("How to export from Google Maps") {
            Label("Open takeout.google.com and select only \"Saved\" (Maps)", systemImage: "1.circle")
            Label("Download the export and unzip it", systemImage: "2.circle")
            Label("Pick the Saved Places file here — it never leaves this device", systemImage: "3.circle")
            Text("Apple Maps has no export — search and save those spots manually.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func runImport(from url: URL) async {
        state = .working
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let places = try TakeoutParser.parse(data)
            let venues = try await listing.fetchVenues(VenueQuery(limit: 200))
            let result = TakeoutMatcher.match(places: places, venues: venues)
            for venue in result.matched where !savedVenues.contains(venue.id) {
                savedVenues.toggle(venue.id)
            }
            state = .done(matched: result.matched, unmatched: result.unmatched)
        } catch {
            state = .failed
        }
    }
}
