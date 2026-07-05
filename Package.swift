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
        .package(
            url: "https://github.com/Feng6611/Kiki_mackit.git",
            exact: "0.7.1"
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
