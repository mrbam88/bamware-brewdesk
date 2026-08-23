// Push Phase A — local rate-your-visit nudge (brewdesk#93, parent
// brewdesk#92). No backend, no network, no device tokens: every reminder is
// a local notification scheduled on-device after a Directions tap. Same
// constructor-injected capability pattern as `CaptureSubmissionService` —
// protocol here, `UNUserNotificationCenter` behind `UserNotificationVisitReminders`,
// deterministic `FakeVisitReminders` for unit + UI tests (never a real
// permission prompt in tests).
import Foundation
import UserNotifications

/// Mirrors the subset of `UNAuthorizationStatus` the UI needs to explain
/// itself: denied shows "Enable in Settings" instead of asking again.
public enum VisitReminderAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// The scheduling capability. BrewDeskKit's target default is
/// `@MainActor` — this protocol and every conformer are MainActor-isolated,
/// called from UI; `UserNotificationVisitReminders` hops off-main inside
/// `UNUserNotificationCenter` itself (its methods are already `async`).
public protocol VisitReminderScheduling: AnyObject {
    /// Current system authorization, read fresh from the OS.
    func currentAuthorizationStatus() async -> VisitReminderAuthorizationStatus
    /// Requests permission if not yet determined. Returns whether reminders
    /// may be scheduled (true only for `.authorized`).
    @discardableResult
    func requestAuthorization() async -> Bool
    /// Schedules the single pending reminder for `venueId`, replacing any
    /// earlier one for that venue (a second Directions tap reschedules
    /// rather than stacking duplicates).
    func schedule(venueId: String, name: String, at date: Date) async
    /// Cancels every pending visit reminder (toggle off).
    func cancelAll() async
    /// Pending reminder count — unit tests assert on it directly; UI tests
    /// read it through a UI-test-only debug label (`VisitReminderToggleRow`).
    var pendingCount: Int { get async }
}

/// Notification copy + the deep-link payload key. Kept as pure, testable
/// content generation, separate from the `UNUserNotificationCenter` glue.
/// Localized (en + es) via `BrewDesk/Localizable.xcstrings` — `Bundle.main`
/// is the host app for both `Text` and `String(localized:)` calls made from
/// this package, so the catalog lives in the app target (see
/// `DatasetStatStrip`/`Components` for the same convention).
public enum VisitReminderContent {
    /// `UNNotificationRequest.content.userInfo` key carrying the venue id
    /// the deep link routes to.
    public static let venueIdKey = "venueId"

    public static func title(venueName: String) -> String {
        String(format: String(localized: "How was %@?"), venueName)
    }

    public static var body: String {
        String(localized: "Rate your visit to help other remote workers.")
    }

    static func makeContent(venueId: String, venueName: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title(venueName: venueName)
        content.body = body
        content.sound = .default
        content.userInfo = [venueIdKey: venueId]
        return content
    }
}

/// Real implementation: `UNUserNotificationCenter.current()`. `.shared` is
/// one instance per process so every screen that touches reminders — the
/// Directions-tap prompt and the Saved toggle — reads the same pending set
/// (same role as `AccountSessionStore.shared`).
public final class UserNotificationVisitReminders: VisitReminderScheduling {
    public static let shared = UserNotificationVisitReminders()

    /// Every scheduled reminder gets this identifier; `add(_:)` replaces a
    /// request that reuses an identifier, so re-tapping Directions on the
    /// same venue reschedules instead of duplicating.
    static func identifier(for venueId: String) -> String { "brewdesk.visit-reminder.\(venueId)" }

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func currentAuthorizationStatus() async -> VisitReminderAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func schedule(venueId: String, name: String, at date: Date) async {
        let content = VisitReminderContent.makeContent(venueId: venueId, venueName: name)
        // Minimum 60s: a `0`/negative interval (a clock that already passed
        // the target, or a test racing the clock) would fire immediately —
        // never useful for a "come back in two hours" nudge.
        let interval = max(60, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: venueId),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    public var pendingCount: Int {
        get async { await center.pendingNotificationRequests().count }
    }
}

/// Deterministic in-process double. Records every schedule/cancel call for
/// assertions; never touches `UNUserNotificationCenter`, so package tests
/// and UI tests never trigger a real system permission prompt.
public final class FakeVisitReminders: VisitReminderScheduling {
    /// Process-wide instance for `-UITestScenario` launches (fresh per UI
    /// test process), mirroring `AuthScenarioService.shared`. The
    /// Directions-tap prompt and the Saved toggle must observe the same
    /// pending set across screen instances within one UI test.
    public static let shared = FakeVisitReminders()

    public nonisolated struct ScheduledReminder: Equatable, Sendable {
        public let venueId: String
        public let name: String
        public let at: Date
    }

    /// Script the next `requestAuthorization()` result before it's called.
    public var authorizationGrantResult = true
    public private(set) var authorizationStatus: VisitReminderAuthorizationStatus = .notDetermined
    public private(set) var scheduled: [ScheduledReminder] = []
    public private(set) var cancelAllCallCount = 0

    public init() {}

    public func currentAuthorizationStatus() async -> VisitReminderAuthorizationStatus {
        authorizationStatus
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        authorizationStatus = authorizationGrantResult ? .authorized : .denied
        return authorizationGrantResult
    }

    public func schedule(venueId: String, name: String, at date: Date) async {
        scheduled.removeAll { $0.venueId == venueId }
        scheduled.append(ScheduledReminder(venueId: venueId, name: name, at: date))
    }

    public func cancelAll() async {
        cancelAllCallCount += 1
        scheduled.removeAll()
    }

    public var pendingCount: Int {
        get async { scheduled.count }
    }

    /// Test-only reset so `.shared` doesn't leak state between package
    /// tests that choose to use the singleton.
    public func reset() {
        authorizationGrantResult = true
        authorizationStatus = .notDetermined
        scheduled.removeAll()
        cancelAllCallCount = 0
    }
}
