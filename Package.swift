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
    targets: [
        .executableTarget(
            name: "MacGuard",
            path: ".",
            exclude: [
                "Info.plist",
                "MacGuard.entitlements",
                "Package.swift"
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
