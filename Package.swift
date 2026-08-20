// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxeraSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VoxeraSDK",
            targets: ["VoxeraSDK"]
        ),
        // Compatibility product for applications migrating from ROCS.
        .library(
            name: "RocsSDK",
            targets: ["RocsSDK"]
        )
    ],
    dependencies: [
        // Socket.IO client
        .package(
            url: "https://github.com/socketio/socket.io-client-swift.git",
            exact: "16.1.0"
        ),
        // Public WebRTC XCFramework distribution.
        .package(
            url: "https://github.com/stasel/WebRTC.git",
            exact: "149.0.0"
        )
    ],
    targets: [
        // Pure Swift mediasoup client (integrated from mediasoup-client-swift)
        .target(
            name: "Mediasoup",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "mediasoup-client-swift/Sources/Mediasoup"
        ),
        .target(
            name: "RocsSDK",
            dependencies: [
                "Mediasoup",
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ],
            path: "Sources/RocsSDK"
        ),
        .target(
            name: "VoxeraSDK",
            dependencies: ["RocsSDK"],
            path: "Sources/VoxeraSDK"
        )
    ]
)
