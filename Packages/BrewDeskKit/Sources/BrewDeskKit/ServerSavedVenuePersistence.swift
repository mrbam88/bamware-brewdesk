import BamwareAccounts
import Foundation
import VenueKit

// Saved-spots sync adapter (bamware-brewdesk#175, C10). Local saves stay
// free and unlimited for everyone (bd#120) — this file only adds the
// optional cross-device sync layer for signed-in users, against the
// venue-engine contract in bamware-venue-engine PR #94
// (`GET/PUT/DELETE /v1/users/me/saved`, README "Saved-spots sync").

/// The wire shape both directions of the sync client speak.
public nonisolated struct SavedSpotsSnapshot: Equatable, Sendable {
    public let venueIDs: [String]
    public let updatedAt: String?

    public init(venueIDs: [String], updatedAt: String?) {
        self.venueIDs = venueIDs
        self.updatedAt = updatedAt
    }
}

public nonisolated enum SavedSpotsSyncError: Error, Equatable, Sendable {
    case http(Int)
    case decoding
}

/// Network seam for the three saved-spots routes. Real: `SavedSpotsSyncClient`
/// (URLSession, the same venue-engine deployment `VenueAPI` already talks
/// to). Tests use a fake.
public protocol SavedSpotsSyncing: Sendable {
    // Conformers are expected to be usable off the main actor (network I/O).
    func fetch(accessToken: String) async throws -> SavedSpotsSnapshot
    /// Full replace, last-write-wins, per the contract — never a merge
    /// server-side. `venueIDs` must already be the caller's desired
    /// complete set.
    func replace(venueIDs: [String], accessToken: String) async throws -> SavedSpotsSnapshot
    /// Used by account deletion's content step. Idempotent server-side.
    func delete(accessToken: String) async throws
}

/// `URLSession` client for `GET/PUT/DELETE /v1/users/me/saved`. Defaults to
/// the same base URL and short-timeout session `VenueAPI` uses — this is
/// the same venue-engine deployment, just a different route family.
public nonisolated struct SavedSpotsSyncClient: SavedSpotsSyncing {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = VenueAPI.defaultBaseURL, session: URLSession = VenueAPI.defaultSession) {
        self.baseURL = baseURL
        self.session = session
    }

    private var endpoint: URL { baseURL.appendingPathComponent("v1/users/me/saved") }

    public func fetch(accessToken: String) async throws -> SavedSpotsSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    public func replace(venueIDs: [String], accessToken: String) async throws -> SavedSpotsSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["venueIds": venueIDs])
        return try await send(request)
    }

    public func delete(accessToken: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
    }

    private func send(_ request: URLRequest) async throws -> SavedSpotsSnapshot {
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard let wire = try? JSONDecoder().decode(WireSnapshot.self, from: data) else {
            throw SavedSpotsSyncError.decoding
        }
        return SavedSpotsSnapshot(venueIDs: wire.venueIds, updatedAt: wire.updatedAt)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SavedSpotsSyncError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private struct WireSnapshot: Decodable {
        let venueIds: [String]
        let updatedAt: String?
    }
}

/// Persists the offline write queue across launches — "queue while offline,
/// retry on next foreground/sign-in" (bamware-brewdesk#175). Holds at most
/// one pending write: the most recent local `venueIDs` set that hasn't been
/// confirmed on the server yet. A later local change simply overwrites the
/// pending value (it already carries every earlier change forward), so the
/// queue never needs to replay a sequence.
public final class PendingSavedSpotsWriteStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "brewdesk.saved-spots-sync.pending") {
        self.defaults = defaults
        self.key = key
    }

    public var pendingVenueIDs: [String]? {
        defaults.array(forKey: key) as? [String]
    }

    public var hasPending: Bool { pendingVenueIDs != nil }

    public func markPending(_ venueIDs: [String]) {
        defaults.set(venueIDs, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// `SavedVenuePersisting` adapter that wraps the existing local persistence
/// and adds server sync for signed-in users (bamware-brewdesk#175, C10).
///
/// - Reads are always local-first: `loadVenueIDs()` never blocks on the
///   network, so the Saved tab always has an instant answer.
/// - Writes go to both: local synchronously, server best-effort in the
///   background (queued on failure).
/// - Sign-in merges server ∪ local (union — see `merge(local:server:)`'s
///   doc comment for why there is no per-id conflict to break by
///   `updatedAt`) and pushes the merged set back so both sides agree.
/// - Unauthenticated (including signed-out) is local only: `tokenProvider`
///   returning `nil` is the only signal this type needs, and it never
///   prompts or nags — it just reports `.localOnly`.
@MainActor
@Observable
public final class ServerSavedVenuePersistence: SavedVenuePersisting, SavedVenuesSyncStatusReporting {
    public private(set) var syncStatus: SavedVenuesSyncStatus = .localOnly

    @ObservationIgnored private let local: any SavedVenuePersisting
    @ObservationIgnored private let syncing: any SavedSpotsSyncing
    @ObservationIgnored private let pending: PendingSavedSpotsWriteStore
    /// Returns a fresh, valid bearer token, or `nil` when there is no
    /// signed-in session (or refresh itself failed) — the single signal
    /// this type needs to distinguish "sync" from "local only, no prompts".
    /// Production wiring: `BrewDeskAccountTenant.freshAccessToken` (reads
    /// the keychain fresh each call, so it reflects sign-in/out done
    /// elsewhere in the app without this type holding a shared session
    /// object — see that function's doc comment).
    @ObservationIgnored private let tokenProvider: @Sendable () async -> String?

    public init(
        local: any SavedVenuePersisting = UserDefaultsSavedVenuePersistence(),
        syncing: any SavedSpotsSyncing,
        pending: PendingSavedSpotsWriteStore = PendingSavedSpotsWriteStore(),
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.local = local
        self.syncing = syncing
        self.pending = pending
        self.tokenProvider = tokenProvider
    }

    // MARK: - SavedVenuePersisting

    public func loadVenueIDs() -> [String] {
        local.loadVenueIDs()
    }

    public func saveVenueIDs(_ venueIDs: [String]) {
        local.saveVenueIDs(venueIDs)
        Task { await push(venueIDs) }
    }

    // MARK: - Sign-in / foreground sync

    /// Call when the Saved tab appears and when the app returns to the
    /// foreground: merges on first successful contact per sign-in, and
    /// always tries to flush a queued offline write first.
    public func syncIfNeeded() async {
        guard let token = await tokenProvider() else {
            syncStatus = .localOnly
            return
        }
        if pending.hasPending {
            await retryPendingIfNeeded(token: token)
        }
        guard syncStatus != .synced else { return }
        await mergeOnSignIn(token: token)
    }

    /// Server ∪ local, server `updatedAt` wins where there could be a
    /// conflict. In this contract a "conflict" can only be about whether an
    /// id is a member of the set at all — `venueIds` carries no other
    /// per-item field the two sides could disagree on — so a union already
    /// resolves it without ever silently dropping either side's saves; the
    /// merged set is then pushed back with a `PUT` (last-write-wins on the
    /// server), which is what actually makes the server's `updatedAt`
    /// authoritative for whatever the sync state is from that point on.
    public func mergeOnSignIn(token: String) async {
        do {
            let remote = try await syncing.fetch(accessToken: token)
            let localIDs = local.loadVenueIDs()
            let merged = Self.merge(local: localIDs, server: remote.venueIDs)
            local.saveVenueIDs(merged)
            if merged != remote.venueIDs {
                _ = try await syncing.replace(venueIDs: merged, accessToken: token)
            }
            pending.clear()
            syncStatus = .synced
        } catch {
            pending.markPending(local.loadVenueIDs())
            syncStatus = .localOnly
        }
    }

    static func merge(local: [String], server: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in local where seen.insert(id).inserted { result.append(id) }
        for id in server where seen.insert(id).inserted { result.append(id) }
        return result
    }

    // MARK: - Sign-out

    /// Sign-out never touches local storage — only sync bookkeeping resets,
    /// so the next `loadVenueIDs()` still returns everything that was there
    /// (bamware-brewdesk#175: "signing out keeps my local saves").
    public func handleSignOut() {
        syncStatus = .localOnly
    }

    // MARK: - Offline queue retry

    public func retryPendingIfNeeded() async {
        guard let token = await tokenProvider() else { return }
        await retryPendingIfNeeded(token: token)
    }

    private func retryPendingIfNeeded(token: String) async {
        guard let queued = pending.pendingVenueIDs else { return }
        do {
            _ = try await syncing.replace(venueIDs: queued, accessToken: token)
            pending.clear()
            syncStatus = .synced
        } catch {
            // Still offline or still failing — stays queued for the next
            // foreground/sign-in.
        }
    }

    private func push(_ venueIDs: [String]) async {
        guard let token = await tokenProvider() else {
            syncStatus = .localOnly
            return
        }
        do {
            _ = try await syncing.replace(venueIDs: venueIDs, accessToken: token)
            pending.clear()
            syncStatus = .synced
        } catch {
            pending.markPending(venueIDs)
            syncStatus = .localOnly
        }
    }
}

/// `AccountContentDeleting` conformer for account deletion's content step
/// (bamware-brewdesk#175: "account deletion's content step calls DELETE").
/// Deliberately independent of `ServerSavedVenuePersistence` — `AccountModel`
/// already hands `deleteUserContent` the signed-in session's own access
/// token, so this only needs the network seam, not a shared session/token
/// object. That also keeps it a plain `Sendable` struct: it never touches
/// the `@MainActor`-isolated persistence type.
public struct SavedVenuesAccountContentDeleting: AccountContentDeleting {
    private let syncing: any SavedSpotsSyncing

    public init(syncing: any SavedSpotsSyncing) {
        self.syncing = syncing
    }

    public func deleteUserContent(accessToken: String) async throws {
        try await syncing.delete(accessToken: accessToken)
    }
}
