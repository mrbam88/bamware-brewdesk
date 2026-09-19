import CoreLocation
import MapKit
import SwiftUI

/// Resolves a selected Apple `MapFeature` to a full `MKMapItem` (bd#182) —
/// used to hand `openInMaps`/Directions a precise place instead of a bare
/// coordinate. On-device only; the result is held in view state for the
/// life of the card and never written to disk or sent anywhere (the ticket's
/// "never persist Apple results" constraint).
///
/// iOS 18+ resolves via `MKMapItemRequest(feature:)` — the feature carries
/// Apple's own place identifier, so this is the precise path. iOS 17 has no
/// feature-to-item bridge, so it falls back to an `MKLocalSearch` for the
/// feature's name near its coordinate — the same lookup a person typing the
/// café's name into Maps would trigger, not always the identical place, but
/// close enough for Directions.
@MainActor
public enum AppleCafeDetailsResolver {
    public static func resolveMapItem(
        name: String,
        coordinate: CLLocationCoordinate2D,
        feature: MapFeature
    ) async -> MKMapItem? {
        if #available(iOS 18, *), let item = await mapItem(forFeature: feature) {
            return item
        }
        return await localSearchMapItem(name: name, coordinate: coordinate)
    }

    @available(iOS 18, *)
    private static func mapItem(forFeature feature: MapFeature) async -> MKMapItem? {
        let request = MKMapItemRequest(feature: feature)
        // `MKMapItem` isn't `Sendable`, and this whole type is `@MainActor`
        // (the package's default isolation), so `getMapItem`'s completion
        // handler runs MainActor-isolated — handing its `item` straight to
        // `continuation.resume` trips Swift 6's "sending non-Sendable value"
        // check even though both sides are actually the same actor. `Box`
        // is the standard workaround: `@unchecked Sendable` because we
        // control both ends of the handoff and never touch `item` from
        // anywhere but this actor.
        let box = await withCheckedContinuation { (continuation: CheckedContinuation<Box<MKMapItem?>, Never>) in
            request.getMapItem { item, _ in
                continuation.resume(returning: Box(item))
            }
        }
        return box.value
    }

    private struct Box<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// iOS 17 fallback: a tight, name-scoped local search centered on the
    /// tapped coordinate. A ~150m span keeps this from matching a
    /// same-named café blocks away.
    private static func localSearchMapItem(name: String, coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        guard !name.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)
        )
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        let response = try? await search.start()
        return response?.mapItems.first
    }
}
