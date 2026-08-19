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
        default: source
        }
    }
}

public struct VenueAttributes: Codable, Hashable, Sendable {
    public let wifi: Claim
    public let outlets: Claim
    public let laptopPolicy: Claim
    public let noise: Claim

    public init(wifi: Claim, outlets: Claim, laptopPolicy: Claim, noise: Claim) {
        self.wifi = wifi
        self.outlets = outlets
        self.laptopPolicy = laptopPolicy
        self.noise = noise
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
        distanceM: Int?
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
    }

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lng, address, neighborhood, borough, hoursRaw,
             vertical, attributes, vibeTags, workScore, lastVerified
        case distanceM = "distance_m"
    }

    public var scoreTier: ScoreTier { ScoreTier(score: workScore) }
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

public struct NeighborhoodsResponse: Codable, Sendable {
    public struct Hood: Codable, Identifiable, Hashable, Sendable {
        public let name: String
        public let borough: String
        public let count: Int
        public var id: String { name }
    }
    public let neighborhoods: [Hood]
}
