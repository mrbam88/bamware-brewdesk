import CoreLocation
import MapKit
import VenueKit

/// One Apple-only café/coffee POI shown as a grey "unverified" marker when
/// our own listing is thin for the visible region (bd#182). Never persisted
/// (MapKit ToS + the ticket's own constraint) — held only in `CafeMapScreen`
/// view state, recomputed on every camera settle, discarded on the next.
public struct AppleUnverifiedPOI: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(name: String, coordinate: CLLocationCoordinate2D) {
        self.id = "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"
        self.name = name
        self.coordinate = coordinate
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// Feature-flagged (default OFF — bd#182) on-device gap-fill: when the
/// visible region has fewer than `minimumPinsBeforeGapFill` of our own pins,
/// ask Apple directly for nearby cafe/coffee POIs
/// (`MKLocalPointsOfInterestRequest`, on-device, no spend) and show them as
/// grey "unverified" markers — `AppleUnverifiedPin` in
/// `MapAnnotationViews.swift`, deliberately never the same visual language
/// as a scored marker (`TeardropMarkerView`), so an unverified Apple result can never be mistaken
/// for one of our own claims.
@MainActor
public enum AppleGapFillService {
    /// Below this many of our own pins in the visible region, gap-fill
    /// kicks in (bd#182 ticket: "fewer than 5 of our pins" → N = 5).
    public static let minimumPinsBeforeGapFill = 5
    static let categories: [MKPointOfInterestCategory] = [.cafe, .bakery]

    /// Computed once from the launch's `-UITestAppleGapFill` flag — same
    /// "always compiled, inert outside the flag" convention as
    /// `MapFrameStatsHUD.isEnabled`. Default OFF in every real and
    /// store-submission launch.
    public static let isEnabled = LaunchEnvironment.current.appleGapFillEnabled

    public static func shouldGapFill(ourPinCount: Int) -> Bool {
        ourPinCount < minimumPinsBeforeGapFill
    }

    /// Queries Apple for cafe/coffee POIs in `region`, dropping anything
    /// that already matches one of `venues` (`AppleFeatureMatcher`) so a
    /// gap-fill marker never doubles up a real pin. `[]` on any failure —
    /// this is a nice-to-have overlay, never a load-bearing state.
    public static func fetch(region: MKCoordinateRegion, excluding venues: [Venue]) async -> [AppleUnverifiedPOI] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.placemark.coordinate
            guard AppleFeatureMatcher.matchingVenue(
                name: name, lat: coordinate.latitude, lng: coordinate.longitude, in: venues
            ) == nil else { return nil }
            return AppleUnverifiedPOI(name: name, coordinate: coordinate)
        }
    }
}
