// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Centwise",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LedgerCore", targets: ["LedgerCore"]),
        .executable(name: "LedgerPreview", targets: ["LedgerPreview"]),
        .executable(name: "LedgerTool", targets: ["LedgerTool"])
    ],
    targets: [
        .target(name: "LedgerCore", path: "Core", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "LedgerPreview", dependencies: ["LedgerCore"], path: "App"),
        .executableTarget(name: "LedgerTool", dependencies: ["LedgerCore"], path: "Tools"),
        .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
