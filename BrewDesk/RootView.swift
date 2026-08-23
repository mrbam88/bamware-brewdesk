import BrewDeskKit
import SwiftUI
import VenueKit

struct RootView: View {
    private let configuration = AppConfiguration.brewDesk
    private let venueListing: any VenueListing
    private let venueDetails: any VenueDetailServing
    // Parsed once here — the app's single ProcessInfo.arguments read
    // (bd#101). Every UI-test seam below consults this value instead of
    // re-scanning arguments itself.
    private let environment: LaunchEnvironment
    private let uiTestTakeoutURL: URL?
    // Bundled first-paint venues (brewdesk#28). Decoded once here; scenario
    // launches opt in with `-UITestSeedSnapshot` so degraded-state tests that
    // pin the no-snapshot states keep their meaning.
    private let snapshot: [Venue]
    @State private var flow: AppFlowStore
    @State private var locationService: LocationService

    init(
        venueListing: any VenueListing = VenueAPI(),
        venueDetails: any VenueDetailServing = VenueAPI()
    ) {
        self.venueListing = venueListing
        self.venueDetails = venueDetails
        let environment = LaunchEnvironment.current
        self.environment = environment
        self.uiTestTakeoutURL = environment.scenario == nil ? nil : UITestScenario.takeoutFixtureURL()
        self.snapshot = (environment.scenario == nil || environment.seedSnapshot) ? VenueSnapshot.load() : []
        _flow = State(initialValue: AppFlowStore())
        _locationService = State(initialValue: LocationService(environment: environment))
    }

    var body: some View {
        Group {
            if environment.skipGates {
                discovery
            } else if !flow.onboardingComplete {
                OnboardingView(configuration: configuration) { flow.finishOnboarding() }
            } else if flow.locationIntroComplete {
                discovery
            } else {
                LocationPermissionView(locationService: locationService) {
                    flow.finishLocationIntro()
                }
            }
        }
        .environment(\.launchEnvironment, environment)
    }

    @ViewBuilder
    private var discovery: some View {
        if let uiTestScenario = environment.scenario {
            // Deterministic fixtures for degraded-state UI tests. No network.
            let service = ScenarioVenueService(scenario: uiTestScenario)
            DiscoveryRootView(
                configuration: configuration,
                locationService: locationService,
                venueListing: service,
                venueDetails: service,
                snapshot: snapshot
            )
            .environment(\.venuePhotoService, service)
            .environment(\.takeoutImportAutorunURL, uiTestTakeoutURL)
        } else {
            #if DEBUG
            // Env switch tears the whole stack down via .id — models rebuild
            // against the new base URL; no mixed-environment data survives.
            let env = DebugEnvironmentStore.shared.current
            DiscoveryRootView(
                configuration: configuration,
                locationService: locationService,
                venueListing: VenueAPI(baseURL: env.baseURL),
                venueDetails: VenueAPI(baseURL: env.baseURL),
                snapshot: snapshot
            )
            .environment(\.venuePhotoService, uiTestPhotoService(VenueAPI(baseURL: env.baseURL)))
            .id(env)
            #else
            DiscoveryRootView(
                configuration: configuration,
                locationService: locationService,
                venueListing: venueListing,
                venueDetails: venueDetails,
                snapshot: snapshot
            )
            .environment(\.venuePhotoService, uiTestPhotoService(venueListing as? any VenuePhotoServing))
            #endif
        }
    }

    /// `-UITestNoPhotos` nils the photo service so photo UI never renders —
    /// used by the App Store screenshot capture (brewdesk#30: marketing
    /// screenshots must not feature Google Places photos). The fixture-driven
    /// scenario seam above keeps its own service; degraded-state tests cover
    /// photo behavior there.
    private func uiTestPhotoService(
        _ service: (any VenuePhotoServing)?
    ) -> (any VenuePhotoServing)? {
        environment.noPhotos ? nil : service
    }
}

#Preview {
    RootView()
}
