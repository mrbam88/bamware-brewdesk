import Foundation

/// The bundled first-paint dataset (brewdesk#28): a small slice of the engine's
/// venues captured at build time, so a fresh install renders real content
/// before — or without — the first network round-trip. Loading never throws
/// into the UI: a missing or corrupt resource degrades to "no snapshot", which
/// is the pre-existing loading/error path.
///
/// The file is `VenueSnapshot.json` in the app bundle (the same JSON shape as
/// `GET /v1/venues`, with `distance_m` stripped because distances only mean
/// something relative to a live query). Refresh it with
/// `scripts/refresh-venue-snapshot.sh`.
public enum VenueSnapshot {
    public static let resourceName = "VenueSnapshot"

    /// Venues from the bundled resource, or `[]` when it is absent or unreadable.
    public static func load(bundle: Bundle = .main, resource: String = resourceName) -> [Venue] {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else { return [] }
        return (try? load(from: url)) ?? []
    }

    public static func load(from url: URL) throws -> [Venue] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VenueListResponse.self, from: data).venues
    }
}
