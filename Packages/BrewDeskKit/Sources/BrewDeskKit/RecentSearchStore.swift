import Foundation
import Observation
import VenueKit

/// bd#223: one remembered search — either a café the user actually SELECTED
/// (a shelf-row tap or a Search/return that resolved to exactly one result,
/// both routed through `CafeMapScreen.selectSearchResult`) or a plain typed
/// QUERY the user submitted without picking a row. Two kinds rather than one
/// "text" entry: a café recent carries enough (`id` + coordinate) to fly the
/// map straight back to it without re-running the search; a query recent
/// only ever re-runs the search.
public enum RecentSearchEntry: Equatable, Sendable, Identifiable {
    case cafe(id: String, name: String, neighborhood: String, lat: Double, lng: Double)
    case query(text: String)

    /// De-duplication key: a later record of the SAME café (by id) or the
    /// same normalized query text replaces the earlier entry in place
    /// (moves to the top) rather than appending a second row for it.
    public var id: String {
        switch self {
        case .cafe(let id, _, _, _, _): "cafe:\(id)"
        case .query(let text): "query:\(Self.normalize(text))"
        }
    }

    public var title: String {
        switch self {
        case .cafe(_, let name, _, _, _): name
        case .query(let text): text
        }
    }

    /// The row's secondary line — a café's neighborhood; `nil` for a query
    /// (nothing to show under a plain remembered search term).
    public var neighborhood: String? {
        if case .cafe(_, _, let neighborhood, _, _) = self { neighborhood } else { nil }
    }

    public var cafeID: String? {
        if case .cafe(let id, _, _, _, _) = self { id } else { nil }
    }

    public var coordinate: (lat: Double, lng: Double)? {
        if case .cafe(_, _, _, let lat, let lng) = self { (lat, lng) } else { nil }
    }

    /// SF Symbol for the row's leading icon — a café's pin versus a plain
    /// remembered search term.
    public var symbolName: String {
        switch self {
        case .cafe: "mappin.and.ellipse"
        case .query: "clock.arrow.circlepath"
        }
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension RecentSearchEntry: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id, name, neighborhood, lat, lng, text }
    private enum Kind: String, Codable { case cafe, query }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cafe:
            self = .cafe(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                neighborhood: try container.decode(String.self, forKey: .neighborhood),
                lat: try container.decode(Double.self, forKey: .lat),
                lng: try container.decode(Double.self, forKey: .lng)
            )
        case .query:
            self = .query(text: try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cafe(let id, let name, let neighborhood, let lat, let lng):
            try container.encode(Kind.cafe, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(neighborhood, forKey: .neighborhood)
            try container.encode(lat, forKey: .lat)
            try container.encode(lng, forKey: .lng)
        case .query(let text):
            try container.encode(Kind.query, forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

/// On-device-only persistence for `RecentSearchStore` (bd#223's privacy
/// requirement: recent searches are never sent to any server, never logged —
/// this is a plain `UserDefaults` JSON blob under a namespaced key, exactly
/// the same shape `UserDefaultsSavedVenuePersistence` already uses for saved
/// cafés).
@MainActor
public protocol RecentSearchPersisting: AnyObject {
    func loadEntries() -> [RecentSearchEntry]
    func saveEntries(_ entries: [RecentSearchEntry])
}

@MainActor
public final class UserDefaultsRecentSearchPersistence: RecentSearchPersisting {
    private let defaults: UserDefaults
    private let key: String
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "brewdesk.recent-searches") {
        self.defaults = defaults
        self.key = key
    }

    public func loadEntries() -> [RecentSearchEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? Self.decoder.decode([RecentSearchEntry].self, from: data)) ?? []
    }

    public func saveEntries(_ entries: [RecentSearchEntry]) {
        guard let data = try? Self.encoder.encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

/// bd#223: "the search field should remember recent search history." Up to
/// `capacity` entries, newest first, de-duplicated by `RecentSearchEntry.id`
/// (the same café or the same normalized query text moves to the top rather
/// than appending a second row) — pure state + persistence, no view code, so
/// this is exercised directly by `RecentSearchStoreTests` without a running
/// `Map`.
@MainActor
@Observable
public final class RecentSearchStore {
    public static let capacity = 10
    /// Ticket's own trigger: a submitted query shorter than this is never
    /// worth remembering (matches `VenuesModel.serverSearchMinimumLength`'s
    /// "≥ 2 characters" rationale, kept as an independent constant here
    /// since a recent and a citywide server search are different concerns
    /// that happen to agree on the same threshold).
    public static let minimumQueryLength = 2

    public private(set) var entries: [RecentSearchEntry]
    /// True only for the run that just removed a stale café (its detail
    /// fetch came back "not found") — `DiscoveryShelfCard` reads this to show
    /// a brief inline message, distinct from a `Bool` so the SAME wording
    /// survives a view re-render but a later record/clear replaces it.
    public private(set) var lastRemovalReason: String?

    @ObservationIgnored
    private let persistence: any RecentSearchPersisting

    public init(
        persistence: any RecentSearchPersisting = UserDefaultsRecentSearchPersistence(),
        launchEnvironment: LaunchEnvironment = .current
    ) {
        self.persistence = persistence
        // bd#223: a UI test run must never inherit recents a PREVIOUS run
        // left behind on the shared simulator's UserDefaults — every
        // `-UITest…` launch resets to either an explicit seed
        // (`-brewdesk.recent-searches-seed`, for a test that needs a recent
        // already present) or empty, the same "argument is authoritative"
        // determinism `LaunchEnvironment`'s other UI-test seams already
        // give every other piece of persisted state.
        if launchEnvironment.isUITestRun {
            let seed = Self.decodeSeed(launchEnvironment.recentSearchSeedJSON)
            persistence.saveEntries(seed)
            entries = seed
        } else {
            entries = persistence.loadEntries()
        }
    }

    public func recordSelection(of venue: Venue) {
        record(.cafe(id: venue.id, name: venue.name, neighborhood: venue.neighborhood, lat: venue.lat, lng: venue.lng))
    }

    /// The keyboard's Search/return, `≥ minimumQueryLength` characters, with
    /// no row picked (a shorter or blank submit is silently ignored — never
    /// worth a recent).
    public func recordSubmittedQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else { return }
        record(.query(text: trimmed))
    }

    private func record(_ entry: RecentSearchEntry) {
        var next = entries.filter { $0.id != entry.id }
        next.insert(entry, at: 0)
        entries = Array(next.prefix(Self.capacity))
        persistence.saveEntries(entries)
    }

    public func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        persistence.saveEntries(entries)
    }

    public func remove(id: String) {
        entries.removeAll { $0.id == id }
        persistence.saveEntries(entries)
    }

    /// A café the detail endpoint reports gone — removes it and records the
    /// message `DiscoveryShelfCard` shows inline for a beat.
    public func removeGoneCafe(id: String, name: String) {
        remove(id: "cafe:\(id)")
        lastRemovalReason = "\(name) no longer exists"
    }

    public func clearRemovalReason() {
        lastRemovalReason = nil
    }

    public func clear() {
        entries = []
        persistence.saveEntries(entries)
    }

    /// Up to `limit` recents whose TITLE has a word starting with `prefix` —
    /// surfaced above the live results while typing (ticket: "up to 3
    /// recents whose title has a word starting with the typed text"),
    /// excluding anything already present among the live results themselves
    /// (`excludingCafeIDs`) so a café never appears twice on screen at once.
    /// Reuses the exact word-prefix rule `CafeMapScreen.wordPrefixRankedResults`
    /// already applies to the live list, so "sey" surfaces a "SEY Coffee"
    /// recent but not one merely containing "sey" mid-word.
    public func matching(prefix: String, limit: Int = 3, excludingCafeIDs: Set<String> = []) -> [RecentSearchEntry] {
        let needle = RecentSearchEntry.normalize(prefix)
        guard !needle.isEmpty else { return [] }
        var results: [RecentSearchEntry] = []
        for entry in entries {
            if let cafeID = entry.cafeID, excludingCafeIDs.contains(cafeID) { continue }
            guard Self.hasWordPrefixMatch(needle, in: entry.title) else { continue }
            results.append(entry)
            if results.count == limit { break }
        }
        return results
    }

    private static func hasWordPrefixMatch(_ needle: String, in text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(needle) }
    }

    /// `LaunchEnvironment.recentSearchSeedJSON` decoded, or `[]` for a
    /// missing/malformed argument — a UI-test seed is a nicety, never a
    /// reason to crash or leave the store in an undefined state.
    private static func decodeSeed(_ json: String?) -> [RecentSearchEntry] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecentSearchEntry].self, from: data)) ?? []
    }
}
