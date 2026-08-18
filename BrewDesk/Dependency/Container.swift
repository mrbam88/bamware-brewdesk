import Factory
import VenueKit

/// Composition root: Factory owns object lifetimes at the app edge;
/// packages stay DI-framework-agnostic (constructor injection only).
extension Container {
    var venueAPI: Factory<VenueAPI> {
        self { VenueAPI() }.scope(.singleton)
    }
}
