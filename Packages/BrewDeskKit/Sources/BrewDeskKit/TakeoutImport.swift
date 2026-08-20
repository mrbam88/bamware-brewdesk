import Foundation
import VenueKit

/// Parses Google Takeout "Saved Places" exports entirely on-device.
/// Two shapes exist in the wild: a GeoJSON FeatureCollection and a CSV
/// (Title,Note,URL — coordinates only inside the Maps URL, when present).
public enum TakeoutImportError: Error, Equatable {
    case unrecognizedFormat
}

public struct TakeoutPlace: Equatable, Sendable {
    public let name: String
    public let lat: Double?
    public let lng: Double?

    public init(name: String, lat: Double? = nil, lng: Double? = nil) {
        self.name = name
        self.lat = lat
        self.lng = lng
    }
}

public enum TakeoutParser {
    public static func parse(_ data: Data) throws -> [TakeoutPlace] {
        if let places = parseGeoJSON(data) { return places }
        if let places = parseCSV(data) { return places }
        throw TakeoutImportError.unrecognizedFormat
    }

    // MARK: GeoJSON — {"type":"FeatureCollection","features":[...]}

    private static func parseGeoJSON(_ data: Data) -> [TakeoutPlace]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { return nil }

        let places = features.compactMap { feature -> TakeoutPlace? in
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let location = properties["location"] as? [String: Any] ?? [:]
            let name = (location["name"] as? String)
                ?? (properties["Title"] as? String)
                ?? (properties["name"] as? String)
            guard let name, !name.isEmpty else { return nil }

            var lat: Double?
            var lng: Double?
            if let geometry = feature["geometry"] as? [String: Any],
               let coords = geometry["coordinates"] as? [Any], coords.count == 2 {
                lng = (coords[0] as? NSNumber)?.doubleValue
                lat = (coords[1] as? NSNumber)?.doubleValue
            }
            return TakeoutPlace(name: name, lat: lat, lng: lng)
        }
        return places.isEmpty ? nil : places
    }

    // MARK: CSV — header "Title,Note,URL" (RFC-4180 quoting on the title)

    private static func parseCSV(_ data: Data) -> [TakeoutPlace]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first,
              header.lowercased().replacingOccurrences(of: "\"", with: "").hasPrefix("title")
        else { return nil }
        lines.removeFirst()

        let places = lines.compactMap { line -> TakeoutPlace? in
            let fields = splitCSVLine(line)
            guard let title = fields.first?.trimmingCharacters(in: .whitespaces),
                  !title.isEmpty
            else { return nil }
            // URL is the last column; unquoted commas inside it (`@lat,lng,17z`)
            // would otherwise split it apart.
            let url = fields.count >= 3 ? fields[2...].joined(separator: ",") : ""
            let coords = coordinates(inMapsURL: url)
            return TakeoutPlace(name: title, lat: coords?.lat, lng: coords?.lng)
        }
        return places.isEmpty ? nil : places
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            switch character {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current)
                current = ""
            default: current.append(character)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
    }

    /// Maps URLs carry coordinates as `!3d<lat>!4d<lng>` or `@lat,lng,`.
    static func coordinates(inMapsURL url: String) -> (lat: Double, lng: Double)? {
        if let range3d = url.range(of: #"!3d(-?\d+\.?\d*)!4d(-?\d+\.?\d*)"#, options: .regularExpression) {
            let token = String(url[range3d])
            let parts = token.dropFirst(3).components(separatedBy: "!4d")
            if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                return (lat, lng)
            }
        }
        if let rangeAt = url.range(of: #"@(-?\d+\.?\d*),(-?\d+\.?\d*)"#, options: .regularExpression) {
            let token = String(url[rangeAt]).dropFirst()
            let parts = token.components(separatedBy: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                return (lat, lng)
            }
        }
        return nil
    }
}

public enum TakeoutMatcher {
    public struct Result: Sendable {
        public let matched: [Venue]
        public let unmatched: [TakeoutPlace]
    }

    /// A place matches a venue by normalized-name containment or by sitting
    /// within 150m of it. Display-only decision — no fuzzy guessing beyond that.
    public static func match(places: [TakeoutPlace], venues: [Venue]) -> Result {
        var matched: [Venue] = []
        var unmatched: [TakeoutPlace] = []

        for place in places {
            if let venue = venues.first(where: { matches(place, $0) }) {
                if !matched.contains(venue) { matched.append(venue) }
            } else {
                unmatched.append(place)
            }
        }
        return Result(matched: matched, unmatched: unmatched)
    }

    static func matches(_ place: TakeoutPlace, _ venue: Venue) -> Bool {
        let placeName = normalized(place.name)
        let venueName = normalized(venue.name)
        if placeName == venueName { return true }
        if placeName.count >= 5, venueName.contains(placeName) { return true }
        if venueName.count >= 5, placeName.contains(venueName) { return true }
        if let lat = place.lat, let lng = place.lng {
            return VenuesModel.metersBetween(lat, lng, venue.lat, venue.lng) <= 150
        }
        return false
    }

    static func normalized(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
