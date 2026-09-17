import Foundation
import Testing
@testable import BrewDeskKit

/// brewdesk#160 — the three eligibility rules, each isolated on its own
/// ephemeral `UserDefaults` suite so tests never share persisted state.
@Suite struct ReviewPromptPolicyTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "review-prompt-tests-\(UUID().uuidString)")!
    }

    // MARK: - Count rule

    @Test func firstSaveNeverPrompts() {
        let defaults = freshDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, clock: { .day2 }, appVersion: "1.0")

        #expect(policy.recordSaveAndShouldPrompt() == false)
    }

    @Test func secondSavePromptsOnceThenStaysQuiet() {
        let defaults = freshDefaults()
        // Launch on day 1 so the day-2 saves below aren't suppressed by the
        // first-launch-day rule (covered separately below).
        ReviewPromptPolicy(defaults: defaults, clock: { .day1 }, appVersion: "1.0")
            .recordFirstLaunchIfNeeded()
        let policy = ReviewPromptPolicy(defaults: defaults, clock: { .day2 }, appVersion: "1.0")

        #expect(policy.recordSaveAndShouldPrompt() == false) // 1st save
        #expect(policy.recordSaveAndShouldPrompt() == true) // 2nd save
        #expect(policy.recordSaveAndShouldPrompt() == false) // 3rd save, same version
        #expect(policy.recordSaveAndShouldPrompt() == false) // 4th save, same version
    }

    // MARK: - Per-version rule

    @Test func promptsAgainOnceAfterAnAppVersionBump() {
        let defaults = freshDefaults()
        // Launch on day 1 so the day-2 saves below aren't suppressed by the
        // first-launch-day rule (covered separately below).
        ReviewPromptPolicy(defaults: defaults, clock: { .day1 }, appVersion: "1.0")
            .recordFirstLaunchIfNeeded()

        let policyV1 = ReviewPromptPolicy(defaults: defaults, clock: { .day2 }, appVersion: "1.0")
        _ = policyV1.recordSaveAndShouldPrompt() // 1st save, v1.0
        #expect(policyV1.recordSaveAndShouldPrompt() == true) // 2nd save, v1.0 — prompts
        #expect(policyV1.recordSaveAndShouldPrompt() == false) // 3rd save, v1.0 — already asked

        let policyV2 = ReviewPromptPolicy(defaults: defaults, clock: { .day2 }, appVersion: "1.1")
        // Save count is already >= 2, but v1.1 hasn't been asked yet.
        #expect(policyV2.recordSaveAndShouldPrompt() == true)
        #expect(policyV2.recordSaveAndShouldPrompt() == false) // already asked for v1.1
    }

    // MARK: - First-launch-day rule

    @Test func suppressesOnTheDayOfFirstLaunchEvenAtTheSecondSave() {
        let defaults = freshDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, clock: { .day1 }, appVersion: "1.0")
        policy.recordFirstLaunchIfNeeded()

        #expect(policy.recordSaveAndShouldPrompt() == false) // 1st save, launch day
        #expect(policy.recordSaveAndShouldPrompt() == false) // 2nd save, still launch day
    }

    @Test func promptsOnSecondSaveOnceThePromptingDayHasMovedOn() {
        let defaults = freshDefaults()
        // Launch happens on day 1...
        let launchPolicy = ReviewPromptPolicy(defaults: defaults, clock: { .day1 }, appVersion: "1.0")
        launchPolicy.recordFirstLaunchIfNeeded()

        // ...both saves land on day 2, so the launch-day suppression no
        // longer applies and the 2nd save prompts.
        let policy = ReviewPromptPolicy(defaults: defaults, clock: { .day2 }, appVersion: "1.0")
        #expect(policy.recordSaveAndShouldPrompt() == false) // 1st save
        #expect(policy.recordSaveAndShouldPrompt() == true) // 2nd save
    }

    @Test func seedsFirstLaunchDayItselfWhenNeverRecordedExplicitly() {
        // A caller that skips `recordFirstLaunchIfNeeded()` (e.g. a test
        // that only calls the save path) still gets the launch-day
        // suppression: the very first call seeds "today" as launch day.
        let defaults = freshDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, clock: { .day1 }, appVersion: "1.0")

        #expect(policy.recordSaveAndShouldPrompt() == false) // 1st save, seeds launch day
        #expect(policy.recordSaveAndShouldPrompt() == false) // 2nd save, still launch day
    }
}

extension Date {
    fileprivate static let day1 = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01 00:00 UTC
    fileprivate static let day2 = Date(timeIntervalSince1970: 1_893_628_800) // 2030-01-03 00:00 UTC
}
