import Foundation
import SwiftUI
import Testing
import UIKit
@testable import BrewDeskKit
import VenueKit

/// Bamware Picks on the Saved tab (bamware-ai#301): the model's states, the
/// words and dates the rows print, and the badge's contrast.
@Suite @MainActor struct PicksModelTests {
    // MARK: Model states

    @Test func startsIdleAndHidden() {
        let model = PicksModel(service: StubPicks(.success(.empty)))
        #expect(model.phase == .idle)
        #expect(!model.isVisible)
        #expect(model.picks.isEmpty)
    }

    @Test func isHiddenWhileTheFirstRequestIsInFlight() async {
        let gate = Gate()
        let model = PicksModel(service: GatedPicks(gate: gate, response: Self.response(count: 1)))
        let load = Task { await model.load() }
        await gate.waitUntilEntered()

        #expect(model.phase == .loading)
        #expect(!model.isVisible, "no header or spinner before the list is known to be non-empty")

        await gate.open()
        await load.value
        #expect(model.phase == .loaded)
        #expect(model.isVisible)
    }

    @Test func loadedWithOnePick() async {
        let model = PicksModel(service: StubPicks(.success(Self.response(count: 1))))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.isVisible)
        #expect(model.picks.map(\.rank) == [1])
        #expect(model.updatedAt == "2026-11-24")
    }

    @Test func loadedWithTenPicksInRankOrder() async throws {
        let model = PicksModel(service: ScenarioVenueService(scenario: .tenPicks))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.isVisible)
        #expect(model.picks.map(\.rank) == Array(1...10))
        #expect(model.picks.first?.venue.name == "Fixture Pick One Roasters")
    }

    @Test func anEmptyListIsHidden() async {
        let model = PicksModel(service: StubPicks(.success(.empty)))
        await model.load()
        #expect(model.phase == .empty)
        #expect(!model.isVisible)
    }

    @Test(arguments: [404, 500, 503])
    func aFailedRequestIsHiddenWithNoErrorState(status: Int) async {
        // 404 is an engine that predates the route.
        let model = PicksModel(service: StubPicks(.failure(VenueAPIError.http(statusCode: status))))
        await model.load()
        #expect(model.phase == .failed)
        #expect(!model.isVisible)
        #expect(model.picks.isEmpty)
        #expect(model.updatedAt == nil)
    }

    @Test func offlineAndUndecodableAreHiddenToo() async {
        for error in [URLError(.notConnectedToInternet) as any Error, VenueAPIError.decoding] {
            let model = PicksModel(service: StubPicks(.failure(error)))
            await model.load()
            #expect(model.phase == .failed)
            #expect(!model.isVisible)
        }
    }

    @Test func aServiceWithoutPicksMakesNoSectionAndNoRequest() async {
        let model = PicksModel(service: nil)
        await model.load()
        #expect(model.phase == .empty)
        #expect(!model.isVisible)
    }

    @Test func aFailedRefreshKeepsTheListAlreadyOnScreen() async {
        let service = SequencePicks([
            .success(Self.response(count: 3)),
            .failure(URLError(.timedOut)),
        ])
        let model = PicksModel(service: service)
        await model.load()
        #expect(model.picks.count == 3)

        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.isVisible)
        #expect(model.picks.count == 3)
    }

    @Test func aRefreshThatComesBackEmptyHidesTheSection() async {
        let service = SequencePicks([.success(Self.response(count: 2)), .success(.empty)])
        let model = PicksModel(service: service)
        await model.load()
        #expect(model.isVisible)
        await model.load()
        #expect(model.phase == .empty)
        #expect(!model.isVisible)
        #expect(model.picks.isEmpty)
    }

    @Test func recoversAfterAFailure() async {
        let service = SequencePicks([.failure(URLError(.timedOut)), .success(Self.response(count: 1))])
        let model = PicksModel(service: service)
        await model.load()
        #expect(!model.isVisible)
        await model.load()
        #expect(model.isVisible)
    }

    // MARK: Wording and dates

    private static let english = Locale(identifier: "en_US")
    private static let november2026 = PicksWording.parse("2026-11-25")!

    @Test func badgeWording() {
        #expect(PicksWording.badge(rank: 1, locale: Self.english) == "Pick #1")
        #expect(PicksWording.badge(rank: 10, locale: Self.english) == "Pick #10")
        #expect(PicksWording.badgeAccessibilityLabel(rank: 3, locale: Self.english) == "Bamware Pick number 3")
    }

    @Test func visitedIsMonthAndDayWithinTheYear() {
        #expect(PicksWording.visited("2026-10-27", now: Self.november2026, locale: Self.english) == "Visited Oct 27")
        #expect(PicksWording.visited("2026-01-05", now: Self.november2026, locale: Self.english) == "Visited Jan 5")
    }

    @Test func anEarlierYearIsNamed() {
        #expect(PicksWording.visited("2025-12-14", now: Self.november2026, locale: Self.english) == "Visited Dec 14, 2025")
        #expect(PicksWording.updated("2025-12-14", now: Self.november2026, locale: Self.english) == "Updated Dec 14, 2025")
    }

    @Test func updatedWording() {
        #expect(PicksWording.updated("2026-11-24", now: Self.november2026, locale: Self.english) == "Updated Nov 24")
        #expect(PicksWording.updated(nil, now: Self.november2026, locale: Self.english) == nil)
    }

    @Test func theDayNeverShiftsWithTheReadersTimeZone() {
        // A calendar day is printed as written, wherever the phone is.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for identifier in ["Pacific/Honolulu", "America/New_York", "Asia/Tokyo", "Pacific/Kiritimati"] {
            NSTimeZone.default = TimeZone(identifier: identifier)!
            #expect(
                PicksWording.visited("2026-10-27", now: Self.november2026, locale: Self.english) == "Visited Oct 27",
                "\(identifier)"
            )
        }
    }

    @Test func spanishPutsTheDayFirst() throws {
        let day = try #require(PicksWording.day("2026-10-27", now: Self.november2026, locale: Locale(identifier: "es_ES")))
        #expect(day.hasPrefix("27"))
        #expect(day.lowercased().contains("oct"))
    }

    @Test(arguments: ["", "yesterday", "2026-13-01", "2026-02-30", "27/10/2026", "2026-10-27T10:00:00Z", "26-10-27", "2026-1-5"])
    func aBrokenDateDropsTheLineInsteadOfPrintingIt(raw: String) {
        #expect(PicksWording.visited(raw, now: Self.november2026, locale: Self.english) == nil)
        #expect(PicksWording.updated(raw, now: Self.november2026, locale: Self.english) == nil)
    }

    @Test func theLineIsQuotedAndTrimmed() {
        #expect(PicksWording.quoted("  Two floors.  \n") == "\u{201C}Two floors.\u{201D}")
    }

    // MARK: Badge contrast (light and dark)

    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linearize(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// WCAG 2.1 contrast ratio between two colours as resolved for `style`.
    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let first = relativeLuminance(UIColor(a).resolvedColor(with: traits))
        let second = relativeLuminance(UIColor(b).resolvedColor(with: traits))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func rgb(_ color: Color, _ style: UIUserInterfaceStyle) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// "Pick #1" is caption-size text, so it needs the full 4.5:1 against
    /// the badge's own opaque fill.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func pickBadgeTextMeetsFourPointFiveToOne(style: UIUserInterfaceStyle) {
        let ratio = contrast(PickBadge.foreground, PickBadge.background, style)
        print("pick badge contrast (\(style == .dark ? "dark" : "light")): \(ratio):1")
        #expect(ratio >= 4.5, "pick badge text vs. fill: \(ratio):1")
    }

    /// The section's own text tokens on the Saved tab's page background.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func picksSectionTextMeetsFourPointFiveToOneOnThePage(style: UIUserInterfaceStyle) {
        for (name, token) in [
            ("name and line", BrewDeskPalette.clusterSurfaceText),
            ("neighbourhood, subline, dates", BrewDeskPalette.secondaryText),
            ("rank numeral and bookmark", BrewDeskPalette.primaryText),
        ] {
            let ratio = contrast(token, BrewDeskPalette.page, style)
            #expect(ratio >= 4.5, "\(name) vs. page: \(ratio):1")
        }
    }

    /// The badge is a neutral: it must not carry a red or a green that a
    /// red-green colourblind reader would have to tell apart, and it must
    /// not look like a Work Fit tier.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func pickBadgeIsNeutralNeitherRedNorGreen(style: UIUserInterfaceStyle) {
        for token in [PickBadge.foreground, PickBadge.background, PickBadge.outline] {
            let c = rgb(token, style)
            // Red and green channels stay close together: no red-vs-green signal.
            #expect(abs(c.r - c.g) < 0.08, "red \(c.r) vs green \(c.g)")
        }
        for tier in [ScoreTier.great, .good, .mixed, .weak] {
            #expect(UIColor(PickBadge.background) != UIColor(tier.color))
        }
    }

    // MARK: Helpers

    static func response(count: Int) -> PicksResponse {
        PicksResponse(
            updatedAt: "2026-11-24",
            curator: "Bamware",
            picks: (1...count).map { rank in
                Pick(
                    rank: rank,
                    blurb: "Line \(rank).",
                    visitedAt: "2026-10-27",
                    venue: PickVenue(id: "v\(rank)", name: "Cafe \(rank)", neighborhood: "NoHo", scoreDisplay: .rated(80))
                )
            }
        )
    }
}

private struct StubPicks: PicksServing {
    let result: Result<PicksResponse, any Error>
    init(_ result: Result<PicksResponse, any Error>) { self.result = result }
    func fetchPicks() async throws -> PicksResponse { try result.get() }
}

/// Answers each call with the next result in the list.
private final class SequencePicks: PicksServing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<PicksResponse, any Error>]
    init(_ results: [Result<PicksResponse, any Error>]) { self.results = results }
    func fetchPicks() async throws -> PicksResponse {
        let next = lock.withLock { results.removeFirst() }
        return try next.get()
    }
}

/// Lets a test hold a request open and look at the model mid-flight.
private actor Gate {
    private var entered = false
    private var opened = false
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        enterWaiters.forEach { $0.resume() }
        enterWaiters = []
        if !opened {
            await withCheckedContinuation { openWaiters.append($0) }
        }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { enterWaiters.append($0) } }
    }

    func open() {
        opened = true
        openWaiters.forEach { $0.resume() }
        openWaiters = []
    }
}

private struct GatedPicks: PicksServing {
    let gate: Gate
    let response: PicksResponse
    func fetchPicks() async throws -> PicksResponse {
        await gate.enter()
        return response
    }
}
