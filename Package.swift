// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Tempo", platforms: [.macOS(.v14)], products: [.executable(name: "Tempo", targets: ["Tempo"])], targets: [.target(name: "TempoCore"), .executableTarget(name: "Tempo", dependencies: ["TempoCore"]), .executableTarget(name: "TempoChecks", dependencies: ["TempoCore"], path: "Tests/TempoCoreTests")])
