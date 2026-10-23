// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tempo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tempo", targets: ["Tempo"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "TempoCore"),
        .executableTarget(
            name: "Tempo",
            dependencies: ["TempoCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "TempoChecks", dependencies: ["TempoCore"], path: "Tests/TempoCoreTests")
    ]
)
