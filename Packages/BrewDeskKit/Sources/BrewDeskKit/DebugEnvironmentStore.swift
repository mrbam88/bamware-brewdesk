#if DEBUG
import Foundation
import Observation
import VenueKit

/// Debug-only backend switcher. This entire file compiles ONLY into Debug
/// builds — the App Store binary contains none of it (Guideline 2.3.1).
/// Extending: add a case + its URL; the picker and badge pick it up.
/// Lives in the package (moved here by brewdesk#117) so `AccountScreen` —
/// now the You tab's root — can host the reveal gesture + picker sheet
/// itself instead of threading a cross-module closure back into the app
/// target.
public enum DebugEnvironment: String, CaseIterable, Identifiable {
    case localhost
    case production
    // case stage — future: add the case and its baseURL below.

    public var id: String { rawValue }

    public var baseURL: URL {
        switch self {
        case .localhost: URL(string: "http://localhost:3000")!
        case .production: URL(string: "https://venuekit-ashen.vercel.app")!
        }
    }

    public var label: String { rawValue.capitalized }
}

/// Persisted selection. Defaults to localhost, matching the Debug scheme's
/// historical behavior, so nothing changes until the easter egg is used.
@MainActor
@Observable
public final class DebugEnvironmentStore {
    public static let shared = DebugEnvironmentStore()
    private static let key = "brewdesk.debug.environment"

    public var current: DebugEnvironment {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    private init() {
        current = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(DebugEnvironment.init(rawValue:)) ?? .localhost
    }
}
#endif
