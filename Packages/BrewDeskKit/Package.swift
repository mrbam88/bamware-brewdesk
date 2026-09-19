// swift-tools-version: 6.2
// Package Traits (SE-0450, used below to opt this app into the real
// GoogleSignIn-iOS SDK via BamwareAccountsGoogle's `GoogleSignIn` trait)
// only need tools-version 6.1+ — this manifest was already on 6.2 for
// `.defaultIsolation` below, so no bump was needed for bamware-brewdesk#174.
import PackageDescription

let package = Package(
    name: "BrewDeskKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BrewDeskKit", targets: ["BrewDeskKit"]),
        .library(name: "VenueKit", targets: ["VenueKit"])
    ],
    dependencies: [
        // Pinned to the bamware-ios revision that contains B5-B8
        // (BamwareAccounts, BamwareAccountsGoogle, BamwareAccountUI,
        // bamware-brewdesk#174). Pin until bamware-ios publishes
        // semantic-version tags. `traits: ["GoogleSignIn"]` enables
        // BamwareAccountsGoogle's optional trait so the real GoogleSignIn-iOS
        // SDK links (off by default upstream) — see that package's README.
        .package(
            url: "https://github.com/mrbam88/bamware-ios.git",
            revision: "ac444619a96e5e018b33f6c2acf7d6dac0839415",
            traits: ["GoogleSignIn"]
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
                .product(name: "BamwareUI", package: "bamware-ios"),
                .product(name: "BamwareAccounts", package: "bamware-ios"),
                .product(name: "BamwareAccountsGoogle", package: "bamware-ios"),
                .product(name: "BamwareAccountUI", package: "bamware-ios")
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
