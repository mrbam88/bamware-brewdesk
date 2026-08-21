import Foundation

/// Blocked community contributors (brewdesk#48, Apple 1.2: "the ability to
/// block abusive users"). Device-local v1: blocking hides every photo whose
/// `communityByline` matches on the next photo fetch (photo services filter
/// through this store), and the viewer dismisses immediately on block.
///
/// Keyed by contributor DISPLAY NAME because `VenuePhoto` carries no
/// contributor id (`contributorName` only — see Models.swift). Good enough
/// while display names are moderated server-side and unique-ish; the proposed
/// reports contract (ReportContract.swift) adds a stable `contributorId` for
/// the engine follow-up, at which point this store keys on ids.
///
/// Scenario launches (`-UITestScenario`) get an in-memory backing so UI test
/// runs never accumulate blocks in the simulator's persisted defaults.
public final class ContributorBlockStore: @unchecked Sendable {
    public static let defaultsKey = "brewdesk.blocked-contributors"

    public static let shared: ContributorBlockStore = {
        if ProcessInfo.processInfo.arguments.contains("-UITestScenario") {
            return ContributorBlockStore(defaults: nil)
        }
        return ContributorBlockStore(defaults: .standard)
    }()

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var names: Set<String>

    /// `defaults: nil` = in-memory only (scenario launches, tests).
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        names = Set(defaults?.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    public var blockedNames: [String] {
        lock.withLock { names.sorted() }
    }

    public func isBlocked(_ contributorName: String) -> Bool {
        lock.withLock { names.contains(Self.normalize(contributorName)) }
    }

    public func block(_ contributorName: String) {
        let name = Self.normalize(contributorName)
        guard !name.isEmpty else { return }
        lock.withLock {
            names.insert(name)
            persistLocked()
        }
    }

    public func unblock(_ contributorName: String) {
        lock.withLock {
            names.remove(Self.normalize(contributorName))
            persistLocked()
        }
    }

    /// Drops community photos from blocked contributors; photos without a
    /// community byline (Google photos) always pass through.
    public func filteringBlocked(_ photos: [VenuePhoto]) -> [VenuePhoto] {
        let blocked = lock.withLock { names }
        guard !blocked.isEmpty else { return photos }
        return photos.filter { photo in
            guard let byline = photo.communityByline else { return true }
            return !blocked.contains(byline)
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persistLocked() {
        defaults?.set(names.sorted(), forKey: Self.defaultsKey)
    }
}
