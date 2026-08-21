import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// The import's two failure modes must stay apart: a bad file says "pick
/// another file"; a dead engine says "Retry" and keeps the file.
@Suite @MainActor struct TakeoutImportModelTests {
    private func writeTemp(_ contents: String, ext: String = "csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("takeout-\(UUID().uuidString).\(ext)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private let validCSV = "Title,Note,URL\nFixture Roasters,,\nNowhere Cafe,,\n"

    @Test func missingFileIsAFileFailure() async {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .fixtureOK), savedVenues: store)

        await model.importFile(at: URL(fileURLWithPath: "/nonexistent/takeout.csv"))

        #expect(model.phase == .fileFailed)
        #expect(store.venueIDs.isEmpty)
    }

    @Test func malformedFileIsAFileFailure() async throws {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .fixtureOK), savedVenues: store)

        await model.importFile(at: try writeTemp("not a takeout file", ext: "txt"))

        #expect(model.phase == .fileFailed)
    }

    @Test func engineFailureIsNotBlamedOnTheFile() async throws {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .engineDown), savedVenues: store)

        await model.importFile(at: try writeTemp(validCSV))

        #expect(model.phase == .engineFailed)
        #expect(store.venueIDs.isEmpty)
    }

    @Test func offlineIsAnEngineFailureToo() async throws {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .offline), savedVenues: store)

        await model.importFile(at: try writeTemp(validCSV))

        #expect(model.phase == .engineFailed)
    }

    @Test func validFileAgainstHealthyEngineMatchesAndSaves() async throws {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .fixtureOK), savedVenues: store)

        await model.importFile(at: try writeTemp(validCSV))

        guard case let .done(matched, unmatched) = model.phase else {
            Issue.record("expected .done, got \(model.phase)")
            return
        }
        #expect(matched.map(\.id) == ["fixture-roasters"])
        #expect(unmatched.map(\.name) == ["Nowhere Cafe"])
        #expect(store.venueIDs == ["fixture-roasters"])
    }

    @Test func retryReRunsTheRetainedFile() async throws {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .engineDown), savedVenues: store)
        let url = try writeTemp(validCSV)

        await model.importFile(at: url)
        #expect(model.phase == .engineFailed)

        // Same engine, same answer — but the retry must go through the file
        // again (not require a re-pick) and land back in the engine state.
        await model.retry()
        #expect(model.phase == .engineFailed)

        try FileManager.default.removeItem(at: url)
        await model.retry()
        #expect(model.phase == .fileFailed)
    }

    @Test func retryWithoutAPriorImportIsANoOp() async {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .fixtureOK), savedVenues: store)

        await model.retry()

        #expect(model.phase == .idle)
    }

    @Test func pickerFailureMarksFileFailed() {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let model = TakeoutImportModel(listing: ScenarioVenueService(scenario: .fixtureOK), savedVenues: store)

        model.markFileFailed()

        #expect(model.phase == .fileFailed)
    }
}
