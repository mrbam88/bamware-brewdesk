// Push Phase A (brewdesk#93) — the two UI surfaces that ever ask for
// notification permission: the inline Directions-tap prompt, and the Saved
// tab toggle. Both are self-contained (own their styling, accessibility
// identifiers, and — for the toggle — service resolution), so the screens
// that host them stay one-line hooks.
import SwiftUI
import VenueKit

/// Inline card shown once, the first time a user taps Directions and hasn't
/// enabled reminders yet. "Not now" never asks the system for permission —
/// only "Yes" does. This purpose text is the in-app explanation that stands
/// in for a system usage-description string (none is required for local
/// notifications).
public struct VisitReminderPromptCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private let target: VisitReminderPromptTarget
    private let settings: VisitReminderSettings

    public init(target: VisitReminderPromptTarget, settings: VisitReminderSettings) {
        self.target = target
        self.settings = settings
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remind me to rate this visit?")
                .font(.headline)
                .foregroundStyle(theme.primaryColor)
            Text("One local reminder about two hours from now — no account, nothing sent anywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Not now") {
                    settings.declinePrompt()
                }
                .accessibilityIdentifier("visit-reminder-later")

                Spacer(minLength: 0)

                Button("Yes, remind me") {
                    Task { await settings.acceptPrompt() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrewDeskPalette.roast)
                .accessibilityIdentifier("visit-reminder-yes")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrewDeskPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("visit-reminder-prompt")
    }
}

/// Saved tab settings row (brewdesk#93 AC: "Settings row to turn reminders
/// off; cancel pending requests when off"). Resolves its own service the
/// same way `ObservationFormEntrySection` does, so `SavedCafesScreen`'s
/// addition stays a single line. A plain card (not a `List` `Section`) so it
/// drops into a `safeAreaInset` above every phase of the Saved tab —
/// loading, error, empty, and loaded all show the same row.
public struct VisitReminderToggleRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private let settings: VisitReminderSettings

    public init(settings: VisitReminderSettings = .shared) {
        self.settings = settings
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.authorizationStatus == .denied {
                HStack {
                    Label("Visit reminders", systemImage: "bell.badge")
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.primaryColor)
                    Spacer(minLength: 12)
                    Button("Enable in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.caption.bold())
                    .accessibilityIdentifier("visit-reminder-enable-in-settings")
                }
            } else {
                Toggle(isOn: Binding(
                    get: { settings.isEnabled },
                    set: { settings.toggleEnabled($0) }
                )) {
                    Label("Remind me to rate visits", systemImage: "bell.badge")
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.primaryColor)
                }
                .tint(BrewDeskPalette.roast)
                .accessibilityIdentifier("visit-reminder-toggle")
            }
            Text("One local reminder about two hours after you get directions to a café. Nothing is sent anywhere — turning this off cancels every pending reminder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Runtime-gated (not `#if DEBUG`): the app + UI test gate builds
            // Release (`ENABLE_TESTABILITY=YES`), which strips `#if DEBUG`
            // code — see `MapFrameStatsHUD.isEnabled` for the same
            // convention. `localPendingCount` is a plain `@Observable`
            // property (no `.task`/await needed to read it here).
            if UITestVisitReminderDebug.isEnabled {
                Text(verbatim: "pending: \(settings.localPendingCount)")
                    .font(.caption2)
                    .accessibilityIdentifier("visit-reminder-pending-count")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrewDeskPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("visit-reminder-settings-row")
        .task { await settings.refreshAuthorizationStatus() }
    }
}

/// UI-test-only seam: `pendingCount` has no other externally observable
/// signal (it lives inside `UNUserNotificationCenter`/`FakeVisitReminders`),
/// so `VisitReminderUITests` reads it off this debug label. Always compiled
/// in (like `MapFrameStatsHUD.isEnabled`) but inert outside `-UITestScenario`
/// launches — never renders in a normal or store-submission launch.
enum UITestVisitReminderDebug {
    static let isEnabled = LaunchEnvironment.current.scenario != nil
}
