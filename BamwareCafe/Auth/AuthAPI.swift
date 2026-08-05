import Foundation

actor AuthAPI {
    private struct LoginRequest: Encodable {
        let email: String
        let password: String
        let tenantId: String
    }

    private struct RegistrationRequest: Encodable {
        let email: String
        let password: String
        let name: String
        let tenantId: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct ForgotPasswordRequest: Encodable {
        let email: String
        let tenantId: String
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private let baseURL: URL
    private let tenantID: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, tenantID: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tenantID = tenantID
        self.session = session
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await post(
            "auth/login",
            body: LoginRequest(email: normalize(email), password: password, tenantId: tenantID),
            as: AuthResponse.self
        )
    }

    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        try await post(
            "auth/register",
            body: RegistrationRequest(
                email: normalize(email),
                password: password,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                tenantId: tenantID
            ),
            as: AuthResponse.self
        )
    }

    func refresh(_ refreshToken: String) async throws -> AuthTokens {
        try await post(
            "auth/refresh",
            body: RefreshRequest(refreshToken: refreshToken),
            as: RefreshResponse.self
        ).tokens
    }

    func forgotPassword(email: String) async throws {
        let _: EmptyResponse = try await post(
            "auth/forgot-password",
            body: ForgotPasswordRequest(email: normalize(email), tenantId: tenantID),
            as: EmptyResponse.self
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        as type: Response.Type
    ) async throws -> Response {
        let url = path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error) ?? "Authentication failed."
            if http.statusCode == 401 { throw AuthError.invalidCredentials }
            if http.statusCode == 409 { throw AuthError.emailAlreadyRegistered }
            throw AuthError.server(message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AuthError.invalidResponse
        }
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct EmptyResponse: Decodable {
    init(from decoder: Decoder) throws {}
}
