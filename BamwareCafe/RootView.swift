import SwiftUI

struct RootView: View {
    private let configuration = AppConfiguration.cafe
    @State private var flow: AppFlowStore
    @State private var subscriptions: SubscriptionStore
    @State private var auth: AuthSessionStore
    @State private var locationService = LocationService()

    init() {
        let configuration = AppConfiguration.cafe
        _flow = State(initialValue: AppFlowStore())
        _subscriptions = State(initialValue: SubscriptionStore(configuration: configuration))
        _auth = State(initialValue: AuthSessionStore(configuration: configuration))
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-UITestSkipGates") {
                DiscoveryRootView(auth: auth, locationService: locationService)
            } else if !flow.onboardingComplete {
                OnboardingView(configuration: configuration) { flow.finishOnboarding() }
            } else if !subscriptions.hasProAccess {
                PaywallView(configuration: configuration, store: subscriptions)
            } else {
                switch auth.state {
                case .hydrating:
                    ProgressView("Restoring your session…")
                case .signedOut:
                    AuthenticationView(configuration: configuration, auth: auth)
                case .authenticated:
                    if flow.locationIntroComplete {
                        DiscoveryRootView(auth: auth, locationService: locationService)
                    } else {
                        LocationPermissionView(locationService: locationService) {
                            flow.finishLocationIntro()
                        }
                    }
                }
            }
        }
        .task {
            async let entitlement: Void = subscriptions.prepare()
            async let session: Void = auth.hydrate()
            _ = await (entitlement, session)
        }
    }
}

#Preview {
    RootView()
}
