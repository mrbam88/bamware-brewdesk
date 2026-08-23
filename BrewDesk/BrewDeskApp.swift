import BrewDeskKit
import SwiftUI
import UserNotifications

@main
struct BrewDeskApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Registers the tap → deep-link route (brewdesk#93).
                // Registering a delegate never triggers a permission prompt
                // on its own — only `directionsTapped`/the Saved toggle do
                // that. Deferred to `.task` (not `App.init()`, which runs
                // before the scene attaches): `UNUserNotificationCenter
                // .current()` is an XPC round-trip, best not made that early
                // in the launch sequence.
                .task {
                    UNUserNotificationCenter.current().delegate = VisitReminderNotificationDelegate.shared
                }
        }
    }
}
