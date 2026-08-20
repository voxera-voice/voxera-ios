// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RocsVoiceDemo",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "RocsVoiceDemo",
            dependencies: [
                .product(name: "RocsSDK", package: "RocsSDK")
            ],
            path: "Sources/RocsVoiceDemo"
        )
    ]
)
socket.io-client-swift → GitHub (16.1.0+)
