import BamwareAccounts
import Foundation
import Testing
@testable import BrewDeskKit

/// Unit tests for the saved-spots sync adapter (bamware-brewdesk#175, C10):
/// merge rules, offline queue, sign-out keeps local, deletion clears server.
@Suite @MainActor struct ServerSavedVenuePersistenceTests {
    // MARK: - Merge rules (sign-in: server ∪ local)

    @Test func mergeUnionsWithoutDroppingEitherSide() {
        let merged = ServerSavedVenuePersistence.merge(local: ["a", "b"], server: ["b", "c"])
        #expect(merged == ["a", "b", "c"])
    }

    @Test func mergeDeduplicatesPreservingLocalOrderFirst() {
        let merged = ServerSavedVenuePersistence.merge(local: ["b", "a"], server: ["a", "c", "b"])
        #expect(merged == ["b", "a", "c"])
    }

    @Test func signInMergesServerAndLocalAndPushesUnionBack() async {
        let local = MemorySavedPersistence()
        local.saved = ["local-only", "shared"]
        let syncing = FakeSavedSpotsSyncing(fetchResult: .success(.init(venueIDs: ["shared", "server-only"], updatedAt: "t0")))
        let persistence = ServerSavedVenuePersistence(
            local: local,
            syncing: syncing,
            pending: PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending"),
            tokenProvider: { "token" }
        )

        await persistence.mergeOnSignIn(token: "token")

        #expect(Set(local.saved) == Set(["local-only", "shared", "server-only"]))
        #expect(persistence.syncStatus == .synced)
        #expect(syncing.replaceCalls.last?.venueIDs.sorted() == ["local-only", "server-only", "shared"])
    }

    @Test func signInSkipsPushWhenMergedSetAlreadyMatchesServer() async {
        let local = MemorySavedPersistence()
        local.saved = ["a"]
        let syncing = FakeSavedSpotsSyncing(fetchResult: .success(.init(venueIDs: ["a"], updatedAt: "t0")))
        let persistence = ServerSavedVenuePersistence(
            local: local,
            syncing: syncing,
            pending: PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending"),
            tokenProvider: { "token" }
        )

        await persistence.mergeOnSignIn(token: "token")

        #expect(syncing.replaceCalls.isEmpty)
        #expect(persistence.syncStatus == .synced)
    }

    // MARK: - Offline queue

    @Test func failedWriteIsQueuedAndRetriedOnNextAttempt() async {
        let local = MemorySavedPersistence()
        let syncing = FakeSavedSpotsSyncing(replaceResult: .failure(SavedSpotsSyncError.http(503)))
        let pendingStore = PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending")
        let persistence = ServerSavedVenuePersistence(
            local: local,
            syncing: syncing,
            pending: pendingStore,
            tokenProvider: { "token" }
        )

        persistence.saveVenueIDs(["a", "b"])
        // saveVenueIDs kicks off the network push in a detached Task; give
        // it a beat to run before asserting the queued state.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(persistence.syncStatus == .localOnly)
        #expect(pendingStore.pendingVenueIDs == ["a", "b"])

        // Retry succeeds this time.
        syncing.replaceResult = .success(.init(venueIDs: ["a", "b"], updatedAt: "t1"))
        await persistence.retryPendingIfNeeded()

        #expect(persistence.syncStatus == .synced)
        #expect(pendingStore.pendingVenueIDs == nil)
    }

    @Test func retryIsANoOpWithNothingQueued() async {
        let syncing = FakeSavedSpotsSyncing()
        let pendingStore = PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending")
        let persistence = ServerSavedVenuePersistence(
            local: MemorySavedPersistence(),
            syncing: syncing,
            pending: pendingStore,
            tokenProvider: { "token" }
        )

        await persistence.retryPendingIfNeeded()

        #expect(syncing.replaceCalls.isEmpty)
    }

    // MARK: - Sign-out keeps local

    @Test func signOutKeepsLocalDataAndFlipsStatusToLocalOnly() async {
        let local = MemorySavedPersistence()
        local.saved = ["kept-a", "kept-b"]
        let syncing = FakeSavedSpotsSyncing(fetchResult: .success(.init(venueIDs: ["kept-a"], updatedAt: "t0")))
        let persistence = ServerSavedVenuePersistence(
            local: local,
            syncing: syncing,
            pending: PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending"),
            tokenProvider: { "token" }
        )
        await persistence.mergeOnSignIn(token: "token")
        #expect(persistence.syncStatus == .synced)

        persistence.handleSignOut()

        #expect(persistence.syncStatus == .localOnly)
        #expect(Set(persistence.loadVenueIDs()) == Set(["kept-a", "kept-b"]))
    }

    @Test func unauthenticatedReadsAndWritesStayLocalOnlyWithNoNetworkCall() async {
        let local = MemorySavedPersistence()
        let syncing = FakeSavedSpotsSyncing()
        let persistence = ServerSavedVenuePersistence(
            local: local,
            syncing: syncing,
            pending: PendingSavedSpotsWriteStore(defaults: freshDefaults(), key: "test.pending"),
            tokenProvider: { nil }
        )

        persistence.saveVenueIDs(["solo"])
        try? await Task.sleep(for: .milliseconds(50))

        #expect(persistence.loadVenueIDs() == ["solo"])
        #expect(persistence.syncStatus == .localOnly)
        #expect(syncing.replaceCalls.isEmpty)

        await persistence.syncIfNeeded()
        #expect(persistence.syncStatus == .localOnly)
        #expect(syncing.fetchCallCount == 0)
    }

    // MARK: - Account deletion clears server

    @Test func accountDeletionContentStepCallsDelete() async throws {
        let syncing = FakeSavedSpotsSyncing()
        let deleting = SavedVenuesAccountContentDeleting(syncing: syncing)

        try await deleting.deleteUserContent(accessToken: "the-token")

        #expect(syncing.deleteCalls == ["the-token"])
    }

    @Test func deletionFailurePropagates() async {
        let syncing = FakeSavedSpotsSyncing(deleteResult: .failure(SavedSpotsSyncError.http(500)))
        let deleting = SavedVenuesAccountContentDeleting(syncing: syncing)

        do {
            try await deleting.deleteUserContent(accessToken: "t")
            Issue.record("expected deleteUserContent to throw")
        } catch let error as SavedSpotsSyncError {
            #expect(error == .http(500))
        } catch {
            Issue.record("expected SavedSpotsSyncError, got \(error)")
        }
    }

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "ServerSavedVenuePersistenceTests-\(UUID().uuidString)")!
        return defaults
    }
}

private final class MemorySavedPersistence: SavedVenuePersisting {
    var saved: [String] = []

    func loadVenueIDs() -> [String] { saved }
    func saveVenueIDs(_ venueIDs: [String]) { saved = venueIDs }
}

private nonisolated final class FakeSavedSpotsSyncing: SavedSpotsSyncing, @unchecked Sendable {
    var fetchResult: Result<SavedSpotsSnapshot, Error>
    /// nil means "echo back whatever `replace` was called with" — the real
    /// contract's full-replace echo behavior; a non-nil value overrides it
    /// (e.g. to simulate a failure).
    var replaceResult: Result<SavedSpotsSnapshot, Error>?
    var deleteResult: Result<Void, Error>

    private(set) var fetchCallCount = 0
    private(set) var replaceCalls: [(venueIDs: [String], accessToken: String)] = []
    private(set) var deleteCalls: [String] = []

    init(
        fetchResult: Result<SavedSpotsSnapshot, Error>? = nil,
        replaceResult: Result<SavedSpotsSnapshot, Error>? = nil,
        deleteResult: Result<Void, Error>? = nil
    ) {
        self.fetchResult = fetchResult ?? .success(SavedSpotsSnapshot(venueIDs: [], updatedAt: nil))
        self.replaceResult = replaceResult
        self.deleteResult = deleteResult ?? .success(())
    }

    func fetch(accessToken: String) async throws -> SavedSpotsSnapshot {
        fetchCallCount += 1
        return try fetchResult.get()
    }

    func replace(venueIDs: [String], accessToken: String) async throws -> SavedSpotsSnapshot {
        replaceCalls.append((venueIDs, accessToken))
        if let replaceResult {
            return try replaceResult.get()
        }
        return SavedSpotsSnapshot(venueIDs: venueIDs, updatedAt: "t")
    }

    func delete(accessToken: String) async throws {
        deleteCalls.append(accessToken)
        try deleteResult.get()
    }
}
