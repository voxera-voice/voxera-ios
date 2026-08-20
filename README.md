# Voxera SDK — iOS / macOS

Swift SDK for the Voxera Voice Platform. New integrations should import
`VoxeraSDK` and use `VoxeraClient`, `VoxeraConfig`, and `VoxeraViewModel`.
The legacy product and type names remain available for one compatibility cycle.

## Requirements

- iOS 15.0+ / macOS 13.0+
- Xcode 15+
- Swift 5.9+

## Installation

### Swift Package Manager (GitLab)

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://gitlab-eu.avrioc.io/ai/sdk/voxera/ios.git",
        from: "1.1.42"
    )
]
```

Then add `VoxeraSDK` to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "VoxeraSDK", package: "ios")
    ]
)
```

#### Xcode Project

1. **File > Add Package Dependencies...**
2. Enter: `https://gitlab-eu.avrioc.io/ai/sdk/voxera/ios.git`
3. Set version rule to **Up to Next Major** from `1.1.42`
4. Add `VoxeraSDK` to your target

#### XcodeGen (`project.yml`)

```yaml
packages:
  VoxeraSDK:
    url: https://gitlab-eu.avrioc.io/ai/sdk/voxera/ios.git
    from: "1.1.42"

targets:
  YourApp:
    dependencies:
      - package: VoxeraSDK
        product: VoxeraSDK
```

### CocoaPods

```ruby
source "https://cdn.cocoapods.org/"

target "YourApp" do
  pod "VoxeraSDK", "1.1.42"
end
```

For local development, use `pod "VoxeraSDK", :path => "../ios"`.

Both installation methods resolve WebRTC from public package infrastructure:
Swift Package Manager uses `stasel/WebRTC` 149.0.0 and CocoaPods uses
`WebRTC-lib` 149.0.0. Do not add another WebRTC binary to the application.

### Authentication (Private Repos)

Since the GitLab repo is private, configure credentials:

**Xcode:** Add your GitLab account in **Xcode > Settings > Accounts**.

**CI / Command-line:** Add to `~/.netrc`:

```
machine gitlab-eu.avrioc.io
login <your-username>
password <your-personal-access-token>
```

### Local Development

```swift
dependencies: [
    .package(path: "../sdk-ios")
]
```

## Required Permissions

Add to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice chat</string>
<key>NSCameraUsageDescription</key>
<string>Required for video chat</string>
```

## Quick Start — SwiftUI

```swift
import SwiftUI
import VoxeraSDK

struct VoiceChatView: View {
    @StateObject private var vm = VoxeraViewModel(config: VoxeraConfig(
        appKey: "your-app-key",
        serverUrl: "wss://media.voxera.ai",
        userId: "user-123",
        threadId: "thread-456"
    ))

    var body: some View {
        VStack(spacing: 16) {
            Text("Status: \(vm.connectionStatus.rawValue)")
            Text("Conversation: \(vm.conversationStatus.rawValue)")
            Text("Speaking: \(vm.speakingStatus.rawValue)")

            // Messages
            ForEach(vm.messages) { msg in
                Text("\(msg.role.rawValue): \(msg.content)")
            }

            // Controls
            HStack {
                Button("Connect") { vm.connect() }
                Button("Start") { vm.startConversation() }
                Button(vm.isMuted ? "Unmute" : "Mute") { vm.toggleMute() }
                Button("Stop") { vm.endConversation() }
                Button("Disconnect") { vm.disconnect() }
            }
        }
    }
}
```

## Quick Start — UIKit (Delegate)

```swift
import VoxeraSDK

class ChatViewController: UIViewController, VoxeraClientDelegate {
    private var client: VoxeraClient!

    override func viewDidLoad() {
        super.viewDidLoad()
        client = VoxeraClient(config: VoxeraConfig(
            appKey: "your-app-key",
            serverUrl: "wss://media.voxera.ai",
            userId: "user-123",
            threadId: "thread-456"
        ))
        client.delegate = self
        client.connect()
    }

    // MARK: - VoxeraClientDelegate
    func client(_ client: VoxeraClient, didChangeConnectionStatus status: ConnectionStatus) {
        if status == .connected {
            client.startConversation()
        }
    }

    func client(_ client: VoxeraClient, didReceiveMessage message: ConversationMessage) {
        print("\(message.role): \(message.content)")
    }

    func client(_ client: VoxeraClient, didFailWithError error: VoxeraError) {
        print("Error: \(error.message)")
    }
}
```

## Justin Action Integration

Use this flow when the server emits a `justin_action` and you need to send back a tool output.

### 1) Receive `justin_action`

Implement the delegate callback:

```swift
func client(_ client: VoxeraClient, didReceiveToolCalls tools: [ToolCall], messageId: String) {
        guard let action = tools.first else { return }
        print("action_id: \(action.id)")
        print("name: \(action.function.name)")
        print("arguments: \(action.function.arguments)") // JSON string
}
```

Server payload shape:

```json
{
    "type": "justin_action",
    "content": {
        "action_id": "YJ8hC9qHC",
        "name": "schedule_message",
        "arguments": {
            "schedule_message": {
                "message": "Hi Ayman, are the justin actions works?",
                "recipient": { "name": "ayman" },
                "schedule": { "time": "2026-04-17T14:00:00" }
            }
        }
    }
}
```

### 2) Send `select-actions` output

Call:

```swift
client.selectAction(
        message: "message was scheduled to ayman",
        actionId: "YJ8hC9qHC"
)
```

This sends:

```json
{
    "message": "message was scheduled to ayman",
    "event": "justin_action_output",
    "action_id": "YJ8hC9qHC"
}
```

## Configuration

```swift
let config = VoxeraConfig(
    appKey: "your-app-key",                          // Required — from the Voxera dashboard
    serverUrl: "wss://media.voxera.ai",              // Required — media server URL
    userId: "user-123",                              // Optional
    threadId: "thread-456",                          // Optional               // Optional
    username: "Alice",                               // Optional — tells the AI who is speaking
    userInfo: ["plan": "pro", "locale": "en-US"],    // Optional — extra context added to system prompt
)
```

## API Reference

### VoxeraClient / VoxeraViewModel

#### Connection
| Method | Description |
|--------|-------------|
| `connect()` | Connect to the media server |
| `disconnect()` | Disconnect and reset state |

#### Conversation
| Method | Description |
|--------|-------------|
| `startConversation()` | Start a voice conversation |
| `endConversation()` | End the current conversation |
| `selectAction(message:actionId:)` | Send tool output for a received `justin_action` |

#### Media Controls
| Method | Description |
|--------|-------------|
| `toggleMute()` / `setMuted(_ :)` | Toggle or set microphone mute |
| `toggleListenMode()` / `setListenMode(_ :)` | Toggle listen-only mode |
| `toggleVideo(track:)` / `enableVideo(track:)` / `disableVideo()` | Video controls |
| `startCamera(position:)` / `stopCamera()` / `switchCamera()` | Camera controls |
| `setAudioOutput(_ :)` / `toggleAudioOutput()` | Switch between `.speaker` and `.earpiece` |



### State Properties

All properties are `@Published` and observable:

| Property | Type | Description |
|----------|------|-------------|
| `connectionStatus` | `ConnectionStatus` | `.idle`, `.connecting`, `.connected`, `.reconnecting`, `.disconnected`, `.error` |
| `conversationStatus` | `ConversationStatus` | `.idle`, `.starting`, `.active`, `.ending`, `.ended` |
| `speakingStatus` | `SpeakingStatus` | `.user`, `.ai`, `.none` |
| `messages` | `[ConversationMessage]` | Conversation messages |
| `isMuted` | `Bool` | Microphone mute state |
| `isVideoEnabled` | `Bool` | Video enabled state |
| `audioLevel` | `Float` | Current user audio level |
