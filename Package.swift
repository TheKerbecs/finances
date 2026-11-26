// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Finances",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FinanceCore"),
        .executableTarget(name: "Finances", dependencies: ["FinanceCore"]),
        .executableTarget(name: "SelfCheck", dependencies: ["FinanceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
