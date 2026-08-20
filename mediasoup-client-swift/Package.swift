// swift-tools-version: 5.9
import PackageDescription

// NOTE: This Package.swift is NOT used when mediasoup-client-swift is integrated
// as a target in sdk-ios/Package.swift. It's kept for standalone development/testing.

let package = Package(
    name: "MediasoupClient",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Mediasoup",
            targets: ["Mediasoup"]
        )
    ],
    dependencies: [
        // Public WebRTC XCFramework distribution used by VoxeraSDK.
        .package(
            url: "https://github.com/stasel/WebRTC.git",
            exact: "149.0.0"
        )
    ],
    targets: [
        .target(
            name: "Mediasoup",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/Mediasoup"
        )
    ]
)
