# RocsSDK iOS - Build, Publish & Deployment Guide

Complete guide for building, publishing, and using the VoxeraSDK iOS package.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building the SDK](#building-the-sdk)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### For Publishers

Swift Package Manager consumes packages straight from git, so publishing is
tagging — no registry, no credentials:

```bash
./scripts/build.sh --clean     # verify it builds
git tag 1.1.43
git push origin 1.1.43
```

### For Users

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/voxera-voice/voxera-ios.git", from: "1.1.43")
]
```

That's it — WebRTC resolves automatically from `github.com/stasel/WebRTC`.

---

## Prerequisites

### Development Environment
- macOS 13.0+ (Ventura or later)
- Xcode 15.0+ (Swift 5.9+)
- Git 2.30+
- Swift Package Manager (included with Xcode)

### Dependencies & Peer Dependency Pattern

The SDK uses a **peer dependency pattern** for WebRTC:

- **socket.io-client-swift** (16.1.0+) - Direct dependency from GitHub
- **mediasoup-client-swift** - Integrated as target (sources in `mediasoup-client-swift/`)
- **WebRTC** - **PEER DEPENDENCY** (can be overridden by consumer)

**How Peer Dependencies Work:**

1. **sdk-ios** references WebRTC from `github.com/stasel/WebRTC` (default)
2. **Consuming app** CAN declare their own WebRTC package (same product name "WebRTC")
3. **Swift PM resolution:** If consumer provides WebRTC, it takes precedence over sdk-ios's reference
4. **Result:** the SDK uses the consumer's WebRTC if provided, otherwise the default

**Consumer Can Override (Optional):**

```swift
// Package.swift - User's own WebRTC takes precedence
dependencies: [
    .package(url: "https://github.com/voxera-voice/voxera-ios.git", from: "1.1.43"),
    .package(url: "https://github.com/my-org/custom-webrtc.git", from: "2.0.0")  // ← Overrides sdk-ios's WebRTC
]
```

**Local Development:**

For local development, update Package.swift to use path:
```swift
.package(path: "../webrtc-ios-release")  // Local dev only
```

---

## Building the SDK

### 1. Clone the Repository

```bash
cd /path/to/packages
git clone <your-repo-url>/sdk-ios.git
cd sdk-ios
```

### 2. Verify Package Structure

```bash
# Check package is valid
swift package dump-package

# Expected output should show:
# - name: "RocsSDK"
# - products: ["RocsSDK"]
# - dependencies: ["socket.io-client-swift", "webrtc-ios-release"]
# - targets: ["Mediasoup", "RocsSDK"]
```

### 3. Build the Package (Optional - for verification)

```bash
# Build for iOS Simulator (verification only)
xcodebuild build \
  -scheme RocsSDK \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Note: swift build will fail because iOS-only package
# doesn't support macOS host platform
```

### 4. Create a Release Tag

```bash
# Tag the release version
git tag -a 1.0.0 -m "Release version 1.0.0"
git push origin 1.0.0

# Or for semantic versioning:
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

---

## Usage Guide

### 1. Add Required Permissions

Add to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice conversations</string>

<key>NSCameraUsageDescription</key>
<string>Required for video calls</string>
```

### 2. Import the SDK

```swift
import RocsSDK
import AVFoundation  // For RTCVideoTrack if using video
```

### 3. Basic Setup - SwiftUI with RocsViewModel

```swift
import SwiftUI
import RocsSDK

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceChatView()
        }
    }
}

struct VoiceChatView: View {
    @StateObject private var vm: RocsViewModel
    
    init() {
        let config = RocsConfig(
            appKey: "your-app-key-from-dashboard",
            serverUrl: "wss://media.example.com",
            userId: "user-123",
            threadId: "thread-456"  // Created in dashboard
        )
        _vm = StateObject(wrappedValue: RocsViewModel(config: config))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Status
            VStack {
                Text("Connection: \(vm.connectionStatus.rawValue)")
                Text("Conversation: \(vm.conversationStatus.rawValue)")
                Text("Speaking: \(vm.speakingStatus.rawValue)")
            }
            .font(.caption)
            
            // Controls
            HStack(spacing: 15) {
                if !vm.isConnected {
                    Button("Connect") {
                        vm.connect()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if !vm.isConversationActive {
                        Button("Start Chat") {
                            vm.startConversation()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("End Chat") {
                            vm.endConversation()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(vm.isMuted ? "Unmute" : "Mute") {
                        vm.toggleMute()
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.isMuted ? .red : .blue)
                    
                    Button(vm.isSpeakerOn ? "Earpiece" : "Speaker") {
                        vm.toggleAudioOutput()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Disconnect") {
                        vm.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages, id: \.id) { message in
                        HStack {
                            if message.role == "user" {
                                Spacer()
                            }
                            
                            VStack(alignment: message.role == "user" ? .trailing : .leading) {
                                Text(message.role.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(message.content)
                                    .padding(10)
                                    .background(message.role == "user" ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundColor(message.role == "user" ? .white : .primary)
                                    .cornerRadius(10)
                            }
                            
                            if message.role != "user" {
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
    }
}
```

### 4. Advanced Setup - Using RocsClient (Delegate Pattern)

```swift
import RocsSDK
import UIKit

class VoiceCallViewController: UIViewController {
    private var client: RocsClient!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure
        var config = RocsConfig(
            appKey: "your-app-key",
            serverUrl: "wss://media.example.com",
            userId: "user-123",
            threadId: "thread-456"
        )
        
        // Optional: Customize callbacks
        config.onConnectionStatusChange = { status in
            print("Connection: \(status)")
        }
        
        config.onConversationStatusChange = { status in
            print("Conversation: \(status)")
        }
        
        config.onSpeakingStatusChange = { status in
            print("Speaking: \(status)")
        }
        
        config.onMessage = { message in
            print("\(message.role): \(message.content)")
        }
        
        config.onError = { error in
            print("Error: \(error.message)")
        }
        
        // Create client
        client = RocsClient(config: config)
        client.delegate = self
    }
    
    @IBAction func connectTapped() {
        client.connect()
    }
    
    @IBAction func startConversationTapped() {
        client.startConversation()
    }
    
    @IBAction func toggleMuteTapped() {
        client.toggleMute()
    }
    
    @IBAction func toggleSpeakerTapped() {
        client.toggleAudioOutput()
    }
    
    @IBAction func endConversationTapped() {
        client.endConversation()
    }
    
    @IBAction func disconnectTapped() {
        client.disconnect()
    }
}

extension VoiceCallViewController: RocsClientDelegate {
    func client(_ client: RocsClient, didChangeConnectionStatus status: ConnectionStatus) {
        DispatchQueue.main.async {
            // Update UI
        }
    }
    
    func client(_ client: RocsClient, didChangeConversationStatus status: ConversationStatus) {
        DispatchQueue.main.async {
            // Update UI
        }
    }
    
    func client(_ client: RocsClient, didChangeSpeakingStatus status: SpeakingStatus) {
        DispatchQueue.main.async {
            // Update UI
        }
    }
    
    func client(_ client: RocsClient, didReceiveMessage message: ConversationMessage) {
        DispatchQueue.main.async {
            // Add to messages list
        }
    }
    
    func client(_ client: RocsClient, didFailWithError error: RocsError) {
        DispatchQueue.main.async {
            // Show error alert
        }
    }
    
    func client(_ client: RocsClient, didReceiveRemoteAudioTrack track: RTCMediaStreamTrack) {
        // Remote audio is automatically played
    }
    
    func client(_ client: RocsClient, didReceiveRemoteVideoTrack track: RTCMediaStreamTrack) {
        // Display video track in RTCVideoView
    }
}
```

### 5. Configuration Options

```swift
var config = RocsConfig(
    appKey: "your-app-key",
    serverUrl: "wss://media.example.com",
    userId: "user-123",
    threadId: "thread-456"
)

// Optional configurations
config.user = [
    "name": "John Doe",
    "email": "john@example.com",
    "avatar": "https://example.com/avatar.jpg"
]

config.chatProfile = "your-chat-profile-id"  // From dashboard
config.roomMode = .aiMeeting  // or .normalMeeting
config.displayName = "John Doe"

// Connection options
config.connectionOptions = ConnectionOptions(
    iceServers: [/* custom TURN/STUN servers */],
    enableVideo: false,
    enableAudio: true
)

// Callbacks
config.onConnectionStatusChange = { status in }
config.onConversationStatusChange = { status in }
config.onSpeakingStatusChange = { status in }
config.onMessage = { message in }
config.onError = { error in }
config.onAudioLevelChange = { level in }
config.onAIAudioLevelChange = { level in }
config.onRemoteAudioTrack = { track in }
config.onRemoteVideoTrack = { track in }
```

### 6. Audio Output Control

```swift
// Toggle between speaker and earpiece
client.toggleAudioOutput()

// Set explicitly
client.setAudioOutput(.speaker)   // Loud speaker
client.setAudioOutput(.earpiece)  // Earphone/receiver

// Check current route
let route = client.currentAudioRoute  // .speaker or .earpiece
```

### 7. Camera & Video

```swift
// Start camera
Task {
    try await client.startCamera(position: .front)  // or .back
}

// Switch camera
client.switchCamera()

// Stop camera
client.stopCamera()

// Access local video track
if let videoTrack = client.localVideoTrack {
    // Display in RTCVideoView
}
```

### 8. Meeting Controls (Normal Meeting Mode)

```swift
// Host controls
client.muteParticipant(targetClientId: "user-456")
client.muteAll()
client.unmuteAll()
client.removeParticipant(targetClientId: "user-456")
client.transferHost(toClientId: "user-456")
client.lockRoom(locked: true)
client.endMeeting()

// Waiting room
client.admitFromWaitingRoom(clientId: "user-456")
client.denyFromWaitingRoom(clientId: "user-456")

// AI features (text-only in normal meeting)
client.askAIText(question: "Summarize the discussion")
client.createBookmark(text: "Important point", isActionItem: true)
```

### 9. Error Handling

```swift
config.onError = { error in
    switch error.code {
    case .connectionFailed:
        print("Connection failed: \(error.message)")
    case .authenticationFailed:
        print("Authentication failed: \(error.message)")
    case .webRTCError:
        print("WebRTC error: \(error.message)")
    case .mediaAccessDenied:
        print("Microphone/Camera access denied")
    case .serverError:
        print("Server error: \(error.message)")
    case .networkError:
        print("Network error: \(error.message)")
    case .unknown:
        print("Unknown error: \(error.message)")
    }
}
```

---

## Troubleshooting

### Build Issues

**Issue: "No such module 'RocsSDK'"**

Solution:
```bash
# Clean and rebuild
rm -rf .build
rm -rf ~/Library/Developer/Xcode/DerivedData/*
xcodebuild clean
xcodebuild build -scheme RocsSDK -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Issue: "No such module 'WebRTC'"**

Solution:
```bash
# Verify webrtc-ios-release peer dependency exists
ls ../webrtc-ios-release/Package.swift

# If missing, clone it to the sibling directory:
cd /path/to/packages
git clone <repo-url>/webrtc-ios-release.git
cd sdk-ios
```

**Issue: "swift build fails with platform error"**

This is expected - sdk-ios is iOS-only and doesn't support macOS host platform. Use xcodebuild instead:

```bash
xcodebuild build -scheme RocsSDK -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Runtime Issues

**Issue: "Microphone access denied"**

Add to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice conversations</string>
```

**Issue: "Connection timeout"**

Check server URL and network:
```swift
config.serverUrl = "wss://media.example.com"  // Must be wss://
```

**Issue: "No audio output"**

Try toggling audio session:
```swift
client.setAudioOutput(.speaker)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-04-12 | - Initial release<br>- Pure Swift mediasoup client<br>- Dynamic WebRTC framework<br>- Audio output control (speaker/earpiece) |

---

## Support

- **GitHub Issues:** https://github.com/voxera-voice/voxera-ios/issues
