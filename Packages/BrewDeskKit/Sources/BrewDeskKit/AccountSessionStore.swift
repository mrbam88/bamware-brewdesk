import Foundation
import Security
import VenueKit

/// Where the signed-in session is kept between launches.
public protocol AuthSessionPersisting: AnyObject, Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// Keychain-backed persistence (generic password, this app only, no iCloud
/// sync). Tokens never touch UserDefaults — the keychain survives reinstalls
/// less predictably but is the only right place for bearer tokens.
public final class KeychainSessionStore: AuthSessionPersisting {
    private let service = "io.bamware.brewdesk.auth"
    private let account = "session"

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Ephemeral persistence for scenario launches and package tests: every
/// process starts signed out, deterministically.
public final class InMemorySessionStore: AuthSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func load() -> AuthSession? { lock.withLock { session } }
    public func save(_ session: AuthSession) { lock.withLock { self.session = session } }
    public func clear() { lock.withLock { session = nil } }
}

/// App-wide signed-in state. One instance (`shared`) backs every account
/// screen; `@Observable` so signed-in/out UI flips live.
@Observable
public final class AccountSessionStore {
    /// Scenario launches get in-memory persistence (fresh per process);
    /// normal launches get the keychain.
    public static let shared: AccountSessionStore = {
        if ProcessInfo.processInfo.arguments.contains("-UITestScenario") {
            return AccountSessionStore(persistence: InMemorySessionStore())
        }
        return AccountSessionStore(persistence: KeychainSessionStore())
    }()

    public private(set) var session: AuthSession?
    private let persistence: any AuthSessionPersisting

    public init(persistence: any AuthSessionPersisting) {
        self.persistence = persistence
        session = persistence.load()
    }

    public var isSignedIn: Bool { session != nil }

    public func store(_ session: AuthSession) {
        self.session = session
        persistence.save(session)
    }

    public func clear() {
        session = nil
        persistence.clear()
    }
}
