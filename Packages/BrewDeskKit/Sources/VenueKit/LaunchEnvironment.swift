import Foundation

/// What this launch was configured with — the one place every `-UITest*` /
/// `-brewdesk.*` launch argument gets parsed (bd#101).
///
/// Before this type, 15 production sites each ran their own
/// `ProcessInfo.processInfo.arguments` scan and picked their own
/// real-vs-fake adapter; two variants of the "is this a scenario launch"
/// check had already diverged (a raw `.contains("-UITestScenario")` versus
/// a parsed-and-validated scenario name). `LaunchEnvironment` is the single
/// definition: parse once, consult everywhere.
///
/// An injected value, not a global — construct it explicitly
/// (`LaunchEnvironment(arguments:)`, or a literal in tests) and pass it to
/// whatever needs it. `.current` exists only as the app-entry convenience;
/// no module outside `BrewDeskApp`/`RootView` should call it directly.
/// Everything else takes an `environment: LaunchEnvironment` parameter
/// (defaulted to `.current` for phase-1 singletons — the composition-root
/// cut that removes even that default is the follow-up ticket).
public struct LaunchEnvironment: Sendable, Equatable {
    /// `-UITestScenario <ScenarioVenueService.Scenario.rawValue>`. `nil` for
    /// a normal launch, for a missing value, and for an unrecognized name.
    public let scenario: ScenarioVenueService.Scenario?
    /// `-UITestLocationDenied` — pins `LocationService.authorizationStatus`
    /// to `.denied`.
    public let locationDenied: Bool
    /// `-UITestLocationUndetermined` — pins `LocationService.authorizationStatus`
    /// to `.notDetermined` until `requestAccess()` is called (brewdesk#149).
    public let locationUndetermined: Bool
    /// `-UITestSeedSnapshot` — scenario launches opt in to the bundled
    /// first-paint snapshot (normal launches always load it).
    public let seedSnapshot: Bool
    /// `-UITestSkipGates` — `RootView` skips onboarding/location-intro.
    public let skipGates: Bool
    /// `-UITestNoPhotos` — nils the photo service (App Store screenshot
    /// capture must not feature Google Places photos).
    public let noPhotos: Bool
    /// `-UITestFrameStats` — shows the map's frame-timing HUD.
    public let frameStats: Bool
    /// `-UITestCaptureFailures <n>` — a scripted mock fails the first `n`
    /// capture submits. `nil` unless `n` parses as an integer `> 0`
    /// (mirrors the pre-existing resolver contract).
    public let captureFailures: Int?
    /// `-brewdesk.saved-venue-ids "(...)"` — the NSArgumentDomain
    /// old-style plist array syntax UI tests actually pass (grepped out of
    /// `BrewDeskUITests`), e.g. `()` or `("fixture-roasters")`. `nil` when
    /// absent; not yet consumed by `SavedVenuesStore` (out of this
    /// ticket's fence — it still reads `UserDefaults.standard` directly,
    /// which the OS populates from this same argument).
    public let savedVenueIDs: [String]?
    /// `-brewdesk.uitest-fixed-now yyyy-MM-dd'T'HH:mm` (local wall time) —
    /// pins the clock the venue-detail open-now badge is judged against.
    /// `nil` when absent or unparseable.
    public let fixedNow: Date?
    /// `-UITestAppleGapFill` (bd#182) — opts a launch into the on-device
    /// Apple `MKLocalPointsOfInterestRequest` gap-fill (grey "unverified"
    /// markers shown when the visible region has fewer than
    /// `AppleGapFillService.minimumPinsBeforeGapFill` of our own pins).
    /// Absent by default: this is a spend-free but still network-calling
    /// feature, so every normal and store-submission launch keeps it off
    /// until a real toggle ships — same "always compiled, inert outside the
    /// flag" convention as `MapFrameStatsHUD.isEnabled`.
    public let appleGapFillEnabled: Bool
    /// `-brewdesk.apple-feature-fixture "<name>|<lat>|<lng>"` (bd#182) —
    /// forces `CafeMapScreen` to open the "not in BrewDesk yet" Apple
    /// feature card for this fixed name/coordinate on launch, standing in
    /// for a real tap on an Apple base-map POI label. Apple's own labels
    /// are drawn by the platform map layer, not the accessibility tree, so
    /// `MapFeatureCardUITests` cannot reliably tap one on the simulator —
    /// this fixture is the seam that exercises the card's rendering and
    /// actions instead. `nil` when absent or malformed.
    public let appleFeatureFixture: AppleFeatureFixture?
    /// `-UITestForceLaunchReveal` (bamware-brewdesk#186) — the one seam
    /// that forces `LaunchRevealView` to run even though `isUITestRun` is
    /// true. Every other `-UITest*` launch skips the reveal outright (it's
    /// a purely cosmetic cold-launch moment that would otherwise make every
    /// UI test race a ~1.2s overlay); this flag exists for the one UI test
    /// that specifically asserts the reveal's own behavior.
    public let forceLaunchReveal: Bool
    /// `-UITestFreezeLaunchRevealAtMS <ms>` (bamware-brewdesk#193) — pins
    /// `LaunchRevealView` to a single fixed frame instead of advancing with
    /// real time, and suspends its own auto-dismiss. A screenshot-capture
    /// seam only: real time (a ~1.2s window, sub-400ms stage transitions)
    /// is too fast for `simctl io recordVideo` to reliably land a frame on
    /// a specific stage like "arcs mid-draw" or "light sweep active" — this
    /// makes that deterministic. Requires `forceLaunchReveal` to have any
    /// effect. `nil` when absent or unparseable.
    public let freezeLaunchRevealAtMS: Double?
    /// `-brewdesk.uitest-fixed-location "<lat>|<lng>"` (bd#198): pins
    /// `LocationService` to this coordinate and, unlike `-UITestLocation*`
    /// (which only pin `authorizationStatus`), makes it deliver an
    /// authorized real-looking fix immediately and then re-deliver the same
    /// coordinate roughly once a second — standing in for real CoreLocation
    /// periodically re-sending the same fix. `MapLocateButtonUITests`
    /// documents why a genuinely simulated GPS fix instead needs host-side
    /// `xcrun simctl location` setup and quietly skips when that isn't
    /// provisioned; a regression test proving GPS ticks can't overwrite an
    /// explored viewport needs to run deterministically in CI, so this
    /// flag exists instead of depending on that. `nil` when absent or
    /// malformed.
    public let fixedLocation: FixedLocationFixture?
    /// `-brewdesk.debug.initial-span <metres-per-point>` (bd#212, revised
    /// after supervisor review) — opens the map's camera at this real-world
    /// metres-per-screen-point instead of the normal GPS-fix/Browse-NYC
    /// default. Metres/point, not a raw coordinate span in degrees: that's
    /// the same unit `MapAnnotationPlanner.headDiameter(forMetersPerPoint:)`
    /// sizes markers from, so a screenshot/perf script can name an exact
    /// marker-size target ("7.2 m/pt" ⇒ 4pt dots, "1.8 m/pt" ⇒ 17pt
    /// teardrops) rather than guessing a degree span that MapKit might
    /// render wider once it fits the device's aspect ratio. A test/
    /// screenshot seam only — `CafeMapScreen` only ever applies it alongside
    /// `isUITestRun` (some other `-UITest…` argument must also be present),
    /// so a real App Store/TestFlight launch — which never carries one —
    /// can't be driven by it. `nil` when absent, unparseable, or
    /// non-positive.
    public let debugInitialMetersPerPoint: Double?
    /// `-brewdesk.recent-searches-seed '<json>'` (bd#223) — pre-populates
    /// `RecentSearchStore` (BrewDeskKit) for a UI test/screenshot that needs
    /// a recent already present (e.g. "tap Recent → flies back") without
    /// first driving a real selection. Kept as the raw JSON string here,
    /// same as `savedVenueIDs`' own "not yet consumed here" shape: this
    /// module (VenueKit) can't import `RecentSearchEntry`'s type
    /// (BrewDeskKit) without a cycle, so `RecentSearchStore.init` decodes
    /// this string itself. `nil` when the argument is absent, in which case
    /// a UI-test-run store starts empty instead (see `RecentSearchStore.init`
    /// — every `-UITest…` launch resets recents one way or the other, never
    /// inheriting a previous run's UserDefaults).
    public let recentSearchSeedJSON: String?
    /// True when ANY `-UITest…` launch argument is present — the one seam
    /// that holds for every automated UI run, scenario or live. Every UI
    /// test that can reach user flows passes at least one (`-UITestSkipGates`
    /// for the live-rail tests such as `testSaveCafeFromDetails`). Used where
    /// `scenario == nil` is too narrow (brewdesk#160's rating prompt: the
    /// save counter persists on a simulator across runs, and a system rating
    /// sheet mid-test would block taps). Deliberately NOT an environment
    /// variable: `XCTestConfigurationFilePath` exists in the test-runner
    /// process, not in an app launched by XCUITest.
    public let isUITestRun: Bool

    /// Every UI-test flag absent — the real-world default for every launch
    /// that isn't a UI test.
    public static let production = LaunchEnvironment(arguments: [])

    /// App-entry convenience ONLY. Reads `ProcessInfo.processInfo
    /// .arguments` — the one production call site that does. Every other
    /// module takes a `LaunchEnvironment` value instead of calling this.
    public static var current: LaunchEnvironment {
        LaunchEnvironment(arguments: ProcessInfo.processInfo.arguments)
    }

    /// Unknown `-UITestScenario` names `assertionFailure` (a no-op outside
    /// Debug — see the stdlib's `assertionFailure`) so a typo in a UI test
    /// launch argument is caught in development rather than silently
    /// falling back to the live rail.
    public init(arguments: [String]) {
        self.init(arguments: arguments, assertOnUnknownScenario: true)
    }

    /// Non-asserting variant so tests can exercise the "unknown scenario
    /// name → nil" contract without tripping `assertionFailure` in a
    /// Debug-configured test host.
    init(arguments: [String], assertOnUnknownScenario: Bool) {
        let scenarioName = Self.value(after: "-UITestScenario", in: arguments)
        let scenario = scenarioName.flatMap(ScenarioVenueService.Scenario.init(rawValue:))
        if let scenarioName, scenario == nil, assertOnUnknownScenario {
            assertionFailure("LaunchEnvironment: unknown -UITestScenario name \"\(scenarioName)\"")
        }
        self.scenario = scenario
        locationDenied = arguments.contains("-UITestLocationDenied")
        locationUndetermined = arguments.contains("-UITestLocationUndetermined")
        seedSnapshot = arguments.contains("-UITestSeedSnapshot")
        skipGates = arguments.contains("-UITestSkipGates")
        noPhotos = arguments.contains("-UITestNoPhotos")
        frameStats = arguments.contains("-UITestFrameStats")
        captureFailures = Self.value(after: "-UITestCaptureFailures", in: arguments)
            .flatMap(Int.init)
            .flatMap { $0 > 0 ? $0 : nil }
        savedVenueIDs = Self.value(after: "-brewdesk.saved-venue-ids", in: arguments)
            .flatMap(Self.parseOldStylePlistArray)
        fixedNow = Self.value(after: "-brewdesk.uitest-fixed-now", in: arguments)
            .flatMap(Self.parseFixedNow)
        appleGapFillEnabled = arguments.contains("-UITestAppleGapFill")
        appleFeatureFixture = Self.value(after: "-brewdesk.apple-feature-fixture", in: arguments)
            .flatMap(AppleFeatureFixture.init(raw:))
        forceLaunchReveal = arguments.contains("-UITestForceLaunchReveal")
        freezeLaunchRevealAtMS = Self.value(after: "-UITestFreezeLaunchRevealAtMS", in: arguments)
            .flatMap(Double.init)
        fixedLocation = Self.value(after: "-brewdesk.uitest-fixed-location", in: arguments)
            .flatMap(FixedLocationFixture.init(raw:))
        debugInitialMetersPerPoint = Self.value(after: "-brewdesk.debug.initial-span", in: arguments)
            .flatMap(Double.init)
            .flatMap { $0 > 0 ? $0 : nil }
        recentSearchSeedJSON = Self.value(after: "-brewdesk.recent-searches-seed", in: arguments)
        isUITestRun = arguments.contains { $0.hasPrefix("-UITest") }
    }

    /// The token immediately following `flag`, if any — the `-key value`
    /// convention every one of these arguments uses.
    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    /// Hand-rolled rather than `NSString.propertyList()`: that API raises
    /// an uncatchable `NSException` on malformed input, and a launch
    /// argument is exactly the kind of string a typo can malform. Handles
    /// the two shapes UI tests actually pass: `()` and
    /// `("a", "b", ...)`.
    private static func parseOldStylePlistArray(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return nil }
        let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return [] }
        return inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    private static func parseFixedNow(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: raw)
    }
}

/// `name|lat|lng` fixture for `-brewdesk.apple-feature-fixture` (bd#182).
/// A plain struct rather than reusing `Venue`: this stands in for an Apple
/// POI, not one of ours, and has no score/attributes to fabricate.
public struct AppleFeatureFixture: Sendable, Equatable {
    public let name: String
    public let lat: Double
    public let lng: Double

    public init(name: String, lat: Double, lng: Double) {
        self.name = name
        self.lat = lat
        self.lng = lng
    }

    init?(raw: String) {
        let parts = raw.components(separatedBy: "|")
        guard parts.count == 3, !parts[0].isEmpty,
              let lat = Double(parts[1]), let lng = Double(parts[2])
        else { return nil }
        self.init(name: parts[0], lat: lat, lng: lng)
    }
}

/// `lat|lng` fixture for `-brewdesk.uitest-fixed-location` (bd#198).
public struct FixedLocationFixture: Sendable, Equatable {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    init?(raw: String) {
        let parts = raw.components(separatedBy: "|")
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        self.init(lat: lat, lng: lng)
    }
}
