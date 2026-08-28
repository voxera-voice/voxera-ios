// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxeraSDK",
    platforms: [
        // iOS only. This used to also claim .macOS(.v13), which was never
        // true: the WebRTC dependency ships no usable macOS slice, so a macOS
        // build fails on "'WebRTC/RTCAudioSource.h' file not found".
        //
        // Removing it does NOT change that failure -- SPM still builds for the
        // host, so a bare `swift build` on a Mac fails exactly as before. What
        // it fixes is the manifest advertising a platform the package cannot
        // support, which is what made the failure look like a broken package
        // rather than the wrong build target. Build for iOS:
        //
        //   xcodebuild -scheme VoxeraSDK -destination 'generic/platform=iOS Simulator' build
        .iOS(.v15)
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
