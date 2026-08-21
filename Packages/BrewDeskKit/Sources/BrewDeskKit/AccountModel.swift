// BrewDesk accounts (brewdesk#48). Sign in / sign up / sign out plus the
// ordered account deletion ported from Baat (dating-app #18, Apple 5.1.1(v)).
import Foundation
import SwiftUI
import VenueKit

/// Drives the account screens. All transition rules live here so they are
/// unit-testable without UI (same policy as `ObservationFormModel`).
@Observable
public final class AccountModel {
    public enum Phase: Equatable {
        case idle
        case working
        /// `message` is the friendly, user-facing sentence — never a raw error.
        case failed(message: String)
    }

    /// Outcome of the ordered deletion — drives the deletion screen's copy.
    public enum DeletionOutcome: Equatable {
        /// Everything gone, signed out.
        case completed
        /// Step 1 (content) failed: the session is INTACT — plain retry.
        case contentFailed(message: String)
        /// Content gone but the auth record may remain. Local session is
        /// cleared (the account is unusable); both endpoints treat "already
        /// gone" as success, so sign-in-and-retry completes the job.
        case authIncomplete
    }

    public private(set) var phase: Phase = .idle
    public let sessions: AccountSessionStore

    private let auth: any AccountAuthServing
    private let content: any AccountContentDeleting

    public init(
        auth: any AccountAuthServing,
        content: any AccountContentDeleting = NoUserContentService(),
        sessions: AccountSessionStore
    ) {
        self.auth = auth
        self.content = content
        self.sessions = sessions
    }

    public var isWorking: Bool { phase == .working }

    // MARK: - Sign in / up / out

    public func signIn(email: String, password: String) async {
        await run { try await self.auth.signIn(email: email, password: password) }
    }

    public func signUp(email: String, password: String, name: String) async {
        await run { try await self.auth.register(email: email, password: password, name: name) }
    }

    public func signOut() {
        sessions.clear()
        phase = .idle
    }

    private func run(_ operation: @escaping () async throws -> AuthSession) async {
        guard phase != .working else { return }
        phase = .working
        do {
            let session = try await operation()
            sessions.store(session)
            phase = .idle
        } catch {
            phase = .failed(message: Self.friendlyMessage(for: error))
        }
    }

    // MARK: - Ordered account deletion (Baat's pattern, dating-app #18)

    /// Order matters: app content first, then the auth record (deleting it
    /// breaks refresh/re-login — so it must go last, and before local tokens
    /// are cleared). Both server calls treat "already gone" as success, so
    /// the whole flow is safe to re-run after a partial failure.
    public func deleteAccount() async -> DeletionOutcome {
        guard let session = sessions.session else { return .completed }
        phase = .working
        defer { if phase == .working { phase = .idle } }

        // 1. App content. Failure here leaves the session intact — plain retry.
        do {
            try await content.deleteUserContent(accessToken: session.accessToken)
        } catch {
            let outcome = DeletionOutcome.contentFailed(
                message: "Couldn't delete your account right now. Check your connection and try again."
            )
            phase = .idle
            return outcome
        }

        // 2. Auth record — revokes refresh/re-login, so it goes last.
        do {
            try await auth.deleteAccount(accessToken: session.accessToken)
        } catch {
            // Content is gone; the account is unusable either way — clear the
            // local session, surface the incomplete state.
            sessions.clear()
            phase = .idle
            return .authIncomplete
        }

        // 3. Local session — only after both network steps.
        sessions.clear()
        phase = .idle
        return .completed
    }

    // MARK: - Copy

    /// Friendly copy only — raw errors and status codes never reach the UI.
    static func friendlyMessage(for error: Error) -> String {
        if let authError = error as? AuthAPIError,
           let description = authError.errorDescription {
            return description
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            return "You look offline. Try again in a moment."
        }
        return "Couldn't reach the account service. Try again in a moment."
    }
}

// MARK: - Service injection

/// Optional-first auth service injection, mirroring `\.venueObservationService`:
/// screens read it from the environment; nil (the default) means the screen
/// resolves `AccountServiceResolver.resolve()` on first appearance. Resolved
/// screen-side so the feature stays additive to the composition root.
private struct AccountAuthServiceKey: EnvironmentKey {
    static let defaultValue: (any AccountAuthServing)? = nil
}

extension EnvironmentValues {
    public var accountAuthService: (any AccountAuthServing)? {
        get { self[AccountAuthServiceKey.self] }
        set { self[AccountAuthServiceKey.self] = newValue }
    }
}

/// Same `-UITestScenario` launch-argument contract as
/// `ObservationServiceResolver`: scenario launches get the deterministic
/// in-process `AuthScenarioService`, every normal launch gets `AuthAPI`.
public enum AccountServiceResolver {
    public static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> any AccountAuthServing {
        if let index = arguments.firstIndex(of: "-UITestScenario"),
           arguments.indices.contains(index + 1),
           ScenarioVenueService.Scenario(rawValue: arguments[index + 1]) != nil {
            return AuthScenarioService.shared
        }
        return AuthAPI()
    }
}
