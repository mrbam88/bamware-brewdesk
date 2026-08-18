// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrewDeskKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BrewDeskKit", targets: ["BrewDeskKit"]),
        .library(name: "VenueKit", targets: ["VenueKit"])
    ],
    dependencies: [
        // Pin until bamware-ios publishes semantic-version tags.
        .package(
            url: "https://github.com/mrbam88/bamware-ios.git",
            revision: "464bf1daf166de4ef2826d6c81dac18690601dee"
        )
    ],
    targets: [
        // Pure networking + models. Zero UI, zero cross-repo deps.
        .target(
            name: "VenueKit",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        // Feature layer: BrewDesk SwiftUI screens and theme on top of BamwareUI.
        .target(
            name: "BrewDeskKit",
            dependencies: [
                "VenueKit",
                .product(name: "BamwareCore", package: "bamware-ios"),
                .product(name: "BamwareUI", package: "bamware-ios")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "VenueKitTests",
            dependencies: ["VenueKit"],
            resources: [.process("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "BrewDeskKitTests",
            dependencies: ["BrewDeskKit", "VenueKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ]
)
