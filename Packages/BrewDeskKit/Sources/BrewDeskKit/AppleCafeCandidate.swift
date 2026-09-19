import CoreLocation
import MapKit
import VenueKit

/// A tapped Apple base-map café/food-drink POI label that did NOT resolve to
/// one of our own venues (brewdesk#182, `AppleFeatureMatcher`) — what drives
/// `AppleFeatureCard`. Also constructed straight from a gap-fill result
/// (`AppleGapFillService`), which is already pre-deduped against `venues`.
///
/// Deliberately holds only what the card needs to render and act — never a
/// cached `MapFeature`/`MKMapItem` beyond the single async lookup in flight
/// (bd#182: "never persist Apple results to disk or server").
public struct AppleCafeCandidate: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D
    public let category: MKPointOfInterestCategory?

    public init(name: String, coordinate: CLLocationCoordinate2D, category: MKPointOfInterestCategory? = nil) {
        self.id = "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"
        self.name = name
        self.coordinate = coordinate
        self.category = category
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
