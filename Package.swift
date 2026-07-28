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
        .library(name: "KikiCommercePresentation", targets: ["KikiCommercePresentation"]),
        .library(name: "KikiCommerceTesting", targets: ["KikiCommerceTesting"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/RevenueCat/purchases-ios-spm.git",
            exact: "5.67.0"
        ),
        .package(
            url: "https://github.com/Feng6611/Kiki_mackit.git",
            exact: "0.9.1"
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
        .target(
            name: "KikiCommerceTesting",
            dependencies: ["KikiCommerceCore"]
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
        ),
        .testTarget(
            name: "KikiCommerceTestingTests",
            dependencies: ["KikiCommerceCore", "KikiCommerceTesting"]
        )
    ]
)
