import Foundation
import Security

actor TokenVault {
    private enum Key: String {
        case accessToken = "access-token"
        case refreshToken = "refresh-token"
    }

    private let service: String

    init(service: String = "bamware.BamwareCafe.auth") {
        self.service = service
    }

    func load() throws -> AuthTokens? {
        guard let accessToken = try read(.accessToken),
              let refreshToken = try read(.refreshToken) else {
            return nil
        }
        return AuthTokens(accessToken: accessToken, refreshToken: refreshToken)
    }

    func save(_ tokens: AuthTokens) throws {
        try write(tokens.accessToken, for: .accessToken)
        do {
            try write(tokens.refreshToken, for: .refreshToken)
        } catch {
            try? delete(.accessToken)
            throw error
        }
    }

    func clear() throws {
        try delete(.accessToken)
        try delete(.refreshToken)
    }

    private func read(_ key: Key) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AuthError.invalidSession
        }
        return value
    }

    private func write(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw AuthError.invalidSession }
        let query = baseQuery(for: key)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AuthError.invalidSession
            }
        } else if status != errSecSuccess {
            throw AuthError.invalidSession
        }
    }

    private func delete(_ key: Key) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.invalidSession
        }
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
