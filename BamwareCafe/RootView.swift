import SwiftUI

struct RootView: View {
    private let configuration = AppConfiguration.cafe
    @State private var flow: AppFlowStore
    @State private var locationService = LocationService()

    init() {
        _flow = State(initialValue: AppFlowStore())
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-UITestSkipGates") {
                DiscoveryRootView(configuration: configuration, locationService: locationService)
            } else if !flow.onboardingComplete {
                OnboardingView(configuration: configuration) { flow.finishOnboarding() }
            } else if flow.locationIntroComplete {
                DiscoveryRootView(configuration: configuration, locationService: locationService)
            } else {
                LocationPermissionView(locationService: locationService) {
                    flow.finishLocationIntro()
                }
            }
        }
    }
}

#Preview {
    RootView()
}
