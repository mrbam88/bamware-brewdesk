import Foundation
import Observation

@MainActor
@Observable
final class AppFlowStore {
    private enum Key {
        static let onboardingComplete = "brewdesk.onboarding.complete"
        static let locationIntroComplete = "brewdesk.location-intro.complete"
    }

    private let defaults: UserDefaults
    var onboardingComplete: Bool
    var locationIntroComplete: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        locationIntroComplete = defaults.bool(forKey: Key.locationIntroComplete)
    }

    func finishOnboarding() {
        onboardingComplete = true
        defaults.set(true, forKey: Key.onboardingComplete)
    }

    func finishLocationIntro() {
        locationIntroComplete = true
        defaults.set(true, forKey: Key.locationIntroComplete)
    }

    #if DEBUG
    func reset() {
        defaults.removeObject(forKey: Key.onboardingComplete)
        defaults.removeObject(forKey: Key.locationIntroComplete)
        onboardingComplete = false
        locationIntroComplete = false
    }
    #endif
}
