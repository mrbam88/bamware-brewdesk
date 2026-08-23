// Push Phase A (brewdesk#93) — tapping the local reminder deep-links to the
// venue detail. No backend: the payload is just the `venueId` this process
// scheduled (see `VisitReminderContent.venueIdKey`). `StoreSurface.isGated`
// needs no special-casing here — `VenueDetailScreen` already hides the
// observation entry card when gated (brewdesk#67), so routing to detail
// alone already satisfies "gated → detail only, no observation form".
import Foundation
import Observation
import UserNotifications

/// The venue id a tapped reminder wants the app to open, captured by
/// `VisitReminderNotificationDelegate` and consumed by `DiscoveryRootView`.
/// A tiny `@Observable` singleton rather than a `NotificationCenter` post:
/// SwiftUI can `.onChange`/`.task` off an `@Observable` property directly,
/// and a cold launch (tap on a killed app) sees the value on first render
/// instead of racing a one-shot notification.
@MainActor
@Observable
public final class VisitReminderDeepLinkRouter {
    public static let shared = VisitReminderDeepLinkRouter()

    public private(set) var pendingVenueID: String?

    public init() {}

    public func receive(venueID: String) {
        pendingVenueID = venueID
    }

    /// Called once the deep link has been handled (venue fetched and
    /// pushed, or the fetch failed) so the same tap doesn't replay.
    public func consume() {
        pendingVenueID = nil
    }
}

/// `UNUserNotificationCenterDelegate`: routes a tapped visit reminder into
/// `VisitReminderDeepLinkRouter`, and shows the banner even while the app is
/// foregrounded (otherwise a local notification is silent in-app).
/// BrewDeskKit's target default isolation is `@MainActor`; the async
/// delegate methods are called off-main by the framework and hop onto
/// MainActor automatically because this class is MainActor-isolated.
public final class VisitReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = VisitReminderNotificationDelegate()

    private let router: VisitReminderDeepLinkRouter

    public init(router: VisitReminderDeepLinkRouter = .shared) {
        self.router = router
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let venueID = response.notification.request.content.userInfo[VisitReminderContent.venueIdKey] as? String
        else { return }
        router.receive(venueID: venueID)
    }
}
