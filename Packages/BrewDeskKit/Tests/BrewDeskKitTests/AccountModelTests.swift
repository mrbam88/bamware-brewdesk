import Foundation
import Testing
import VenueKit
@testable import BrewDeskKit

/// Account state machine + the ordered account deletion ported from Baat
/// (dating-app #18, Apple 5.1.1(v)): content → auth record → local session,
/// with both partial-failure paths (brewdesk#48).
@Suite struct AccountModelTests {
    /// Records call order across the two deletion steps. `nonisolated`: the
    /// service fakes call it from nonisolated protocol requirements while the
    /// suite (MainActor by default isolation) reads `order`.
    private nonisolated final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { lock.withLock { entries.append(entry) } }
        var order: [String] { lock.withLock { entries } }
    }

    private struct RecordingAuth: AccountAuthServing {
        let recorder: Recorder
        var deleteError: AuthAPIError?

        func register(email: String, password: String, name: String) async throws -> AuthSession {
            Self.session(email: email, name: name)
        }
        func signIn(email: String, password: String) async throws -> AuthSession {
            Self.session(email: email, name: "Tester")
        }
        func deleteAccount(accessToken: String) async throws {
            recorder.append("auth")
            if let deleteError { throw deleteError }
        }

        static func session(email: String, name: String) -> AuthSession {
            AuthSession(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                user: AuthUser(userId: "u1", email: email, name: name, tenantId: BrewDeskTenant.id)
            )
        }
    }

    private struct RecordingContent: AccountContentDeleting {
        let recorder: Recorder
        var error: AuthAPIError?

        func deleteUserContent(accessToken: String) async throws {
            recorder.append("content")
            if let error { throw error }
        }
    }

    private struct FailingAuth: AccountAuthServing {
        func register(email: String, password: String, name: String) async throws -> AuthSession {
            throw AuthAPIError.emailAlreadyRegistered
        }
        func signIn(email: String, password: String) async throws -> AuthSession {
            throw AuthAPIError.invalidCredentials
        }
        func deleteAccount(accessToken: String) async throws {}
    }

    private func makeSignedInModel(
        recorder: Recorder,
        deleteError: AuthAPIError? = nil,
        contentError: AuthAPIError? = nil
    ) async -> (AccountModel, AccountSessionStore) {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(
            auth: RecordingAuth(recorder: recorder, deleteError: deleteError),
            content: RecordingContent(recorder: recorder, error: contentError),
            sessions: sessions
        )
        await model.signIn(email: "tester@bamware.com", password: "FlatWhite11!")
        #expect(sessions.isSignedIn)
        return (model, sessions)
    }

    // MARK: - Sign in / up / out

    @Test func signInStoresSessionAndPersists() async {
        let persistence = InMemorySessionStore()
        let sessions = AccountSessionStore(persistence: persistence)
        let model = AccountModel(auth: RecordingAuth(recorder: Recorder()), sessions: sessions)

        await model.signIn(email: "tester@bamware.com", password: "FlatWhite11!")

        #expect(sessions.session?.user.email == "tester@bamware.com")
        #expect(persistence.load()?.accessToken == "access-1")
        #expect(model.phase == .idle)
    }

    @Test func failedSignInSurfacesFriendlyMessageAndKeepsSignedOut() async {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: FailingAuth(), sessions: sessions)

        await model.signIn(email: "tester@bamware.com", password: "nope")

        #expect(!sessions.isSignedIn)
        #expect(model.phase == .failed(message: "Invalid email or password."))
    }

    @Test func failedSignUpSurfacesEmailTakenMessage() async {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(auth: FailingAuth(), sessions: sessions)

        await model.signUp(email: "taken@bamware.com", password: "FlatWhite11!", name: "T")

        #expect(model.phase == .failed(message: "That email already has an account. Try signing in."))
    }

    @Test func signOutClearsSessionAndPersistence() async {
        let persistence = InMemorySessionStore()
        let sessions = AccountSessionStore(persistence: persistence)
        let model = AccountModel(auth: RecordingAuth(recorder: Recorder()), sessions: sessions)
        await model.signIn(email: "tester@bamware.com", password: "FlatWhite11!")

        model.signOut()

        #expect(!sessions.isSignedIn)
        #expect(persistence.load() == nil)
    }

    @Test func sessionRestoresFromPersistenceOnInit() {
        let persisted = RecordingAuth.session(email: "tester@bamware.com", name: "Tester")
        let sessions = AccountSessionStore(persistence: InMemorySessionStore(session: persisted))
        #expect(sessions.session == persisted)
    }

    // MARK: - Ordered deletion (the Baat pattern)

    @Test func deletionRunsContentThenAuthThenClearsLocalSession() async {
        let recorder = Recorder()
        let (model, sessions) = await makeSignedInModel(recorder: recorder)

        let outcome = await model.deleteAccount()

        #expect(recorder.order == ["content", "auth"]) // the literal ordering pin
        #expect(outcome == .completed)
        #expect(!sessions.isSignedIn)
    }

    @Test func contentFailureLeavesSessionIntactAndNeverCallsAuth() async {
        let recorder = Recorder()
        let (model, sessions) = await makeSignedInModel(
            recorder: recorder, contentError: .http(statusCode: 500)
        )

        let outcome = await model.deleteAccount()

        #expect(recorder.order == ["content"]) // auth never reached
        guard case .contentFailed = outcome else {
            Issue.record("expected contentFailed, got \(outcome)")
            return
        }
        #expect(sessions.isSignedIn) // plain retry works — session intact
    }

    @Test func authFailureAfterContentClearsLocalSessionAndReportsIncomplete() async {
        let recorder = Recorder()
        let (model, sessions) = await makeSignedInModel(
            recorder: recorder, deleteError: .http(statusCode: 500)
        )

        let outcome = await model.deleteAccount()

        #expect(recorder.order == ["content", "auth"])
        #expect(outcome == .authIncomplete)
        // Content is gone — the account is unusable, so local sign-out anyway.
        #expect(!sessions.isSignedIn)
    }

    @Test func deletionWhenSignedOutIsANoOpSuccess() async {
        let recorder = Recorder()
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        let model = AccountModel(
            auth: RecordingAuth(recorder: recorder),
            content: RecordingContent(recorder: recorder),
            sessions: sessions
        )

        let outcome = await model.deleteAccount()

        #expect(outcome == .completed)
        #expect(recorder.order.isEmpty)
    }

    // MARK: - Tenant pin

    @Test func brewDeskTenantIdNeverDrifts() {
        // A typo would silently create a fresh, empty tenant on the auth
        // service (see auth-service AGENTS.md "Tenants").
        #expect(BrewDeskTenant.id == "bamware-brewdesk")
    }
}
