import SwiftUI
import VenueKit

struct RootView: View {
    private let configuration = AppConfiguration.brewDesk
    private let venueListing: any VenueListing
    private let venueDetails: any VenueDetailServing
    @State private var flow: AppFlowStore
    @State private var locationService = LocationService()

    init(
        venueListing: any VenueListing = VenueAPI(),
        venueDetails: any VenueDetailServing = VenueAPI()
    ) {
        self.venueListing = venueListing
        self.venueDetails = venueDetails
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
        #if DEBUG
        // Env switch tears the whole stack down via .id — models rebuild
        // against the new base URL; no mixed-environment data survives.
        let env = DebugEnvironmentStore.shared.current
        DiscoveryRootView(
            configuration: configuration,
            locationService: locationService,
            venueListing: VenueAPI(baseURL: env.baseURL),
            venueDetails: VenueAPI(baseURL: env.baseURL)
        )
        .environment(\.venuePhotoService, VenueAPI(baseURL: env.baseURL))
        .id(env)
        #else
        DiscoveryRootView(
            configuration: configuration,
            locationService: locationService,
            venueListing: venueListing,
            venueDetails: venueDetails
        )
        .environment(\.venuePhotoService, venueListing as? any VenuePhotoServing)
        #endif
    }
}

#Preview {
    RootView()
}
