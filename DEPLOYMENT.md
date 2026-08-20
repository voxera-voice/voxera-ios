# RocsSDK iOS - Build, Publish & Deployment Guide

Complete guide for building, publishing to Nexus SPM registry, and using the RocsSDK iOS package.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building the SDK](#building-the-sdk)
- [Publishing to Nexus SPM](#publishing-to-nexus-spm)
- [Installing from Nexus](#installing-from-nexus)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### For Publishers (Deploy to Nexus)

```bash
# 1. Publish WebRTC
cd webrtc-ios-release
export NEXUS_URL="https://nexus.example.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="username"
export NEXUS_PASS="password"
./publish-to-nexus.sh 1.0.0

# 2. Update sdk-ios/Package.swift
cd ../sdk-ios
# Replace .package(path: "../webrtc-ios-release") with Nexus URL
# See "Publishing to Nexus SPM → Step 2" for details

# 3. Publish sdk-ios
./scripts/publish-to-nexus.sh
```

### For Users (Install from Nexus)

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://nexus.example.com/repository/swift-hosted/RocsSDK", from: "1.0.0")
]
```

That's it! WebRTC is included automatically. Users can optionally override with their own WebRTC.

---

## Prerequisites

### Development Environment
- macOS 13.0+ (Ventura or later)
- Xcode 15.0+ (Swift 5.9+)
- Git 2.30+
- Swift Package Manager (included with Xcode)

### Nexus Repository Manager
- Nexus 3.x with Swift Package Manager plugin
- Repository configured for Swift packages
- Valid Nexus credentials with publish permissions

### Dependencies & Peer Dependency Pattern

The SDK uses a **peer dependency pattern** for WebRTC:

- **socket.io-client-swift** (16.1.0+) - Direct dependency from GitHub
- **mediasoup-client-swift** - Integrated as target (sources in `mediasoup-client-swift/`)
- **WebRTC** - **PEER DEPENDENCY** (can be overridden by consumer)

**How Peer Dependencies Work:**

1. **sdk-ios** references WebRTC from Nexus (default fallback)
2. **Consuming app** CAN declare their own WebRTC package (same product name "WebRTC")
3. **Swift PM resolution:** If consumer provides WebRTC, it takes precedence over sdk-ios's reference
4. **Result:** RocsSDK uses consumer's WebRTC if provided, otherwise uses Nexus default

**Consumer Can Override (Optional):**

```swift
// Package.swift - User's own WebRTC takes precedence
dependencies: [
    .package(url: "https://nexus.../RocsSDK", from: "1.0.0"),
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

## Publishing to Nexus SPM

### ⚠️ IMPORTANT: Publish Order

**You MUST publish WebRTC before sdk-ios:**

1. ✅ **First:** Publish `webrtc-ios-release` to Nexus
2. ✅ **Second:** Update `sdk-ios/Package.swift` with WebRTC Nexus URL  
3. ✅ **Third:** Publish `sdk-ios` to Nexus

### Step 1: Publish WebRTC to Nexus

```bash
cd /path/to/packages/webrtc-ios-release

# Set environment variables
export NEXUS_URL="https://your-nexus-server.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"

# Publish WebRTC (specify version or use git tag)
./publish-to-nexus.sh 1.0.0

# Output:
# ✅ Successfully published WebRTC 1.0.0 to Nexus
#    URL: https://your-nexus-server.com/repository/swift-hosted/WebRTC/1.0.0/WebRTC-1.0.0.zip
```

### Step 2: Update sdk-ios Package.swift

After publishing WebRTC, update `sdk-ios/Package.swift` to reference WebRTC from Nexus instead of path:

**Find this line (around line 25):**
```swift
.package(path: "../webrtc-ios-release")
```

**Replace with:**
```swift
.package(
    url: "https://your-nexus-server.com/repository/swift-hosted/WebRTC",
    from: "1.0.0"
)
```

Also update the package name references in targets (around line 33 and 41):
```swift
// Change from:
.product(name: "WebRTC", package: "webrtc-ios-release")

// To:
.product(name: "WebRTC", package: "WebRTC")
```

**Full updated dependencies section:**
```swift
dependencies: [
    .package(
        url: "https://github.com/socketio/socket.io-client-swift.git",
        from: "16.1.0"
    ),
    .package(
        url: "https://your-nexus-server.com/repository/swift-hosted/WebRTC",
        from: "1.0.0"
    )
]
```

Commit the change:
```bash
cd /path/to/packages/sdk-ios
git add Package.swift
git commit -m "Configure WebRTC Nexus URL for publishing"
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin main 1.0.0
```

> **Note:** This change is only needed for Nexus publishing. For local development, you can keep the path dependency.

### Step 3: Publish sdk-ios to Nexus

### Prerequisites for Nexus Publishing

1. **Nexus Repository Setup**
   - Create a hosted repository for Swift packages
   - Repository type: `swift` (requires Nexus Swift Plugin)
   - Repository name: e.g., `swift-hosted`

2. **Authentication**
   - Nexus username and password/token
   - Or use deployment token

### Option 1: Manual Upload to Nexus

#### Step 1: Create Archive

```bash
cd /path/to/packages/sdk-ios

# Create a clean archive
git archive --format=zip --prefix=RocsSDK-1.0.0/ HEAD > RocsSDK-1.0.0.zip

# Or create tar.gz
git archive --format=tar.gz --prefix=RocsSDK-1.0.0/ HEAD > RocsSDK-1.0.0.tar.gz
```

#### Step 2: Upload to Nexus via Web UI

1. Login to Nexus: `https://your-nexus-server.com`
2. Navigate to Browse → Repositories → `swift-hosted`
3. Click "Upload Component"
4. Select "Swift Package" as format
5. Upload the archive
6. Fill in metadata:
   - **Name:** RocsSDK
   - **Version:** 1.0.0
   - **Repository URL:** (your git URL)

#### Step 3: Upload via curl (Alternative)

```bash
NEXUS_URL="https://your-nexus-server.com"
NEXUS_REPO="swift-hosted"
NEXUS_USER="your-username"
NEXUS_PASS="your-password"
VERSION="1.0.0"

curl -u "$NEXUS_USER:$NEXUS_PASS" \
  --upload-file "RocsSDK-${VERSION}.zip" \
  "${NEXUS_URL}/repository/${NEXUS_REPO}/RocsSDK/${VERSION}/RocsSDK-${VERSION}.zip"
```

### Option 2: Automated Publishing Script

Create a publish script `scripts/publish-to-nexus.sh`:

```bash
#!/bin/bash
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:-https://your-nexus-server.com}"
NEXUS_REPO="${NEXUS_REPO:-swift-hosted}"
NEXUS_USER="${NEXUS_USER}"
NEXUS_PASS="${NEXUS_PASS}"

# Get version from git tag
VERSION=$(git describe --tags --abbrev=0)
VERSION=${VERSION#v}  # Remove 'v' prefix if exists

if [ -z "$VERSION" ]; then
  echo "Error: No git tag found. Please tag the release first."
  echo "  git tag -a 1.0.0 -m 'Release 1.0.0'"
  echo "  git push origin 1.0.0"
  exit 1
fi

echo "📦 Publishing RocsSDK version $VERSION to Nexus..."

# Create archive
ARCHIVE_NAME="RocsSDK-${VERSION}.zip"
git archive --format=zip --prefix="RocsSDK-${VERSION}/" HEAD > "$ARCHIVE_NAME"

echo "✅ Created archive: $ARCHIVE_NAME"

# Upload to Nexus
UPLOAD_URL="${NEXUS_URL}/repository/${NEXUS_REPO}/RocsSDK/${VERSION}/${ARCHIVE_NAME}"

curl -f -u "${NEXUS_USER}:${NEXUS_PASS}" \
  --upload-file "$ARCHIVE_NAME" \
  "$UPLOAD_URL"

if [ $? -eq 0 ]; then
  echo "✅ Successfully published RocsSDK $VERSION to Nexus"
  echo "   URL: $UPLOAD_URL"
else
  echo "❌ Failed to publish to Nexus"
  exit 1
fi

# Cleanup
rm "$ARCHIVE_NAME"
echo "🧹 Cleaned up temporary archive"
```

Make it executable and run:

```bash
chmod +x scripts/publish-to-nexus.sh

# Set environment variables
export NEXUS_URL="https://your-nexus-server.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"

# Publish
./scripts/publish-to-nexus.sh
```

### Option 3: Docker Build & Publish

Use Docker to publish:

```bash
# Build and publish using Docker
docker build \
  --build-arg REPOSITORY="https://your-nexus-server.com/repository/swift-hosted" \
  --build-arg USERNAME="your-username" \
  --build-arg PASSWORD="your-password" \
  --build-arg VERSION="1.0.0" \
  -t sdk-ios-publisher:1.0.0 \
  -f Dockerfile \
  .

# Docker automatically publishes during build
```

**Using with environment variables:**

```bash
# Load credentials from environment
export NEXUS_URL="https://your-nexus-server.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"
export VERSION="1.0.0"

docker build \
  --build-arg REPOSITORY="${NEXUS_URL}/repository/${NEXUS_REPO}" \
  --build-arg USERNAME="${NEXUS_USER}" \
  --build-arg PASSWORD="${NEXUS_PASS}" \
  --build-arg VERSION="${VERSION}" \
  -t sdk-ios-publisher:${VERSION} \
  .
```

**Cleanup after publishing:**

```bash
docker rmi sdk-ios-publisher:1.0.0
```

### Option 4: CI/CD Pipeline (GitHub Actions)

Create `.github/workflows/publish-nexus.yml`:

```yaml
name: Publish to Nexus SPM

on:
  push:
    tags:
      - 'v*.*.*'
      - '*.*.*'

jobs:
  publish:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get version from tag
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/}
          VERSION=${VERSION#v}
          echo "VERSION=$VERSION" >> $GITHUB_OUTPUT

      - name: Create archive
        run: |
          git archive --format=zip \
            --prefix="RocsSDK-${{ steps.version.outputs.VERSION }}/" \
            HEAD > "RocsSDK-${{ steps.version.outputs.VERSION }}.zip"

      - name: Upload to Nexus
        env:
          NEXUS_URL: ${{ secrets.NEXUS_URL }}
          NEXUS_REPO: ${{ secrets.NEXUS_REPO }}
          NEXUS_USER: ${{ secrets.NEXUS_USER }}
          NEXUS_PASS: ${{ secrets.NEXUS_PASS }}
          VERSION: ${{ steps.version.outputs.VERSION }}
        run: |
          curl -f -u "${NEXUS_USER}:${NEXUS_PASS}" \
            --upload-file "RocsSDK-${VERSION}.zip" \
            "${NEXUS_URL}/repository/${NEXUS_REPO}/RocsSDK/${VERSION}/RocsSDK-${VERSION}.zip"
```

Add secrets to GitHub repository:
- `NEXUS_URL`: Your Nexus server URL
- `NEXUS_REPO`: Repository name (e.g., `swift-hosted`)
- `NEXUS_USER`: Nexus username
- `NEXUS_PASS`: Nexus password or token

### Option 5: GitLab CI/CD Pipeline

A `.gitlab-ci.yml` is included for GitLab CI/CD.

**Prerequisites:**
1. GitLab repository with CI/CD enabled
2. GitLab CI/CD variables configured
3. Git tag created for the version

**Setup GitLab CI/CD Variables:**

Navigate to: Project Settings → CI/CD → Variables

Add these variables:
- `NEXUS_URL` → `https://your-nexus-server.com` (masked)
- `NEXUS_USER` → Your Nexus username (masked)
- `NEXUS_PASS` → Your Nexus password (masked, protected)

**Trigger Publishing:**
```bash
# Tag the release
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin 1.0.0

# GitLab automatically triggers pipeline on tag push
```

**View Pipeline:**
- Navigate to: CI/CD → Pipelines
- Click on latest pipeline for your tag
- View jobs: validate:version, build:docker, publish:nexus

**Pipeline Stages:**
1. **Validate** - Checks tag exists, extracts version
2. **Build** - Builds Docker image with Nexus credentials
3. **Publish** - Uploads package to Nexus
4. **Notify** - Success/failure notification

### Option 6: Jenkins Pipeline

A `Jenkinsfile` is also included for Jenkins CI/CD.

**Prerequisites:**
1. Jenkins credentials configured with ID: `nexus-credentials`
2. Environment variable `NEXUS_URL` set in Jenkins
3. Git tag created for the version

**Setup Jenkins Job:**
1. Create new Pipeline job
2. Configure SCM to track the repository
3. Set Pipeline script from SCM → use `sdk-ios/Jenkinsfile`
4. Configure credentials: `nexus-credentials` → Username/Password
5. Add environment variable: `NEXUS_URL` → Your Nexus server URL

**Trigger Publishing:**
```bash
# Tag the release
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin 1.0.0

# Jenkins automatically builds and publishes
```

**Manual Trigger:**
- Build job in Jenkins
- Pipeline reads version from latest git tag
- Publishes using Docker build

---

## Installing from Nexus

### Prerequisites

1. **Configure Nexus Mirror (if using private registry)**

Create or edit `~/.netrc`:

```bash
machine your-nexus-server.com
login your-username
password your-password
```

Or use `.swift-package-manager/configuration/mirrors.json`:

```json
{
  "object": {
    "mirrors": [
      {
        "mirror": "https://your-nexus-server.com/repository/swift-proxy/",
        "original": "https://github.com"
      }
    ]
  }
}
```

### Option 1: Swift Package Manager (Package.swift)

**Basic Installation (Uses default WebRTC from Nexus):**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        // RocsSDK from Nexus (includes WebRTC dependency automatically)
        .package(
            url: "https://your-nexus-server.com/repository/swift-hosted/RocsSDK",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                .product(name: "RocsSDK", package: "RocsSDK")
            ]
        )
    ]
)
```

**Advanced: Override with Your Own WebRTC (Optional):**

If you want to use a different WebRTC version/source:

```swift
dependencies: [
    // RocsSDK from Nexus
    .package(
        url: "https://your-nexus-server.com/repository/swift-hosted/RocsSDK",
        from: "1.0.0"
    ),
    // Your custom WebRTC (same product name "WebRTC" will override sdk-ios's WebRTC)
    .package(
        url: "https://github.com/your-org/custom-webrtc.git",
        from: "2.0.0"
    )
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RocsSDK", package: "RocsSDK"),
            .product(name: "WebRTC", package: "custom-webrtc")  // Your WebRTC takes precedence
        ]
    )
]
```

SPM will use your WebRTC instead of the one referenced by sdk-ios.

### Option 2: Xcode Project (GUI)

**Basic Installation:**
1. File → Add Package Dependencies
2. Enter Package URL: `https://your-nexus-server.com/repository/swift-hosted/RocsSDK`
3. Select version: "Up to Next Major" from `1.0.0`
4. Click "Add Package"
5. Select "RocsSDK" product

**To Override WebRTC (Optional):**
Repeat steps 1-5 with your custom WebRTC URL before adding RocsSDK. Xcode will use your WebRTC.

### Option 3: XcodeGen (project.yml)

**Basic Installation (Uses default WebRTC from Nexus):**

```yaml
packages:
  RocsSDK:
    url: https://your-nexus-server.com/repository/swift-hosted/RocsSDK
    from: "1.0.0"

targets:
  YourApp:
    dependencies:
      - package: RocsSDK
        product: RocsSDK
```

**Advanced: Override with Your Own WebRTC (Optional):**

```yaml
packages:
  RocsSDK:
    url: https://your-nexus-server.com/repository/swift-hosted/RocsSDK
    from: "1.0.0"
  MyWebRTC:
    url: https://github.com/your-org/custom-webrtc.git
    from: "2.0.0"

targets:
  YourApp:
    dependencies:
      - package: RocsSDK
        product: RocsSDK
      - package: MyWebRTC
        product: WebRTC  # ← Same product name "WebRTC" overrides sdk-ios's WebRTC
```

Generate Xcode project:

```bash
xcodegen generate
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
            serverUrl: "wss://media.rocs-voice.com",
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
            serverUrl: "wss://media.rocs-voice.com",
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
    serverUrl: "wss://media.rocs-voice.com",
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

### Nexus Publishing Issues

**Issue: "401 Unauthorized"**

Check credentials:
```bash
# Test Nexus authentication
curl -u "username:password" https://your-nexus-server.com/service/rest/v1/status
```

**Issue: "404 Not Found"**

Verify repository exists:
1. Login to Nexus web UI
2. Check repository name matches `NEXUS_REPO` variable
3. Ensure Swift plugin is installed

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
config.serverUrl = "wss://media.rocs-voice.com"  // Must be wss://
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

- **Documentation:** https://docs.rocs-voice.com
- **Dashboard:** https://app.rocs-voice.com
- **Email:** support@rocs-voice.com
- **GitHub Issues:** https://github.com/rocs-voice/rocs-ios/issues
