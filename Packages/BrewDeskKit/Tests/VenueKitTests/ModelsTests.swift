import Foundation
import Testing
import VenueKit

@Suite struct ModelsTests {
    private func loadFixture() throws -> VenueListResponse {
        let url = Bundle.module.url(forResource: "venues", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VenueListResponse.self, from: data)
    }

    @Test func decodesVenueListFixture() throws {
        let response = try loadFixture()
        #expect(response.count == 2)
        #expect(response.venues.count == 2)

        let devocion = response.venues[0]
        #expect(devocion.name == "Devoción")
        #expect(devocion.distanceM == 640) // snake_case distance_m mapped
        #expect(devocion.attributes.wifi.mbpsRange == [50, 120])
        #expect(devocion.attributes.wifi.isEstimate == false)

        let random = response.venues[1]
        #expect(random.distanceM == nil)
        #expect(random.attributes.wifi.isEstimate)
        #expect(random.attributes.wifi.confidencePercent == 30)
    }

    @Test func scoreTiersBandCorrectly() {
        #expect(ScoreTier(score: 90) == .great)
        #expect(ScoreTier(score: 75) == .great)
        #expect(ScoreTier(score: 60) == .good)
        #expect(ScoreTier(score: 50) == .mixed)
        #expect(ScoreTier(score: 20) == .weak)
    }

    @Test func sourceLabelsAreHuman() {
        let claim = Claim(
            value: "fast", detail: nil, mbpsRange: nil, timeWindow: nil,
            source: "speed_test", confidence: 0.9, observedAt: "2026-08-03"
        )
        #expect(claim.sourceLabel == "measured in-app")
        #expect(claim.isMeasured)
    }
}
