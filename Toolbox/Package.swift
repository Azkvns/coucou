// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoucouToolbox",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CoucouToolbox", targets: ["CoucouToolbox"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.2.5")],
    targets: [
        .target(name: "CoucouToolbox", dependencies: ["SwiftTerm"],
                resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CoucouToolboxTests", dependencies: ["CoucouToolbox"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
