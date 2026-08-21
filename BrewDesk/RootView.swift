import BrewDeskKit
import SwiftUI
import VenueKit

struct RootView: View {
    private let configuration = AppConfiguration.brewDesk
    private let venueListing: any VenueListing
    private let venueDetails: any VenueDetailServing
    // UI-test fixture seam (`-UITestScenario <name>`); nil in every normal launch.
    private let uiTestScenario: ScenarioVenueService.Scenario?
    private let uiTestTakeoutURL: URL?
    // Bundled first-paint venues (brewdesk#28). Decoded once here; scenario
    // launches opt in with `-UITestSeedSnapshot` so degraded-state tests that
    // pin the no-snapshot states keep their meaning.
    private let snapshot: [Venue]
    @State private var flow: AppFlowStore
    @State private var locationService = LocationService()

    init(
        venueListing: any VenueListing = VenueAPI(),
        venueDetails: any VenueDetailServing = VenueAPI()
    ) {
        self.venueListing = venueListing
        self.venueDetails = venueDetails
        let scenario = UITestScenario.current()
        self.uiTestScenario = scenario
        self.uiTestTakeoutURL = scenario == nil ? nil : UITestScenario.takeoutFixtureURL()
        self.snapshot = (scenario == nil || UITestScenario.seedsSnapshot()) ? VenueSnapshot.load() : []
        _flow = State(initialValue: AppFlowStore())
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-UITestSkipGates") {
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
    }

    @ViewBuilder
    private var discovery: some View {
        if let uiTestScenario {
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
            .environment(\.venuePhotoService, VenueAPI(baseURL: env.baseURL))
            .id(env)
            #else
            DiscoveryRootView(
                configuration: configuration,
                locationService: locationService,
                venueListing: venueListing,
                venueDetails: venueDetails,
                snapshot: snapshot
            )
            .environment(\.venuePhotoService, venueListing as? any VenuePhotoServing)
            #endif
        }
    }
}

#Preview {
    RootView()
}
