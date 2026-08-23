// Push Phase A (brewdesk#93) — permission is asked from exactly two places:
// (a) the one-time inline prompt after a Directions tap, (b) the Saved tab
// toggle. Never on launch. This file owns that session-scoped state plus the
// on/off preference; `VenueDetailScreen`/`SavedCafesScreen` only add small
// hook lines that read it (see those files' diffs).
import Foundation
import Observation

/// Where the on/off preference is kept between launches. Same shape as
/// `SavedVenuePersisting` — a protocol so tests don't touch real
/// `UserDefaults`, a `UserDefaults.standard` conformer for production.
@MainActor
public protocol VisitReminderPreferencesPersisting: AnyObject {
    func loadEnabled() -> Bool
    func saveEnabled(_ enabled: Bool)
}

@MainActor
public final class UserDefaultsVisitReminderPreferences: VisitReminderPreferencesPersisting {
    private let defaults: UserDefaults
    private let key: String

    /// Default off (brewdesk#93 AC: no prompt on launch, nothing scheduled
    /// until the user opts in).
    public init(defaults: UserDefaults = .standard, key: String = "brewdesk.visit-reminders-enabled") {
        self.defaults = defaults
        self.key = key
    }

    public func loadEnabled() -> Bool { defaults.bool(forKey: key) }
    public func saveEnabled(_ enabled: Bool) { defaults.set(enabled, forKey: key) }
}

/// Ephemeral persistence for `-UITestScenario` launches: every process
/// starts disabled, deterministically — same role as `InMemorySessionStore`
/// for `AccountSessionStore.shared`. Real `UserDefaults.standard` would leak
/// a "Yes" from one UI test run into the next launch's starting state
/// (observed while building this feature: a stale `true` from an earlier
/// run made every later launch start pre-enabled and skip the prompt).
@MainActor
public final class InMemoryVisitReminderPreferences: VisitReminderPreferencesPersisting {
    private var enabled = false

    public init() {}

    public func loadEnabled() -> Bool { enabled }
    public func saveEnabled(_ enabled: Bool) { self.enabled = enabled }
}

/// A venue pending the one-time inline "Remind me to rate this visit?" ask.
public struct VisitReminderPromptTarget: Equatable, Sendable {
    public let venueId: String
    public let venueName: String

    public init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
    }
}

/// Process-wide reminder state: the on/off preference, the pending inline
/// prompt (if any), and the "already asked this session" latch. `.shared`
/// picks the real `UNUserNotificationCenter` rail normally and the
/// deterministic fake under `-UITestScenario` — same switch
/// `AccountSessionStore.shared` makes for its persistence.
@MainActor
@Observable
public final class VisitReminderSettings {
    public static let shared: VisitReminderSettings = {
        let isUITestScenario = ProcessInfo.processInfo.arguments.contains("-UITestScenario")
        let reminders: any VisitReminderScheduling = isUITestScenario
            ? FakeVisitReminders.shared
            : UserNotificationVisitReminders.shared
        let persistence: any VisitReminderPreferencesPersisting = isUITestScenario
            ? InMemoryVisitReminderPreferences()
            : UserDefaultsVisitReminderPreferences()
        return VisitReminderSettings(reminders: reminders, persistence: persistence)
    }()

    public private(set) var isEnabled: Bool
    /// Non-nil while the inline Directions-tap prompt should be visible.
    public private(set) var promptTarget: VisitReminderPromptTarget?
    /// The "one-time inline prompt" latch (brewdesk#93): "Not now" never
    /// asks again this session. In-memory only — a fresh process (relaunch)
    /// gets a fresh chance, matching "session" rather than "forever".
    public private(set) var hasPromptedThisSession = false
    public private(set) var authorizationStatus: VisitReminderAuthorizationStatus = .notDetermined
    /// Mirrors what's pending, updated synchronously alongside every
    /// schedule/cancel this object makes — not sourced from `reminders
    /// .pendingCount` (which is `async`, since the real
    /// `UNUserNotificationCenter` API is). A plain `@Observable` property
    /// lets `VisitReminderToggleRow`'s debug label read it directly with no
    /// `.task`/await needed.
    public private(set) var localPendingCount = 0

    @ObservationIgnored
    private var pendingVenueIDs: Set<String> = []
    @ObservationIgnored
    private let reminders: any VisitReminderScheduling
    @ObservationIgnored
    private let persistence: any VisitReminderPreferencesPersisting
    /// Reminder lead time: 2 hours after a Directions tap (brewdesk#93).
    @ObservationIgnored
    private let leadTime: TimeInterval

    public init(
        reminders: any VisitReminderScheduling,
        persistence: any VisitReminderPreferencesPersisting = UserDefaultsVisitReminderPreferences(),
        leadTime: TimeInterval = 2 * 60 * 60
    ) {
        self.reminders = reminders
        self.persistence = persistence
        self.leadTime = leadTime
        isEnabled = persistence.loadEnabled()
    }

    /// Refreshes `authorizationStatus` from the OS. Views call this on
    /// appear so a denied state (changed in system Settings) shows
    /// "Enable in Settings" without needing a relaunch.
    public func refreshAuthorizationStatus() async {
        authorizationStatus = await reminders.currentAuthorizationStatus()
    }

    // MARK: - Directions tap

    /// Call from the Directions button action (wrap in `Task { await }` —
    /// same convention as every other async button action in this codebase,
    /// e.g. `CafeListScreen`'s retry). Already enabled → schedules silently.
    /// Not yet asked this session → surfaces the inline prompt. Already
    /// declined this session → does nothing (never asks twice).
    public func directionsTapped(venueId: String, name: String, now: Date = Date()) async {
        if isEnabled {
            await scheduleVisitReminder(venueId: venueId, name: name, at: now.addingTimeInterval(leadTime))
            return
        }
        guard !hasPromptedThisSession else { return }
        hasPromptedThisSession = true
        promptTarget = VisitReminderPromptTarget(venueId: venueId, venueName: name)
    }

    /// "Yes" on the inline prompt: asks the system, and on grant schedules
    /// the reminder for the venue that triggered the prompt.
    public func acceptPrompt(now: Date = Date()) async {
        guard let target = promptTarget else { return }
        promptTarget = nil
        let granted = await enable()
        guard granted else { return }
        await scheduleVisitReminder(venueId: target.venueId, name: target.venueName, at: now.addingTimeInterval(leadTime))
    }

    /// "Not now": dismisses without ever asking the system.
    public func declinePrompt() {
        promptTarget = nil
    }

    // MARK: - Saved tab toggle

    /// Toggled on: requests system permission (if not already determined)
    /// and persists the result. Toggled off: persists off and cancels every
    /// pending reminder.
    public func setEnabled(_ enabled: Bool) async {
        if enabled {
            await enable()
        } else {
            isEnabled = false
            persistence.saveEnabled(false)
            await reminders.cancelAll()
            pendingVenueIDs.removeAll()
            localPendingCount = 0
        }
    }

    /// Same contract as `setEnabled(_:)`, for the Toggle's `Binding` setter
    /// specifically. `isEnabled` (and, off, `localPendingCount`) flip
    /// synchronously, before any `await` — a Binding setter that only
    /// *starts* async work, rather than one wrapped whole in `Task { await
    /// setEnabled() }`, keeps the switch's own visible state changing in
    /// the same turn as the tap that drove it.
    public func toggleEnabled(_ enabled: Bool) {
        isEnabled = enabled
        persistence.saveEnabled(enabled)
        if enabled {
            Task {
                let granted = await reminders.requestAuthorization()
                // The user may have already flipped it back off while this
                // was in flight — never re-enable out from under them.
                guard isEnabled else { return }
                isEnabled = granted
                authorizationStatus = granted ? .authorized : .denied
                persistence.saveEnabled(granted)
            }
        } else {
            pendingVenueIDs.removeAll()
            localPendingCount = 0
            Task {
                await reminders.cancelAll()
            }
        }
    }

    @discardableResult
    private func enable() async -> Bool {
        let granted = await reminders.requestAuthorization()
        isEnabled = granted
        authorizationStatus = granted ? .authorized : .denied
        persistence.saveEnabled(granted)
        return granted
    }

    private func scheduleVisitReminder(venueId: String, name: String, at date: Date) async {
        guard isEnabled else { return }
        await reminders.schedule(venueId: venueId, name: name, at: date)
        pendingVenueIDs.insert(venueId)
        localPendingCount = pendingVenueIDs.count
    }

    // MARK: - Debug / tests

    /// The scheduler's own count — used by unit tests, which assert against
    /// `FakeVisitReminders` directly rather than this mirror.
    public var pendingCount: Int {
        get async { await reminders.pendingCount }
    }
}
