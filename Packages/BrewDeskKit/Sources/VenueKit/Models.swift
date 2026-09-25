import Foundation

// MARK: - Models (mirror the bamware-venue-engine API JSON 1:1)
// All keys camelCase except `distance_m` (handled via CodingKeys).

public struct Claim: Codable, Hashable, Sendable {
    public let value: String
    public let detail: String?
    public let mbpsRange: [Double]?
    public let timeWindow: String?
    public let source: String      // curated | osm | estimate | speed_test | user_report | field_visit
    public let confidence: Double  // 0...1
    public let observedAt: String

    public init(
        value: String,
        detail: String? = nil,
        mbpsRange: [Double]? = nil,
        timeWindow: String? = nil,
        source: String,
        confidence: Double,
        observedAt: String
    ) {
        self.value = value
        self.detail = detail
        self.mbpsRange = mbpsRange
        self.timeWindow = timeWindow
        self.source = source
        self.confidence = confidence
        self.observedAt = observedAt
    }

    public var isEstimate: Bool { source == "estimate" }
    public var isMeasured: Bool { source == "speed_test" }
    public var confidencePercent: Int {
        Int((min(max(confidence, 0), 1) * 100).rounded())
    }

    public var sourceLabel: String {
        switch source {
        case "curated": "curated"
        case "osm": "OpenStreetMap"
        case "estimate": "unverified estimate"
        case "speed_test": "measured in-app"
        case "user_report": "user report"
        case "field_visit": "field-verified"
        // bd#180: agent claims are AI web/press research, not a human
        // verification — "agent" must never leak to the UI as raw text.
        case "agent": "press research"
        default: source
        }
    }
}

/// ve#103: a single allowlisted press article tied to a café — first-class
/// press signal, never buried in a `Claim.detail` pipeline string.
///
/// **News ≠ Work Fit.** A press mention never raises `workScore` by itself
/// (same honesty rule as `buzz`). Populated only from committed
/// market-research / cultural-moment / agent-evidence URLs on the engine
/// side; the client renders `title`/`sourceDomain` verbatim (allowlisted,
/// curated text — unlike `Claim.detail`, which carries raw pipeline
/// prefixes and must never render verbatim).
public struct NewsLink: Codable, Hashable, Sendable {
    public let url: String
    public let title: String?
    public let sourceDomain: String
    /// ISO date the article was published/observed (not an instant).
    public let observedAt: String
    /// Always `"news"` on the wire (ve#103); decoded as a plain string
    /// rather than a closed enum so an engine-side tag addition stays
    /// additive instead of a decode failure.
    public let tag: String

    public init(
        url: String,
        title: String? = nil,
        sourceDomain: String,
        observedAt: String,
        tag: String = "news"
    ) {
        self.url = url
        self.title = title
        self.sourceDomain = sourceDomain
        self.observedAt = observedAt
        self.tag = tag
    }

    /// `title`, trimmed, with blank-or-absent treated the same (mirrors
    /// `VenuePhoto.communityByline`) — a title-less row falls back to
    /// `sourceDomain` instead of printing an empty line.
    public var displayTitle: String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

public struct VenueAttributes: Codable, Hashable, Sendable {
    public let wifi: Claim
    public let outlets: Claim
    public let laptopPolicy: Claim
    public let noise: Claim
    // v2 — optional-first: absent on pre-v2 payloads, UI renders nothing.
    public let seating: Claim?
    public let outdoorSeating: Claim?

    public init(
        wifi: Claim,
        outlets: Claim,
        laptopPolicy: Claim,
        noise: Claim,
        seating: Claim? = nil,
        outdoorSeating: Claim? = nil
    ) {
        self.wifi = wifi
        self.outlets = outlets
        self.laptopPolicy = laptopPolicy
        self.noise = noise
        self.seating = seating
        self.outdoorSeating = outdoorSeating
    }
}

public struct Venue: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let lat: Double
    public let lng: Double
    public let address: String?
    public let neighborhood: String
    public let borough: String
    public let hoursRaw: String?
    public let vertical: String
    public let attributes: VenueAttributes
    public let vibeTags: [String]
    public let workScore: Int
    public let lastVerified: String?
    public let distanceM: Int?
    /// v2 — "cafe" | "park" | "library" | "mall" | "other"; optional-first.
    public let venueType: String?
    /// Business info (brewdesk#50, email brewdesk#56) — optional-first: detail
    /// payloads may carry them, list payloads typically don't; absent fields
    /// render nothing.
    public let website: String?
    public let phone: String?
    public let email: String?
    /// "researched" | "osm-baseline" (ve#46, bd#108) — the depth behind this
    /// venue's own claims, as opposed to `coverage` on the *response*, which
    /// describes the whole viewport. Optional-first: absent on pre-ve#46
    /// payloads, and absent decodes as researched (`isOSMBaseline == false`)
    /// — backward compatible until the engine ships the field.
    public let tier: String?
    /// Allowlisted press links (ve#103, bd#180) — additive, optional.
    /// **News ≠ Work Fit**: never an input to `workScore`; render nothing
    /// when absent or empty (pre-ve#103 payloads, and most venues, carry no
    /// press hits — that is not a claim about the café).
    public let news: [NewsLink]?
    /// The server's own honest-score signal (brewdesk#213, venue-engine
    /// `76e343a`) — see `ScoreDisplay`'s own doc comment for the three-way
    /// contract. `.notProvided` (key absent) is the default so every
    /// existing call site (fixtures, tests, older-server payloads) keeps
    /// today's `isObserved`-driven behavior without passing this explicitly.
    public let scoreDisplay: ScoreDisplay
    /// What `workScore`/`scoreDisplay` rests on (Work Fit v2, ve#144/#148,
    /// brewdesk#240) — "based on 3 of 5" is exactly this. Additive, NYC
    /// only; absent everywhere else (non-NYC metros, older servers).
    public let scoreCoverage: ScoreCoverage?
    /// How much to trust `scoreDisplay` (Work Fit v2) — served for unrated
    /// pins too, so the UI can explain *why* there's no number (brewdesk#240
    /// item 5: "low" confidence keeps the "Been here? Rate it." nudge).
    /// Additive, NYC only.
    public let scoreConfidence: ScoreConfidence?

    public init(
        id: String,
        name: String,
        lat: Double,
        lng: Double,
        address: String?,
        neighborhood: String,
        borough: String,
        hoursRaw: String?,
        vertical: String,
        attributes: VenueAttributes,
        vibeTags: [String],
        workScore: Int,
        lastVerified: String?,
        distanceM: Int?,
        venueType: String? = nil,
        website: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        tier: String? = nil,
        news: [NewsLink]? = nil,
        scoreDisplay: ScoreDisplay = .notProvided,
        scoreCoverage: ScoreCoverage? = nil,
        scoreConfidence: ScoreConfidence? = nil
    ) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.address = address
        self.neighborhood = neighborhood
        self.borough = borough
        self.hoursRaw = hoursRaw
        self.vertical = vertical
        self.attributes = attributes
        self.vibeTags = vibeTags
        self.workScore = workScore
        self.lastVerified = lastVerified
        self.distanceM = distanceM
        self.venueType = venueType
        self.website = website
        self.phone = phone
        self.email = email
        self.tier = tier
        self.news = news
        self.scoreDisplay = scoreDisplay
        self.scoreCoverage = scoreCoverage
        self.scoreConfidence = scoreConfidence
    }

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lng, address, neighborhood, borough, hoursRaw,
             vertical, attributes, vibeTags, workScore, lastVerified, venueType,
             website, phone, email, tier, news, scoreDisplay, scoreCoverage, scoreConfidence
        case distanceM = "distance_m"
    }

    /// Manual `Decodable` (brewdesk#213): the ONLY reason this struct can't
    /// use synthesized `Codable` any more is `scoreDisplay` — telling "key
    /// absent" from "key present with a JSON `null`" requires
    /// `container.contains(_:)` at THIS level, before ever calling
    /// `decode`/`decodeIfPresent` on it (`decodeIfPresent`'s own default
    /// implementation collapses both cases to `nil`, which is exactly the
    /// ambiguity that let the placeholder `workScore` render as if it were a
    /// real rating). Every other field decodes exactly as the previous
    /// synthesized implementation did.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        neighborhood = try container.decode(String.self, forKey: .neighborhood)
        borough = try container.decode(String.self, forKey: .borough)
        hoursRaw = try container.decodeIfPresent(String.self, forKey: .hoursRaw)
        vertical = try container.decode(String.self, forKey: .vertical)
        attributes = try container.decode(VenueAttributes.self, forKey: .attributes)
        vibeTags = try container.decode([String].self, forKey: .vibeTags)
        workScore = try container.decode(Int.self, forKey: .workScore)
        lastVerified = try container.decodeIfPresent(String.self, forKey: .lastVerified)
        distanceM = try container.decodeIfPresent(Int.self, forKey: .distanceM)
        venueType = try container.decodeIfPresent(String.self, forKey: .venueType)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        news = try container.decodeIfPresent([NewsLink].self, forKey: .news)
        scoreCoverage = try container.decodeIfPresent(ScoreCoverage.self, forKey: .scoreCoverage)
        scoreConfidence = try container.decodeIfPresent(ScoreConfidence.self, forKey: .scoreConfidence)

        if container.contains(.scoreDisplay) {
            if try container.decodeNil(forKey: .scoreDisplay) {
                scoreDisplay = .notRated
            } else {
                scoreDisplay = .rated(try container.decode(Int.self, forKey: .scoreDisplay))
            }
        } else {
            scoreDisplay = .notProvided
        }
    }

    /// Manual `Encodable` counterpart to the manual decoder above — kept in
    /// lockstep so a re-encode (cache writes, snapshot seeding, UI-test
    /// fixture serialization) round-trips all three `scoreDisplay` states:
    /// `.notProvided` omits the key entirely (never fabricates a `null` the
    /// original payload never had), `.notRated` writes a real JSON `null`,
    /// `.rated` writes the number.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encode(neighborhood, forKey: .neighborhood)
        try container.encode(borough, forKey: .borough)
        try container.encodeIfPresent(hoursRaw, forKey: .hoursRaw)
        try container.encode(vertical, forKey: .vertical)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(vibeTags, forKey: .vibeTags)
        try container.encode(workScore, forKey: .workScore)
        try container.encodeIfPresent(lastVerified, forKey: .lastVerified)
        try container.encodeIfPresent(distanceM, forKey: .distanceM)
        try container.encodeIfPresent(venueType, forKey: .venueType)
        try container.encodeIfPresent(website, forKey: .website)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(tier, forKey: .tier)
        try container.encodeIfPresent(news, forKey: .news)
        try container.encodeIfPresent(scoreCoverage, forKey: .scoreCoverage)
        try container.encodeIfPresent(scoreConfidence, forKey: .scoreConfidence)

        switch scoreDisplay {
        case .notProvided:
            break
        case .notRated:
            try container.encodeNil(forKey: .scoreDisplay)
        case .rated(let score):
            try container.encode(score, forKey: .scoreDisplay)
        }
    }

    public var scoreTier: ScoreTier { ScoreTier(score: workScore) }

    /// The badge/filter-facing venue type (brewdesk#240) — `VenueTypeBadge`'s
    /// own doc comment has the full contract; in short, never defaults an
    /// absent/unrecognized `venueType` to `.cafe`.
    public var typeBadge: VenueTypeBadge { VenueTypeBadge(serverValue: venueType) }

    /// True when this venue's own claims come from the OSM tier-0 baseline
    /// rather than curated/researched sources (ve#46). Drives the
    /// `ProvenanceStamp` "OSM baseline · updated <date>" wording (bd#108).
    public var isOSMBaseline: Bool { tier == "osm-baseline" }

    /// True when at least one scored claim (Wi-Fi, outlets, laptop policy,
    /// noise, seating) is not an `estimate` and carries confidence ≥ 0.4.
    /// Mirrors bamware-venue-engine ve#64 ("Stop 0.3-confidence estimates
    /// from driving Work Fit"): the engine now treats `estimate` claims and
    /// anything under 0.4 confidence as not counting toward the score, so
    /// every venue with no real evidence lands on the same flat neutral
    /// `workScore` — a hollow Places pin with no claims at all lands at 40,
    /// not the 52 once documented here (bd#180); OSM-baseline metros with
    /// tag-derived claims still run 50–55. `false` here means `workScore`
    /// is that neutral fallback, not a measurement — the UI must show
    /// "Not rated yet" instead of the number (bd#159).
    ///
    /// This is a client-side approximation of the engine's own rule. The
    /// engine now ships an explicit field for this (`scoreDisplay`,
    /// brewdesk#213) — prefer `displayScore`/`isRated` below in UI code;
    /// this stays the fallback for `.notProvided` (older payloads).
    public var isObserved: Bool {
        let scoredClaims: [Claim?] = [
            attributes.laptopPolicy,
            attributes.seating,
            attributes.wifi,
            attributes.outlets,
            attributes.noise,
        ]
        return scoredClaims.contains { claim in
            guard let claim else { return false }
            // A claim whose value is literally "unknown" is the absence of an
            // observation, whatever its source or confidence says.
            return !claim.isEstimate && claim.confidence >= 0.4 && claim.value != "unknown"
        }
    }

    /// The score to actually show the user (brewdesk#213), honoring the
    /// server's explicit `scoreDisplay` over the client-side `isObserved`
    /// heuristic whenever the server has an opinion at all:
    /// - `.rated(score)`: the server evidenced this café — show `score`
    ///   (equal to `workScore` on the wire, but this is the field that
    ///   means it, not a client guess).
    /// - `.notRated`: the server explicitly says "not rated yet" — `nil`,
    ///   ALWAYS, even if `isObserved`'s own heuristic would have said
    ///   otherwise. Never falls back to `workScore`— that's the exact
    ///   placeholder-number bug this ticket fixes.
    /// - `.notProvided`: older server / metro outside the rollout — no
    ///   opinion at all, so this preserves the pre-#213 behavior verbatim.
    public var displayScore: Int? {
        switch scoreDisplay {
        case .rated(let score): score
        case .notRated: nil
        case .notProvided: isObserved ? workScore : nil
        }
    }

    /// True when this venue has an evidenced score worth showing — the
    /// single source of truth `displayScore` and every score-driven surface
    /// (map marker split, ordering, badges) share, so all of them agree
    /// with each other even where `scoreDisplay` overrides `isObserved`.
    public var isRated: Bool {
        switch scoreDisplay {
        case .rated: true
        case .notRated: false
        case .notProvided: isObserved
        }
    }
}

/// The server's honest-score signal (brewdesk#213, venue-engine `76e343a`):
/// additive on every venue in both the full and `compact=1` shapes.
/// - A JSON number: the café is rated, equal to `workScore`.
/// - A JSON `null`: the café is genuinely unrated — "Not rated yet", never
///   `workScore`'s flat neutral placeholder.
/// - The key absent entirely: an older server, or a metro outside the
///   rollout — no opinion; the client falls back to its own `isObserved`
///   heuristic, exactly like before this field existed.
///
/// `Venue`'s manual `Codable` conformance is what makes "absent" and "null"
/// distinguishable at all — `decodeIfPresent` alone cannot tell them apart.
public enum ScoreDisplay: Hashable, Sendable {
    case notProvided
    case notRated
    case rated(Int)
}

/// Work Fit v2's "what the number rests on" (ve#144/#148, brewdesk#240):
/// `known` of `of` (currently always 5) core attributes carry a voting
/// claim, `weight` is the renormalized weight those claims cover (0...1),
/// and `attributes` names them (engine vocabulary, e.g. `"wifi"`,
/// `"outlets"`). Drives "Based on 3 of 5 details" on both the detail badge
/// and, room permitting, the shelf/list card caption. Additive, NYC only —
/// absent everywhere else.
public struct ScoreCoverage: Codable, Hashable, Sendable {
    public let known: Int
    public let of: Int
    public let weight: Double
    public let attributes: [String]

    public init(known: Int, of: Int, weight: Double, attributes: [String]) {
        self.known = known
        self.of = of
        self.weight = weight
        self.attributes = attributes
    }
}

/// How much to trust `scoreDisplay` (ve#144, brewdesk#240) — served for
/// unrated pins too, so the client can explain *why* a pin reads "Not rated
/// yet" instead of just saying so. `"low"` keeps the shelf/detail nudge at
/// "Been here? Rate it." rather than implying the venue was thoroughly
/// checked and simply came up empty.
public enum ScoreConfidence: String, Codable, Hashable, Sendable {
    case high, medium, low
}

/// The badge/filter-facing venue type (brewdesk#240) — a closed, client-only
/// set distinct from the raw wire string `Venue.venueType` (which stays an
/// optional `String` in `Venue` so a future server value, or a legacy/older
/// payload missing the field entirely, never fails to decode).
///
/// **Never defaults an absent or unrecognized wire value to `.cafe`.** The
/// TestFlight build 28 bug (ve#147/brewdesk#240) was exactly that default —
/// `venue.venueType ?? "cafe"` — leaking a WeWork (`"other"` on the wire)
/// into "cafe" everywhere that expression was written. `.unknown` is its
/// own honest case, not a synonym for café.
public enum VenueTypeBadge: String, CaseIterable, Codable, Hashable, Sendable {
    case cafe
    case library
    case park
    case coworking
    case unknown

    /// `nil`/absent, `"cafe"`, `"library"`, `"park"`, `"other"` (the
    /// server's own wire spelling for a coworking space like WeWork,
    /// ve#147), or anything else the client doesn't recognize → `.unknown`.
    public init(serverValue: String?) {
        switch serverValue {
        case "cafe": self = .cafe
        case "library": self = .library
        case "park": self = .park
        case "other": self = .coworking
        default: self = .unknown
        }
    }

    /// The four chips `WorkFitFilterMenu`'s "Place type" row offers.
    /// `.unknown` is deliberately not one of them — there's no server-
    /// confirmed data to filter on (see `VenueFilter.classify`'s own doc
    /// comment for how an `.unknown`-typed venue behaves under a narrowed
    /// selection).
    public static let filterableCases: [VenueTypeBadge] = [.cafe, .library, .park, .coworking]

    public var displayName: String {
        switch self {
        case .cafe: String(localized: "Café")
        case .library: String(localized: "Library")
        case .park: String(localized: "Park")
        case .coworking: String(localized: "Coworking")
        case .unknown: String(localized: "Place")
        }
    }

    public var symbolName: String {
        switch self {
        case .cafe: "cup.and.saucer"
        case .library: "books.vertical"
        case .park: "tree"
        case .coworking: "building.2"
        case .unknown: "mappin"
        }
    }

    /// Cafés are BrewDesk's default, assumed type — every card and pin
    /// already reads as "a café" without a badge, so adding one would be
    /// pure noise (brewdesk#240: "Cafés get no badge"). `.unknown` also
    /// shows nothing: badging it would assert a type this app has no real
    /// evidence for, which is exactly the honesty rule this feature exists
    /// to enforce.
    public var showsBadge: Bool {
        self != .cafe && self != .unknown
    }
}

/// A response's coverage for the queried viewport (ve#46, bd#108):
/// - `researched`: NYC-depth data — curated/agent claims, human-checked.
/// - `baseline`: OSM tier-0 only — real venues, unverified attributes.
/// - `none`: no data at all for this viewport; the intentional empty state.
///
/// Missing or unrecognized on the wire decodes as `.researched` — backward
/// compatible with an engine that hasn't shipped `coverage` yet.
public enum CoverageLevel: String, Codable, Sendable {
    case researched, baseline, none

    public static func from(_ raw: String?) -> CoverageLevel {
        raw.flatMap(CoverageLevel.init(rawValue:)) ?? .researched
    }
}

/// Coarse quality bands for badges / map pins.
public enum ScoreTier: String, Sendable {
    case great, good, mixed, weak

    public init(score: Int) {
        switch score {
        case 75...: self = .great
        case 60..<75: self = .good
        case 45..<60: self = .mixed
        default: self = .weak
        }
    }
}

public struct VenueListResponse: Codable, Sendable {
    public let count: Int
    public let venues: [Venue]
    /// Coverage for the whole queried viewport (ve#46, bd#108). The engine
    /// sends it as `meta.coverage`; a top-level `coverage` is also accepted
    /// (fixtures). Absent on pre-ve#46 payloads → `.researched` via
    /// `CoverageLevel.from(_:)`.
    public let coverage: String?
    public let meta: Meta?

    public struct Meta: Codable, Sendable {
        public let coverage: String?
    }

    /// `meta.coverage` wins over the legacy top-level field.
    public var resolvedCoverage: String? { meta?.coverage ?? coverage }
}

/// One `fetchVenuesResult` answer: the venues plus what coverage the engine
/// reported for the queried viewport (bd#108). `VenueListing.fetchVenues`
/// stays the venues-only convenience every existing conformer/mock already
/// implements; `fetchVenuesResult` defaults to `.researched` for any of them.
public struct VenueLoadResult: Sendable {
    public let venues: [Venue]
    public let coverage: CoverageLevel

    public init(venues: [Venue], coverage: CoverageLevel = .researched) {
        self.venues = venues
        self.coverage = coverage
    }
}

public struct VenueDetailResponse: Codable, Sendable {
    public let venue: Venue
    public let observations: [ObservationRequest]
}

public struct ObservationRequest: Codable, Sendable {
    public let venueId: String
    public let kind: String            // "speed_test" | "report"
    public var mbpsDown: Double? = nil
    public var note: String? = nil

    public init(venueId: String, kind: String, mbpsDown: Double? = nil, note: String? = nil) {
        self.venueId = venueId
        self.kind = kind
        self.mbpsDown = mbpsDown
        self.note = note
    }
}

public struct ObservationResponse: Codable, Sendable {
    public let venue: Venue
}

/// One display-only venue photo. Production photo bytes load verbatim from
/// Google (`photoUri`, host `lh3.googleusercontent.com`) — there is no
/// same-origin Places proxy (brewdesk#156). `url` is absolute by the time it
/// leaves VenueAPI; attribution must be shown when present (Google Places
/// licensing).
public struct VenuePhoto: Codable, Hashable, Identifiable, Sendable {
    public let url: String
    public let attribution: String?
    public let attributionUri: String?
    public let widthPx: Int?
    public let heightPx: Int?
    /// Contributor display name for an *approved community photo* (brewdesk#49).
    ///
    /// Display-name rules:
    /// - The engine sends it only on community photos, already moderated and
    ///   sanitized server-side; the client renders it verbatim ("Photo by
    ///   <name>") after trimming — see `communityByline`.
    /// - Google Places photos never carry it; they keep `attribution` /
    ///   `attributionUri` and the Google attribution UI unchanged.
    /// - The engine never sends both; if a malformed payload does, the
    ///   community byline wins (our own attribution UI replaces Google's for
    ///   community shots — issue #49).
    /// - Optional-first: absent on pre-#49 payloads, decodes as nil, UI falls
    ///   back to the Google attribution path.
    public let contributorName: String?

    public var id: String { url }

    /// The byline text for a community photo, or nil for a Google photo.
    /// Whitespace-only names count as absent — a blank "Photo by " row is
    /// worse than no byline.
    public var communityByline: String? {
        guard let trimmed = contributorName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    public init(
        url: String,
        attribution: String? = nil,
        attributionUri: String? = nil,
        widthPx: Int? = nil,
        heightPx: Int? = nil,
        contributorName: String? = nil
    ) {
        self.url = url
        self.attribution = attribution
        self.attributionUri = attributionUri
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.contributorName = contributorName
    }
}

public struct VenuePhotosResponse: Codable, Sendable {
    public let photos: [VenuePhoto]

    public init(photos: [VenuePhoto]) {
        self.photos = photos
    }
}

public struct HealthResponse: Codable, Hashable, Sendable {
    public let ok: Bool
    public let venueCount: Int
    public let seededAt: String
    public let observationCount: Int?

    public init(ok: Bool, venueCount: Int, seededAt: String, observationCount: Int? = nil) {
        self.ok = ok
        self.venueCount = venueCount
        self.seededAt = seededAt
        self.observationCount = observationCount
    }
}

public struct NeighborhoodsResponse: Codable, Sendable {
    public struct Hood: Codable, Identifiable, Hashable, Sendable {
        public let name: String
        public let borough: String
        public let count: Int
        public var id: String { name }
    }
    public let neighborhoods: [Hood]
}
