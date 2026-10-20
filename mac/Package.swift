// swift-tools-version:6.2
// Binah for Mac: SwiftUI and AppKit over Binah's JSON API (docs/API.md), not a web view. Built and
// wrapped into an .app by build.sh.
import PackageDescription

let package = Package(
    name: "Binah",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Binah", path: "Sources/Binah")
    ],
    swiftLanguageModes: [.v5]
)
