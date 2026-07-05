// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KikiCommerceKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KikiCommerceCore", targets: ["KikiCommerceCore"]),
        .library(name: "KikiRevenueCat", targets: ["KikiRevenueCat"]),
        .library(name: "KikiCommercePresentation", targets: ["KikiCommercePresentation"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/RevenueCat/purchases-ios-spm.git",
            exact: "5.67.0"
        ),
        // TODO: switch to `.upToNextMinor(from: "0.7.0")` once Kiki_mackit 0.7.0
        // is tagged after the Cat Lock reference migration validates the API.
        // Local dev: `swift package edit Kiki_mackit` to point at a local checkout.
        .package(
            url: "https://github.com/Feng6611/Kiki_mackit.git",
            branch: "main"
        )
    ],
    targets: [
        .target(name: "KikiCommerceCore"),
        .target(
            name: "KikiRevenueCat",
            dependencies: [
                "KikiCommerceCore",
                .product(name: "RevenueCat", package: "purchases-ios-spm")
            ]
        ),
        .target(
            name: "KikiCommercePresentation",
            dependencies: [
                "KikiCommerceCore",
                .product(name: "KikiPaywall", package: "Kiki_mackit")
            ]
        ),
        .testTarget(
            name: "KikiCommerceCoreTests",
            dependencies: ["KikiCommerceCore"]
        ),
        .testTarget(
            name: "KikiRevenueCatTests",
            dependencies: [
                "KikiRevenueCat",
                .product(name: "RevenueCat", package: "purchases-ios-spm")
            ]
        ),
        .testTarget(
            name: "KikiCommercePresentationTests",
            dependencies: ["KikiCommercePresentation"]
        )
    ]
)
