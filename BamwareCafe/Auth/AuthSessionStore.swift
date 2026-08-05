import Foundation
import Observation

@MainActor
@Observable
final class AuthSessionStore {
    enum State: Equatable {
        case hydrating
        case signedOut
        case authenticated(AuthUser)
    }

    private(set) var state: State = .hydrating
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let tenantID: String
    private let api: AuthAPI
    private let vault: TokenVault
    private var sessionGeneration = 0

    init(configuration: AppConfiguration, vault: TokenVault = TokenVault()) {
        tenantID = configuration.tenantID
        api = AuthAPI(baseURL: configuration.authBaseURL, tenantID: configuration.tenantID)
        self.vault = vault
    }

    func hydrate() async {
        guard state == .hydrating else { return }
        do {
            guard let tokens = try await vault.load() else {
                state = .signedOut
                return
            }

            if let user = validUser(from: tokens.accessToken) {
                state = .authenticated(user)
                return
            }

            let generation = sessionGeneration
            let refreshed = try await api.refresh(tokens.refreshToken)
            guard generation == sessionGeneration,
                  let user = validUser(from: refreshed.accessToken) else {
                throw AuthError.invalidSession
            }
            try await vault.save(refreshed)
            state = .authenticated(user)
        } catch {
            try? await vault.clear()
            state = .signedOut
        }
    }

    func login(email: String, password: String) async {
        await submit {
            try await self.api.login(email: email, password: password)
        }
    }

    func register(name: String, email: String, password: String) async {
        await submit {
            try await self.api.register(name: name, email: email, password: password)
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await api.forgotPassword(email: email)
    }

    func logout() async {
        sessionGeneration += 1
        try? await vault.clear()
        errorMessage = nil
        state = .signedOut
    }

    func clearError() {
        errorMessage = nil
    }

    private func submit(_ operation: @escaping () async throws -> AuthResponse) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await operation()
            guard response.user.tenantId == tenantID else { throw AuthError.invalidSession }
            try await vault.save(response.tokens)
            state = .authenticated(response.user)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to sign in. Try again."
        }
    }

    private func validUser(from accessToken: String) -> AuthUser? {
        guard let claims = try? JWTClaimsDecoder.decode(accessToken),
              claims.tenantId == tenantID,
              claims.exp > Int(Date().timeIntervalSince1970) else {
            return nil
        }
        return claims.user
    }
}
