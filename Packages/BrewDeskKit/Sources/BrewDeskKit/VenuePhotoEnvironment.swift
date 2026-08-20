import SwiftUI
import VenueKit

/// Optional-first photo service injection: screens read it from the SwiftUI
/// environment; nil (the default) means no photo UI renders anywhere.
private struct VenuePhotoServiceKey: EnvironmentKey {
    static let defaultValue: (any VenuePhotoServing)? = nil
}

extension EnvironmentValues {
    public var venuePhotoService: (any VenuePhotoServing)? {
        get { self[VenuePhotoServiceKey.self] }
        set { self[VenuePhotoServiceKey.self] = newValue }
    }
}
