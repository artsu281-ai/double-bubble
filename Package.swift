// swift-tools-version: 5.10
// NOTE: This Package.swift is for IDE support only.
// To build Double Bubble, open DoubleBubble.xcodeproj in Xcode.
import PackageDescription

let package = Package(
    name: "DoubleBubble",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DoubleBubble",
            path: "DoubleBubble",
            exclude: ["DoubleBubble.entitlements", "Info.plist"]
        )
    ]
)
