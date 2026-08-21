import Foundation
import Testing
@testable import VenueKit

/// `VenueSnapshot` is the cold-start seed (brewdesk#28): it must decode the
/// engine's list shape and must never surface an error into first paint.
@Suite struct VenueSnapshotTests {
    @Test func decodesTheEngineListShape() throws {
        let url = try #require(Bundle.module.url(forResource: "venues", withExtension: "json"))
        let venues = try VenueSnapshot.load(from: url)
        #expect(!venues.isEmpty)
        #expect(venues.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }

    @Test func missingResourceIsAnEmptySnapshotNotAnError() {
        #expect(VenueSnapshot.load(bundle: .module, resource: "does-not-exist").isEmpty)
    }

    @Test func corruptFileThrowsFromTheThrowingLoaderOnly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brewdesk-corrupt-snapshot-\(UUID().uuidString).json")
        try Data("{not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try VenueSnapshot.load(from: url) }
    }
}
