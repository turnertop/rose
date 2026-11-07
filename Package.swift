// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Rose",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rose", targets: ["Rose"]),
        .executable(name: "RoseChecks", targets: ["RoseChecks"]),
        .executable(name: "RoseImagingChecks", targets: ["RoseImagingChecks"])
    ],
    targets: [
        .target(name: "RoseCore"),
        .target(name: "RoseImaging", dependencies: ["RoseCore"]),
        .executableTarget(name: "Rose", dependencies: ["RoseCore", "RoseImaging"]),
        // A standalone runner also works with Apple's Command Line Tools (no Xcode/XCTest required).
        .executableTarget(name: "RoseChecks", dependencies: ["RoseCore"], path: "Tests/RoseCoreChecks"),
        .executableTarget(name: "RoseImagingChecks", dependencies: ["RoseCore", "RoseImaging"], path: "Tests/RoseImagingChecks")
    ]
)
