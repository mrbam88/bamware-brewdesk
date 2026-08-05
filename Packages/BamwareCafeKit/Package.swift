// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BamwareCafeKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BamwareCafeKit", targets: ["BamwareCafeKit"]),
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
        .target(name: "VenueKit"),
        // Feature layer: SwiftUI screens, tenant #3 theme on top of BamwareUI.
        .target(
            name: "BamwareCafeKit",
            dependencies: [
                "VenueKit",
                .product(name: "BamwareCore", package: "bamware-ios"),
                .product(name: "BamwareUI", package: "bamware-ios")
            ]
        ),
        .testTarget(
            name: "VenueKitTests",
            dependencies: ["VenueKit"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "BamwareCafeKitTests",
            dependencies: ["BamwareCafeKit", "VenueKit"]
        )
    ]
)
