#if DEBUG
import Foundation
import Observation
import VenueKit

/// Debug-only backend switcher. This entire file compiles ONLY into Debug
/// builds — the App Store binary contains none of it (Guideline 2.3.1).
/// Extending: add a case + its URL; the picker and badge pick it up.
enum DebugEnvironment: String, CaseIterable, Identifiable {
    case localhost
    case production
    // case stage — future: add the case and its baseURL below.

    var id: String { rawValue }

    var baseURL: URL {
        switch self {
        case .localhost: URL(string: "http://localhost:3000")!
        case .production: URL(string: "https://venuekit-ashen.vercel.app")!
        }
    }

    var label: String { rawValue.capitalized }
}

/// Persisted selection. Defaults to localhost, matching the Debug scheme's
/// historical behavior, so nothing changes until the easter egg is used.
@MainActor
@Observable
final class DebugEnvironmentStore {
    static let shared = DebugEnvironmentStore()
    private static let key = "brewdesk.debug.environment"

    var current: DebugEnvironment {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    private init() {
        current = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(DebugEnvironment.init(rawValue:)) ?? .localhost
    }
}
#endif
