import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let userId: String
    let email: String
    let name: String
    let role: String
    let tenantId: String
    let emailVerified: Bool?
}

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct AuthResponse: Codable, Sendable {
    let tokens: AuthTokens
    let user: AuthUser
}

struct RefreshResponse: Codable, Sendable {
    let tokens: AuthTokens
}

struct JWTClaims: Codable, Sendable {
    let userId: String
    let email: String
    let name: String
    let role: String
    let tenantId: String
    let emailVerified: Bool?
    let exp: Int

    var user: AuthUser {
        AuthUser(
            userId: userId,
            email: email,
            name: name,
            role: role,
            tenantId: tenantId,
            emailVerified: emailVerified
        )
    }
}

enum AuthError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case emailAlreadyRegistered
    case invalidResponse
    case invalidSession
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Invalid email or password."
        case .emailAlreadyRegistered:
            "An account already exists for this email."
        case .invalidResponse:
            "The authentication service returned an invalid response."
        case .invalidSession:
            "Your session expired. Sign in again."
        case .server(let message):
            message
        }
    }
}

enum JWTClaimsDecoder {
    static func decode(_ token: String) throws -> JWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw AuthError.invalidSession }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(JWTClaims.self, from: data) else {
            throw AuthError.invalidSession
        }
        return claims
    }
}
