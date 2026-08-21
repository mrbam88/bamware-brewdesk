import Foundation
import VenueKit

/// Launch-argument seam for UI tests. Inert in normal launches: one argument
/// lookup at view construction, nothing else. Precedent: `-UITestSkipGates`.
///
///   -UITestScenario <ScenarioVenueService.Scenario.rawValue>
///   -UITestLocationDenied
enum UITestScenario {
    static let scenarioArgument = "-UITestScenario"
    static let locationDeniedArgument = "-UITestLocationDenied"

    static func current(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> ScenarioVenueService.Scenario? {
        guard let index = arguments.firstIndex(of: scenarioArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return ScenarioVenueService.Scenario(rawValue: arguments[index + 1])
    }

    static func isLocationDenied(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(locationDeniedArgument)
    }

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
