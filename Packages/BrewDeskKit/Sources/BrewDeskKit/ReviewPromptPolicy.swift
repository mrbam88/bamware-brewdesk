import Foundation

/// Pure decision logic for the App Store rating prompt (brewdesk#160): ask
/// only after the user's 2nd successful save, at most once per app
/// version, and never on the same calendar day the app was first launched
/// — a save minutes after install is still onboarding, not a happy moment.
///
/// StoreKit-free by design. `@Environment(\.requestReview)` is a SwiftUI
/// view-layer concern (`VenueDetailScreen`'s save handler); this type only
/// decides whether the view should call it, so it stays unit-testable
/// without a StoreKit environment.
///
/// State lives in `UserDefaults` under the `brewdesk.review-prompt.*` keys,
/// already covered by the `NSPrivacyAccessedAPICategoryUserDefaults`
/// (`CA92.1`, same-app-only) reason in `PrivacyInfo.xcprivacy` — no
/// manifest change needed.
public struct ReviewPromptPolicy {
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: Calendar
    private let appVersion: String

    private enum Key {
        static let saveCount = "brewdesk.review-prompt.save-count"
        static let firstLaunchDay = "brewdesk.review-prompt.first-launch-day"
        static let lastPromptedVersion = "brewdesk.review-prompt.last-prompted-version"
    }

    /// - Parameters:
    ///   - defaults: injectable for tests; production default is `.standard`.
    ///   - clock: injectable "now" for tests; production default is `Date.init`.
    ///   - calendar: injectable for tests (day-boundary comparisons);
    ///     production default is `.current`.
    ///   - appVersion: injectable for tests; production default reads
    ///     `CFBundleShortVersionString` from the main bundle.
    public init(
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    ) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        self.appVersion = appVersion
    }

    /// Call once at app launch (`RootView.init`) so "first launch day" has
    /// a real baseline. Idempotent — only the first call for an install
    /// actually writes; later calls (every subsequent launch) are no-ops.
    public func recordFirstLaunchIfNeeded() {
        guard defaults.object(forKey: Key.firstLaunchDay) == nil else { return }
        defaults.set(clock(), forKey: Key.firstLaunchDay)
    }

    /// Call from the save-success path only — never for an un-save.
    /// Increments the persisted save count and returns whether the caller
    /// should invoke `requestReview()` right now. Also seeds "first launch
    /// day" if it was never recorded, so this stays correct even if a
    /// caller forgets `recordFirstLaunchIfNeeded()` at launch.
    public func recordSaveAndShouldPrompt() -> Bool {
        recordFirstLaunchIfNeeded()

        let count = defaults.integer(forKey: Key.saveCount) + 1
        defaults.set(count, forKey: Key.saveCount)

        guard count >= 2 else { return false }
        guard defaults.string(forKey: Key.lastPromptedVersion) != appVersion else { return false }
        guard !isFirstLaunchDay(now: clock()) else { return false }

        defaults.set(appVersion, forKey: Key.lastPromptedVersion)
        return true
    }

    private func isFirstLaunchDay(now: Date) -> Bool {
        guard let firstLaunchDay = defaults.object(forKey: Key.firstLaunchDay) as? Date else {
            return false
        }
        return calendar.isDate(firstLaunchDay, inSameDayAs: now)
    }
}
