// swift-tools-version: 5.9
// MacGuard - Anti-Theft Alarm for macOS

import PackageDescription

let package = Package(
    name: "MacGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacGuard",
            targets: ["MacGuard"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MacGuard",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: ".",
            exclude: [
                "Info.plist",
                "MacGuard.entitlements",
                "Package.swift",
                "README.md",
                "plans",
                "scripts",
                "appcast.xml",
                "dist",
                "featured-image.png"
            ],
            sources: [
                "MacGuardApp.swift",
                "Managers",
                "Views",
                "Models"
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
