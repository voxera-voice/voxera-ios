# RocsSDK + JitsiMeetSDK Integration Guide

How to make `ios-voice-chat-demo` work with both **RocsSDK** (from `sdk-ios`) and **JitsiMeetSDK** (from `conference-sdk-ios-release`).

## Background

Both SDKs depend on WebRTC at runtime:

| Framework | WebRTC linking | Symbols used |
|-----------|---------------|--------------|
| **Mediasoup** (in sdk-ios) | Dynamic from webrtc-ios-release | ObjC only |
| **RocsSDK** (in sdk-ios) | Dynamic from webrtc-ios-release | ObjC API |
| **JitsiMeetSDK** | Dynamic from webrtc-ios-release | ObjC only |
| **GiphyUISDK** (JitsiMeetSDK dep) | none | N/A |

### Architecture

All frameworks share a **single WebRTC.xcframework** from `webrtc-ios-release` as a dynamic dependency. The pure Swift `mediasoup-client-swift` sources are integrated directly into `sdk-ios` as a target (not a separate package).

```
ios-voice-chat-demo
├── webrtc-ios-release (WebRTC.xcframework) ← shared by all
├── sdk-ios (RocsSDK)
│   ├── Mediasoup target (pure Swift, sources in mediasoup-client-swift/)
│   └── RocsSDK target
└── conference-sdk-ios-release (JitsiMeetSDK)
```

---

## Changes Required

### 1. sdk-ios/Package.swift — Mediasoup integrated as target

The `mediasoup-client-swift` sources are now a **target** inside sdk-ios, not a separate package:

```swift
dependencies: [
    .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.1.0"),
    .package(path: "../webrtc-ios-release"),  // Shared WebRTC
],
targets: [
    .target(
        name: "Mediasoup",
        dependencies: [
            .product(name: "WebRTC", package: "webrtc-ios-release")
        ],
        path: "mediasoup-client-swift/Sources/Mediasoup"
    ),
    .target(
        name: "RocsSDK",
        dependencies: [
            "Mediasoup",
            .product(name: "WebRTC", package: "webrtc-ios-release"),
            .product(name: "SocketIO", package: "socket.io-client-swift")
        ],
        path: "Sources/RocsSDK"
    )
]
```

### 2. ios-voice-chat-demo/project.yml — Add all dependencies

Add `webrtc-ios-release`, `RocsSDK`, `JitsiMeetSDK`, and `GiphyUISDK`:

```yaml
packages:
  RocsSDK:
    path: ../sdk-ios
  WebRTC:
    path: ../webrtc-ios-release
  JitsiMeetSDK:
    path: ../conference-sdk-ios-release
  GiphyUISDK:
    url: https://github.com/Giphy/giphy-ios-sdk.git
    exactVersion: "2.2.4"
  socket.io-client-swift:
    url: https://github.com/socketio/socket.io-client-swift.git
    from: "16.1.0"

targets:
  VoiceChatDemo:
    dependencies:
      - package: RocsSDK
        product: RocsSDK
      - package: WebRTC
        product: WebRTC
      - package: JitsiMeetSDK
        product: JitsiMeetSDK
      - package: GiphyUISDK
        product: GiphyUISDK
```

**Why GiphyUISDK is required:** JitsiMeetSDK dynamically links `@rpath/GiphyUISDK.framework/GiphyUISDK` at load time (not lazy). The app crashes at launch without it — a stub framework is not sufficient because JitsiMeetSDK resolves real Giphy symbols during framework initialization.

**GiphyUISDK version must be 2.2.4** — this matches the version JitsiMeetSDK (v9.0.107) was built against per its podspec.

### 3. ios-voice-chat-demo/Sources/ContentView.swift — Add imports

Add `import JitsiMeetSDK` and `import WebRTC` to force the linker to embed and link the frameworks:

```swift
import SwiftUI
import RocsSDK
import WebRTC
import JitsiMeetSDK
```

### 4. Regenerate the Xcode project

```bash
cd ios-voice-chat-demo
xcodegen generate
```

---

## Build & Verify

```bash
# Build for simulator
xcodebuild -scheme VoiceChatDemo -destination 'platform=iOS Simulator,name=iPhone 16' build

# Verify single WebRTC in app bundle (no duplicates)
ls DerivedData/.../VoiceChatDemo.app/Frameworks/
# Expected: GiphyUISDK.framework  JitsiMeetSDK.framework  WebRTC.framework
```

---

## Known Warnings

### Duplicate `PodsDummy_libwebp` class

```
objc: Class PodsDummy_libwebp is implemented in both
  .../GiphyUISDK.framework/GiphyUISDK and
  .../JitsiMeetSDK.framework/JitsiMeetSDK
```

Both JitsiMeetSDK and GiphyUISDK statically link `libwebp`. The ObjC runtime deduplicates it safely at launch — this is a **warning only**, not a crash. It can only be resolved by rebuilding one of the frameworks without bundling libwebp.

---

## Architecture Summary

```
VoiceChatDemo.app/Frameworks/
├── WebRTC.framework        ← webrtc-ios-release (ObjC symbols, shared by all)
├── JitsiMeetSDK.framework  ← conference-sdk-ios-release (links WebRTC via @rpath)
└── GiphyUISDK.framework    ← SPM v2.2.4 (JitsiMeetSDK runtime dependency)

RocsSDK embedded components:
├── Mediasoup (pure Swift sources, uses WebRTC ObjC API)
└── RocsSDK (Swift sources, uses Mediasoup + WebRTC)
```

All frameworks share the **single** `WebRTC.framework` from webrtc-ios-release via `@rpath`. No duplicate WebRTC binaries. RocsSDK and Mediasoup are embedded as Swift code, not separate frameworks.

---

## What Changed from Previous Architecture

| Component | Old | New |
|-----------|-----|-----|
| Mediasoup | C++ xcframework (218 C++ symbols) | Pure Swift target in sdk-ios |
| WebRTC source | Bundled in sdk-ios/Frameworks/ | Dynamic from webrtc-ios-release |
| WebRTC symbols | C++ + ObjC (superset) | ObjC only |
| mediasoup-client-swift | Separate package | Integrated target in sdk-ios |

**Why this works now:** The pure Swift mediasoup implementation only uses WebRTC's ObjC API (RTCPeerConnection, RTCAudioTrack, etc.), not C++ classes. This allows using the standard webrtc-ios-release build.
