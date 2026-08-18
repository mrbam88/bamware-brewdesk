import Foundation
import Testing
@testable import BrewDesk

@Suite @MainActor struct AppFlowStoreTests {
    @Test func persistsCompletedGates() {
        let suite = "AppFlowStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppFlowStore(defaults: defaults)
        #expect(!store.onboardingComplete)
        #expect(!store.locationIntroComplete)

        store.finishOnboarding()
        store.finishLocationIntro()

        let restored = AppFlowStore(defaults: defaults)
        #expect(restored.onboardingComplete)
        #expect(restored.locationIntroComplete)
    }
}

@Suite @MainActor struct ReleaseConfigurationTests {
    @Test func usesBrewDeskIdentityAndCanonicalURLs() {
        let configuration = AppConfiguration.brewDesk

        #expect(configuration.appName == "BrewDesk")
        #expect(configuration.termsURL.absoluteString == "https://bamware.io/brewdesk/terms")
        #expect(configuration.privacyURL.absoluteString == "https://bamware.io/brewdesk/privacy")
        #expect(configuration.supportURL.absoluteString == "https://bamware.io/brewdesk/support")
    }
}
