import Foundation

public enum WifiMinimum: String, CaseIterable, Codable, Sendable {
    case slow
    case ok
    case fast
}

public enum OutletMinimum: String, CaseIterable, Codable, Sendable {
    case scarce
    case some
    case plenty
}

public enum VenueSort: String, Codable, Sendable {
    case workScore = "work_score"
    case distance
}

public struct VenueQuery: Equatable, Sendable {
    public var lat: Double?
    public var lng: Double?
    public var radiusM: Int
    public var wifiMinimum: WifiMinimum?
    public var outletMinimum: OutletMinimum?
    public var laptopFriendlyOnly: Bool
    public var neighborhood: String?
    public var search: String?
    public var sort: VenueSort
    public var limit: Int

    public init(
        lat: Double? = nil,
        lng: Double? = nil,
        radiusM: Int = 2_000,
        wifiMinimum: WifiMinimum? = nil,
        outletMinimum: OutletMinimum? = nil,
        laptopFriendlyOnly: Bool = false,
        neighborhood: String? = nil,
        search: String? = nil,
        sort: VenueSort = .workScore,
        limit: Int = 50
    ) {
        self.lat = lat
        self.lng = lng
        self.radiusM = radiusM
        self.wifiMinimum = wifiMinimum
        self.outletMinimum = outletMinimum
        self.laptopFriendlyOnly = laptopFriendlyOnly
        self.neighborhood = neighborhood
        self.search = search
        self.sort = sort
        self.limit = limit
    }

    var urlQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "sort", value: sort.rawValue),
            .init(name: "limit", value: String(limit)),
            .init(name: "radius_m", value: String(radiusM)),
        ]
        if let lat { items.append(.init(name: "lat", value: String(lat))) }
        if let lng { items.append(.init(name: "lng", value: String(lng))) }
        if let wifiMinimum { items.append(.init(name: "wifi_min", value: wifiMinimum.rawValue)) }
        if let outletMinimum { items.append(.init(name: "outlets_min", value: outletMinimum.rawValue)) }
        if laptopFriendlyOnly { items.append(.init(name: "laptops", value: "friendly")) }
        if let neighborhood { items.append(.init(name: "neighborhood", value: neighborhood)) }
        if let search { items.append(.init(name: "q", value: search)) }
        return items
    }
}
