import Foundation
import VenueKit

/// Test-fixture file helper for UI-test scenario launches. The launch-flag
/// parsing this file used to own (`-UITestScenario`, `-UITestLocationDenied`,
/// `-UITestSeedSnapshot`) now lives in `LaunchEnvironment` (bd#101) — see
/// `RootView.init` and `LocationService.init(environment:)`.
enum UITestScenario {
    /// A one-row Takeout CSV that matches the first fixture venue by name, so
    /// UI tests can exercise the import flow without the system file picker.
    static func takeoutFixtureURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brewdesk-uitest-takeout.csv")
        let csv = "Title,Note,URL\nFixture Roasters,,\n"
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
