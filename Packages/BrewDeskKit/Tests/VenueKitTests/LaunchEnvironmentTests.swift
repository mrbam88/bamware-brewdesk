import Foundation
import Testing

@testable import VenueKit

/// One module answering "what was this launch configured with" — the
/// deepening target for bd#101. Every field mirrors a real `-UITest*` /
/// `-brewdesk.*` launch argument grepped out of `BrewDesk`/`Packages` on
/// main; nothing speculative. Order independence and "absent → default"
/// are the load-bearing behaviors every call site now relies on instead of
/// re-deriving its own argument scan.
@Suite struct LaunchEnvironmentTests {
    // MARK: - Defaults

    @Test func absentArgumentsYieldProductionDefaults() {
        let environment = LaunchEnvironment(arguments: [])
        #expect(environment.scenario == nil)
        #expect(environment.locationDenied == false)
        #expect(environment.seedSnapshot == false)
        #expect(environment.skipGates == false)
        #expect(environment.noPhotos == false)
        #expect(environment.frameStats == false)
        #expect(environment.captureFailures == nil)
        #expect(environment.storeSurfaceGatedOverride == false)
        #expect(environment.savedVenueIDs == nil)
        #expect(environment.fixedNow == nil)
    }

    @Test func productionConstantMatchesEmptyArguments() {
        #expect(LaunchEnvironment.production == LaunchEnvironment(arguments: []))
    }

    // MARK: - Scenario

    @Test func knownScenarioNameParses() {
        let environment = LaunchEnvironment(arguments: ["-UITestScenario", "engineDown"])
        #expect(environment.scenario == .engineDown)
    }

    @Test func unknownScenarioNameYieldsNilWithoutAsserting() {
        // Non-asserting init: the production init would `assertionFailure`
        // here (Debug only — a no-op in Release, so this never fires
        // outside development). Tests reach for the internal, non-asserting
        // variant instead of crashing the Debug-configured test host.
        let environment = LaunchEnvironment(
            arguments: ["-UITestScenario", "not-a-real-scenario"],
            assertOnUnknownScenario: false
        )
        #expect(environment.scenario == nil)
    }

    @Test func scenarioFlagWithNoTrailingValueYieldsNil() {
        let environment = LaunchEnvironment(
            arguments: ["-UITestScenario"],
            assertOnUnknownScenario: false
        )
        #expect(environment.scenario == nil)
    }

    // MARK: - Boolean flags

    @Test func locationDeniedFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestLocationDenied"]).locationDenied)
    }

    @Test func seedSnapshotFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestSeedSnapshot"]).seedSnapshot)
    }

    @Test func skipGatesFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestSkipGates"]).skipGates)
    }

    @Test func noPhotosFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestNoPhotos"]).noPhotos)
    }

    @Test func frameStatsFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestFrameStats"]).frameStats)
    }

    @Test func storeSurfaceGatedOverrideFlagParses() {
        #expect(LaunchEnvironment(arguments: ["-UITestStoreSurfaceGated"]).storeSurfaceGatedOverride)
    }

    // MARK: - Capture failures (`-UITestCaptureFailures <n>`)

    @Test func captureFailuresParsesPositiveInt() {
        let environment = LaunchEnvironment(arguments: ["-UITestCaptureFailures", "3"])
        #expect(environment.captureFailures == 3)
    }

    @Test func captureFailuresZeroIsNil() {
        // Mirrors the pre-existing resolver contract: `failures > 0` only.
        let environment = LaunchEnvironment(arguments: ["-UITestCaptureFailures", "0"])
        #expect(environment.captureFailures == nil)
    }

    @Test func captureFailuresNonNumericIsNil() {
        let environment = LaunchEnvironment(arguments: ["-UITestCaptureFailures", "many"])
        #expect(environment.captureFailures == nil)
    }

    @Test func captureFailuresWithNoTrailingValueIsNil() {
        let environment = LaunchEnvironment(arguments: ["-UITestCaptureFailures"])
        #expect(environment.captureFailures == nil)
    }

    // MARK: - Saved venue IDs (`-brewdesk.saved-venue-ids "(...)"`)
    //
    // NSArgumentDomain old-style plist array syntax — the literal form
    // `BrewDeskUITests` passes today (grepped: `DegradedStateTests.swift`,
    // `BusinessInfoUITests.swift`, etc.), not a comma-separated string.

    @Test func savedVenueIDsEmptyParenIsEmptyArray() {
        let environment = LaunchEnvironment(arguments: ["-brewdesk.saved-venue-ids", "()"])
        #expect(environment.savedVenueIDs == [])
    }

    @Test func savedVenueIDsSingleQuotedEntryParses() {
        let environment = LaunchEnvironment(
            arguments: ["-brewdesk.saved-venue-ids", "(\"fixture-roasters\")"]
        )
        #expect(environment.savedVenueIDs == ["fixture-roasters"])
    }

    @Test func savedVenueIDsMultipleQuotedEntriesParse() {
        let environment = LaunchEnvironment(
            arguments: ["-brewdesk.saved-venue-ids", "(\"fixture-roasters\", \"missing-cafe\")"]
        )
        #expect(environment.savedVenueIDs == ["fixture-roasters", "missing-cafe"])
    }

    @Test func savedVenueIDsAbsentIsNil() {
        #expect(LaunchEnvironment(arguments: []).savedVenueIDs == nil)
    }

    // MARK: - Fixed clock (`-brewdesk.uitest-fixed-now yyyy-MM-dd'T'HH:mm`)

    @Test func fixedNowParsesLocalWallTime() {
        let environment = LaunchEnvironment(
            arguments: ["-brewdesk.uitest-fixed-now", "2026-08-19T10:00"]
        )
        var expected = DateComponents()
        expected.year = 2026
        expected.month = 8
        expected.day = 19
        expected.hour = 10
        expected.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        #expect(environment.fixedNow == calendar.date(from: expected))
    }

    @Test func fixedNowMalformedIsNil() {
        let environment = LaunchEnvironment(
            arguments: ["-brewdesk.uitest-fixed-now", "not-a-date"]
        )
        #expect(environment.fixedNow == nil)
    }

    // MARK: - Order independence

    @Test func flagOrderDoesNotMatter() {
        let forward = LaunchEnvironment(arguments: [
            "-UITestScenario", "fixtureOK",
            "-UITestSkipGates",
            "-UITestCaptureFailures", "2",
        ])
        let reversed = LaunchEnvironment(arguments: [
            "-UITestCaptureFailures", "2",
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
        ])
        #expect(forward == reversed)
    }

    // MARK: - Equatable

    @Test func equalArgumentsProduceEqualEnvironments() {
        let arguments = ["-UITestScenario", "offline", "-UITestNoPhotos"]
        #expect(LaunchEnvironment(arguments: arguments) == LaunchEnvironment(arguments: arguments))
    }
}
