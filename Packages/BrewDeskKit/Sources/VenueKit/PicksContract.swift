import Foundation

// Bamware Picks (bamware-ai#301): a short, hand-curated, ranked list of the
// founder's favourite work cafés, each with one first-person line and the
// date of the last visit. Engine side: bamware-venue-engine `docs/picks.md`.
//
// Two additive pieces of contract, both optional for the client:
//   - `GET /v1/picks` → `PicksResponse`
//   - `pick` on a venue object → `Venue.pick`
//
// **A pick is taste, not data.** Nothing here feeds Work Fit, filtering or
// ordering. Picks are never sold.
//
// Everything decodes leniently. An engine that predates the feature answers
// 404 for the route and sends no `pick` key; the app then shows no Picks
// section and no badge, and nothing else changes.

/// The label a venue carries when it is on the list.
public struct VenuePick: Codable, Hashable, Sendable {
    /// 1 is the favourite.
    public let rank: Int
    /// One first-person line, 140 characters at most on the wire.
    public let blurb: String
    /// The curator's last visit, `YYYY-MM-DD`.
    public let visitedAt: String

    public init(rank: Int, blurb: String, visitedAt: String) {
        self.rank = rank
        self.blurb = blurb
        self.visitedAt = visitedAt
    }
}

/// The venue inside a `/v1/picks` row: the engine's compact map shape plus
/// `neighborhood`, `venueType` and `scoreCoverage`. Deliberately NOT a
/// `Venue` — the compact shape carries no claims, and inventing them to
/// build one would put made-up Wi-Fi and outlet values on screen. Opening a
/// pick fetches the real venue by id.
public struct PickVenue: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let neighborhood: String?
    public let venueType: String?
    public let workScore: Int?
    public let scoreDisplay: ScoreDisplay
    public let scoreCoverage: ScoreCoverage?
    /// `"researched" | "partial" | "none"`: only consulted when the engine
    /// sent no `scoreDisplay` at all (see `displayScore`).
    public let evidence: String?

    public init(
        id: String,
        name: String,
        neighborhood: String? = nil,
        venueType: String? = nil,
        workScore: Int? = nil,
        scoreDisplay: ScoreDisplay = .notProvided,
        scoreCoverage: ScoreCoverage? = nil,
        evidence: String? = nil
    ) {
        self.id = id
        self.name = name
        self.neighborhood = neighborhood
        self.venueType = venueType
        self.workScore = workScore
        self.scoreDisplay = scoreDisplay
        self.scoreCoverage = scoreCoverage
        self.evidence = evidence
    }

    /// The number to show, or `nil` for "Not rated yet". Same three-way
    /// contract as `Venue.displayScore`: an explicit server `null` is never
    /// replaced by `workScore`. With no server opinion at all, the number is
    /// shown only when the engine says the venue has real evidence.
    public var displayScore: Int? {
        switch scoreDisplay {
        case .rated(let score): score
        case .notRated: nil
        case .notProvided:
            if let evidence, evidence != "none" { workScore } else { nil }
        }
    }

    public var typeBadge: VenueTypeBadge { VenueTypeBadge(serverValue: venueType) }
}

extension PickVenue: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, neighborhood, venueType, workScore, scoreDisplay, scoreCoverage, evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The two fields a row cannot exist without.
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Everything else is optional and tolerant of a wrong type.
        neighborhood = (try? container.decodeIfPresent(String.self, forKey: .neighborhood)) ?? nil
        venueType = (try? container.decodeIfPresent(String.self, forKey: .venueType)) ?? nil
        workScore = (try? container.decodeIfPresent(Int.self, forKey: .workScore)) ?? nil
        scoreCoverage = (try? container.decodeIfPresent(ScoreCoverage.self, forKey: .scoreCoverage)) ?? nil
        evidence = (try? container.decodeIfPresent(String.self, forKey: .evidence)) ?? nil
        if container.contains(.scoreDisplay) {
            if let score = try? container.decode(Int.self, forKey: .scoreDisplay) {
                scoreDisplay = .rated(score)
            } else {
                // `null`, or anything that is not a whole number: unrated.
                scoreDisplay = .notRated
            }
        } else {
            scoreDisplay = .notProvided
        }
    }
}

/// One row of the list.
public struct Pick: Hashable, Sendable, Identifiable, Decodable {
    public let rank: Int
    public let blurb: String
    public let visitedAt: String
    public let venue: PickVenue

    public var id: String { venue.id }

    public init(rank: Int, blurb: String, visitedAt: String, venue: PickVenue) {
        self.rank = rank
        self.blurb = blurb
        self.visitedAt = visitedAt
        self.venue = venue
    }

    /// The same label the venue itself carries in list and detail responses.
    public var label: VenuePick { VenuePick(rank: rank, blurb: blurb, visitedAt: visitedAt) }
}

/// `GET /v1/picks`.
public struct PicksResponse: Hashable, Sendable {
    /// The day the list last changed, `YYYY-MM-DD`. Absent when the engine
    /// has no list.
    public let updatedAt: String?
    public let curator: String?
    /// Sorted by rank, 1 first.
    public let picks: [Pick]

    public init(updatedAt: String? = nil, curator: String? = nil, picks: [Pick]) {
        self.updatedAt = updatedAt
        self.curator = curator
        self.picks = picks.sorted { $0.rank < $1.rank }
    }

    public static let empty = PicksResponse(picks: [])
}

extension PicksResponse: Decodable {
    private enum CodingKeys: String, CodingKey { case updatedAt, curator, picks }

    /// A row that fails to decode is skipped, never fatal: one bad entry
    /// must not hide the other nine. Rows with a blank blurb or a rank below
    /// 1 are skipped too, as is a second row for the same venue.
    private struct Lossy: Decodable {
        let pick: Pick?
        init(from decoder: Decoder) throws { pick = try? Pick(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = ((try? container.decodeIfPresent([Lossy].self, forKey: .picks)) ?? nil) ?? []
        var seen = Set<String>()
        let valid = rows.compactMap(\.pick).filter { pick in
            pick.rank >= 1
                && !pick.blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert(pick.venue.id).inserted
        }
        self.init(
            updatedAt: (try? container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil,
            curator: (try? container.decodeIfPresent(String.self, forKey: .curator)) ?? nil,
            picks: valid
        )
    }
}

/// The capability a venue service may offer. `VenueAPI` is the live one and
/// `ScenarioVenueService` the fixture one; a service without it simply has
/// no Picks section.
public protocol PicksServing: Sendable {
    func fetchPicks() async throws -> PicksResponse
}

extension Venue {
    /// A copy of this venue carrying `pick` (or none). Every other field is
    /// untouched; fixtures and tests use it.
    public func settingPick(_ pick: VenuePick?) -> Venue {
        Venue(
            id: id, name: name, lat: lat, lng: lng, address: address,
            neighborhood: neighborhood, borough: borough, hoursRaw: hoursRaw,
            vertical: vertical, attributes: attributes, vibeTags: vibeTags,
            workScore: workScore, lastVerified: lastVerified, distanceM: distanceM,
            venueType: venueType, website: website, phone: phone, email: email,
            tier: tier, news: news, scoreDisplay: scoreDisplay,
            scoreCoverage: scoreCoverage, scoreConfidence: scoreConfidence,
            pick: pick
        )
    }
}
