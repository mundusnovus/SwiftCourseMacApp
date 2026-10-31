// swift-tools-version: 6.2
// Swift: Zero to Hero, the Mac and iPhone apps, by Asteria Technology.
// ZeroToHeroKit is the course, its screens and its runners, shared by both apps. The Mac app builds with SwiftPM
// (tools/build-app.sh); the iPhone app builds with Xcode from project.yml (tools/build-ios.sh).
import PackageDescription

let package = Package(
    name: "SwiftZeroToHero",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ZeroToHeroKit", targets: ["ZeroToHeroKit"]),
    ],
    targets: [
        .target(
            name: "ZeroToHeroKit",
            path: "Sources/ZeroToHeroKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "ZeroToHero",
            dependencies: ["ZeroToHeroKit"],
            path: "Sources/ZeroToHero",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
