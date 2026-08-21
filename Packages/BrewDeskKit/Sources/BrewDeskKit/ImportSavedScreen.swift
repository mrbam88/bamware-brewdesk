import SwiftUI
import UniformTypeIdentifiers
import VenueKit

/// Drives a Google Takeout import: read + parse the file on-device, then match
/// against the venue dataset and save the matches. Two failure modes, kept
/// apart on purpose — a bad file and a dead engine need different remedies.
@MainActor
@Observable
public final class TakeoutImportModel {
    public enum Phase: Equatable {
        case idle
        case working
        case done(matched: [Venue], unmatched: [TakeoutPlace])
        /// The file could not be read or recognized. Remedy: pick another file.
        case fileFailed
        /// The file was fine; the venue engine was not. Remedy: Retry.
        case engineFailed
    }

    public private(set) var phase: Phase = .idle

    @ObservationIgnored
    private let listing: any VenueListing
    @ObservationIgnored
    private let savedVenues: SavedVenuesStore
    @ObservationIgnored
    private var lastURL: URL?

    public init(listing: any VenueListing, savedVenues: SavedVenuesStore) {
        self.listing = listing
        self.savedVenues = savedVenues
    }

    public func importFile(at url: URL) async {
        lastURL = url
        phase = .working

        let places: [TakeoutPlace]
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            places = try TakeoutParser.parse(data)
        } catch {
            phase = .fileFailed
            return
        }

        let venues: [Venue]
        do {
            venues = try await listing.fetchVenues(VenueQuery(limit: 200))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .engineFailed
            return
        }

        let result = TakeoutMatcher.match(places: places, venues: venues)
        for venue in result.matched where !savedVenues.contains(venue.id) {
            savedVenues.toggle(venue.id)
        }
        phase = .done(matched: result.matched, unmatched: result.unmatched)
    }

    /// Re-runs the last import (the file is retained across an engine failure).
    public func retry() async {
        guard let lastURL else { return }
        await importFile(at: lastURL)
    }

    /// The document picker itself failed — same remedy as an unreadable file.
    public func markFileFailed() {
        phase = .fileFailed
    }
}

/// Imports a Google Takeout "Saved Places" file (CSV or GeoJSON), matches it
/// against the venue dataset, and saves the matches locally. Everything is
/// parsed on-device; nothing is uploaded. Accountless by design.
public struct ImportSavedScreen: View {
    @Environment(\.takeoutImportAutorunURL) private var autorunURL
    @State private var model: TakeoutImportModel
    @State private var showFilePicker = false

    public init(savedVenues: SavedVenuesStore, listing: any VenueListing) {
        _model = State(initialValue: TakeoutImportModel(listing: listing, savedVenues: savedVenues))
    }

    public var body: some View {
        List {
            switch model.phase {
            case .idle, .working:
                instructions
            case .fileFailed:
                Section {
                    Label("That file couldn't be read", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(BrewDeskPalette.berry)
                        .accessibilityIdentifier("import-state-file-failed")
                    Text("Export your Saved Places from Google Takeout and pick the CSV or GeoJSON file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                instructions
            case .engineFailed:
                Section {
                    Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(BrewDeskPalette.berry)
                        .accessibilityIdentifier("import-state-engine-failed")
                    Text("Check your connection and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await model.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("import-retry")
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
                    if case .working = model.phase {
                        ProgressView()
                    } else {
                        Text("Choose file")
                    }
                }
                .disabled({ if case .working = model.phase { true } else { false } }())
                .accessibilityIdentifier("import-choose-file")
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .json, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await model.importFile(at: url) }
            case .failure:
                model.markFileFailed()
            }
        }
        .task(id: autorunURL) {
            // UI-test seam only: nil in every real launch.
            guard let autorunURL else { return }
            await model.importFile(at: autorunURL)
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
}
