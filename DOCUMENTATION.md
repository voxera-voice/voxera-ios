# ROCS iOS SDK — Documentation

## Table of Contents

- [Installation](#installation)
  - [Local Package (Development)](#local-package-development)
  - [Nexus Registry (Production)](#nexus-registry-production)
- [Using a Custom WebRTC Package](#using-a-custom-webrtc-package)
- [Socket Events Reference](#socket-events-reference)
  - [Client → Server (Emitted)](#client--server-emitted)
  - [Server → Client (Received)](#server--client-received)

---

## Installation

### Requirements

- iOS 16.0+
- Xcode 15.0+ (Swift 5.9)
- The SDK ships with bundled binary frameworks:
  - `Mediasoup.xcframework` — mediasoup-client for WebRTC SFU transport
  - `WebRTC.xcframework` — Google WebRTC (patched for Swift 6 compatibility)

### Local Package (Development)

Use this when the SDK source lives alongside your project (e.g., in a monorepo).

**1. Add to your `Package.swift` dependencies:**

```swift
dependencies: [
    .package(path: "../sdk-ios")  // adjust the relative path to the SDK root
]
```

Then add `RocsSDK` to your target:

```swift
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "RocsSDK", package: "sdk-ios")
        ]
    )
]
```

**2. Or add via XcodeGen (`project.yml`):**

```yaml
packages:
  RocsSDK:
    path: ../sdk-ios

targets:
  MyApp:
    dependencies:
      - package: RocsSDK
        product: RocsSDK
```

Then run:

```bash
xcodegen generate
```

**3. Or add in Xcode UI:**

1. Open your `.xcodeproj` in Xcode
2. **File → Add Package Dependencies…**
3. Click **Add Local…** and select the `sdk-ios` folder
4. Select the `RocsSDK` library product

After adding, resolve packages:

```bash
xcodebuild -resolvePackageDependencies
```

## Socket Events Reference

The SDK communicates with the ROCS media server over Socket.IO. All events below use JSON payloads.

### Client → Server (Emitted)

#### Connection & Session Setup

| Event | Payload | Description |
|-------|---------|-------------|
| `init-session-connection` | `{ sessionId, threadId, chatProfile, userId, user, clientType, appKey, ttsConfig?, transcriptionConfig?, initialMessages?, selectedModel?, selectedVoice?, workspaceId? }` | Initialize a session. Sent immediately after socket connects. |
| `getRtpCapabilities` | `{}` | Request the mediasoup router's RTP capabilities. Returns codec/header-extension list. |
| `getIceServers` | `{}` | Request ICE/TURN server configuration from the server. |
| `createTransport` | `{}` or `{ consuming: true }` | Create a WebRTC transport. Call once for send, once for receive (with `consuming: true`). Returns transport parameters (id, iceParameters, iceCandidates, dtlsParameters). |
| `connectTransport` | `{ transportId, dtlsParameters }` | Complete the DTLS handshake for a transport. `dtlsParameters` is a JSON object with `role` and `fingerprints`. |
| `produce` | `{ transportId, kind, rtpParameters }` | Start sending media. `kind` is `"audio"` or `"video"`. `rtpParameters` is a JSON object from mediasoup-client. Returns `{ id }` (the server-side producer ID). |
| `consume` | `{ producerId, rtpCapabilities, transportId }` | Request to receive a remote producer's media. Returns `{ id, kind, rtpParameters }` for creating a local consumer. |
| `join` | `{ sessionId, appKey, rtpCapabilities }` | Join a room. Returns an array of existing producers to consume. |

#### Conversation Control

| Event | Payload | Description |
|-------|---------|-------------|
| `startConversation` | `{ sessionId }` | Begin an AI voice conversation in the session. |
| `endConversation` | `{ sessionId }` | End the current conversation. |
| `sendMessage` | `{ sessionId, message }` | Send a text message to the AI while in a conversation. |

#### Meeting / Host Controls

| Event | Payload | Description |
|-------|---------|-------------|
| `mute-participant` | `{ sessionId, targetClientId }` | Mute a specific participant (host only). |
| `mute-all` | `{ sessionId }` | Mute all participants (host only). |
| `unmute-all` | `{ sessionId }` | Unmute all participants (host only). |
| `remove-participant` | `{ sessionId, targetClientId }` | Remove a participant from the room (host only). |
| `lock-room` | `{ sessionId, locked }` | Lock or unlock the room (host only). |
| `end-meeting` | `{ sessionId }` | End the meeting for all participants (host only). |
| `transfer-host` | `{ sessionId, targetClientId }` | Transfer host role to another participant. |

#### Transcription & AI Tools

| Event | Payload | Description |
|-------|---------|-------------|
| `toggle-transcription` | `{ sessionId, enabled }` | Enable or disable live transcription. |
| `ask-ai` | `{ sessionId }` | Trigger an AI analysis of the current conversation. |
| `cancel-ask-ai` | `{ sessionId }` | Cancel an in-progress AI analysis. |
| `ask-ai-text` | `{ sessionId, prompt, ... }` | Send a text-only AI query (non-voice). |
| `generate-summary` | `{ sessionId }` | Generate a summary of the meeting/conversation. |
| `generate-minutes` | `{ sessionId }` | Generate meeting minutes. |

#### Bookmarks

| Event | Payload | Description |
|-------|---------|-------------|
| `add-bookmark` | `{ sessionId, label, isActionItem }` | Add a bookmark at the current point in the conversation. |
| `remove-bookmark` | `{ sessionId, bookmarkId }` | Remove a bookmark by ID. |
| `get-bookmarks` | `{ sessionId }` | Retrieve all bookmarks for the session. |

#### Waiting Room

| Event | Payload | Description |
|-------|---------|-------------|
| `enable-waiting-room` | `{ sessionId, enabled }` | Toggle the waiting room (host only). |
| `admit-participant` | `{ sessionId, targetClientId }` | Admit a participant from the waiting room. |
| `deny-participant` | `{ sessionId, targetClientId }` | Deny a participant in the waiting room. |
| `admit-all` | `{ sessionId }` | Admit all participants from the waiting room. |

#### Data Retrieval

| Event | Payload | Description |
|-------|---------|-------------|
| `get-transcript` | `{ sessionId }` | Retrieve the full transcript. |
| `get-summaries` | `{ sessionId }` | Retrieve all generated summaries. |
| `get-minutes` | `{ sessionId }` | Retrieve generated meeting minutes. |

---

### Server → Client (Received)

#### WebRTC Media Events

| Event | Payload | Description |
|-------|---------|-------------|
| `new-producer` | `{ producerId }` | A new remote producer is available. The client should call `consume` to receive its media. |
| `producer-closed` | `{ producerId }` | A remote producer was closed. Clean up the corresponding consumer. |
| `transport-error` | `{ error, id }` | A server-side transport error occurred. |
| `producer-error` | `{ error }` | A server-side producer error occurred. |

#### Conversation State

| Event | Payload | Description |
|-------|---------|-------------|
| `conversation-started` | — | The AI conversation has started. |
| `conversation-ended` | `{ ... }` | The AI conversation has ended. |
| `conversation-message` | `{ sessionId, role, content, timestamp }` | A conversation message (from user or assistant). `role` is `"user"` or `"assistant"`. `timestamp` is milliseconds since epoch. |
| `message` | `{ id?, role, content/text, isFinal?, output? }` | Streaming message event. Used for word-by-word AI responses. |

#### Speaking Status

| Event | Payload | Description |
|-------|---------|-------------|
| `speaking-status-changed` | `{ status }` | Unified speaking event. `status` is one of: `"user-speaking"`, `"user-stopped"`, `"ai-speaking"`, `"ai-stopped"`. |
| `user-started-speaking` | — | The user's microphone detected speech. |
| `user-stopped-speaking` | — | The user stopped speaking. |
| `ai-started-speaking` | — | The AI began audio playback. |
| `ai-stopped-speaking` | — | The AI finished audio playback. |

#### Audio & Transcript

| Event | Payload | Description |
|-------|---------|-------------|
| `volume-changed` | `{ volume, isAi }` | Audio level update. `volume` is dBFS (double). `isAi` is boolean — `true` for AI output, `false` for user input. |
| `transcript-update` | `{ text }` | Partial speech-to-text transcript while the user is speaking. |

#### Participant Events

| Event | Payload | Description |
|-------|---------|-------------|
| `participant-joined` | `{ clientId, name, ... }` | A participant joined the room. |
| `participant-left` | `{ clientId, ... }` | A participant left the room. |
| `participant-removed` | `{ clientId, ... }` | A participant was removed by the host. |
| `participants-updated` | `{ participants: [...] }` | Full participant list update. |

#### Host Control Responses

| Event | Payload | Description |
|-------|---------|-------------|
| `you-were-muted` | `{ ... }` | You were muted by the host. |
| `you-were-removed` | `{ ... }` | You were removed from the room by the host. |
| `all-muted` | `{ ... }` | All participants were muted. |
| `all-unmuted` | `{ ... }` | All participants were unmuted. |
| `host-changed` | `{ newHostClientId, ... }` | The host role was transferred. Compare with your socket ID to determine if you are the new host. |
| `meeting-ended` | `{ ... }` | The meeting was ended by the host. |
| `room-locked-changed` | `{ locked }` | Room lock status changed. |

#### Transcription Events

| Event | Payload | Description |
|-------|---------|-------------|
| `transcription-toggled` | `{ enabled }` | Live transcription was enabled or disabled. |
| `live-transcription` | `{ speaker, text, timestamp, ... }` | A live transcription entry. |

#### AI Analysis Events

| Event | Payload | Description |
|-------|---------|-------------|
| `ask-ai-started` | `{ ... }` | AI voice analysis started. |
| `ask-ai-processing` | — | AI is processing the analysis. |
| `ask-ai-cancelled` | `{ ... }` | AI analysis was cancelled. |
| `ask-ai-text-started` | `{ ... }` | Text-only AI query started. |
| `ask-ai-text-chunk` | `{ token }` | Streaming text chunk from AI text response. |
| `ask-ai-text-response` | `{ text }` | Complete text response from AI. |
| `ask-ai-text-error` | `{ error }` | AI text query failed. |

#### Waiting Room Events

| Event | Payload | Description |
|-------|---------|-------------|
| `waiting-room` | `{ ... }` | You have been placed in the waiting room. |
| `admitted` | `{ ... }` | You were admitted from the waiting room. |
| `denied` | `{ ... }` | You were denied entry from the waiting room. |
| `waiting-room-updated` | `{ entries: [...] }` | The waiting room list changed (host only). |
| `waiting-room-toggled` | `{ enabled }` | Waiting room was enabled or disabled. |

#### Summary & Minutes Events

| Event | Payload | Description |
|-------|---------|-------------|
| `summary-generating` | `{ ... }` | Summary generation in progress. |
| `summary-generated` | `{ summary }` | Summary generation complete. |
| `minutes-generating` | `{ ... }` | Minutes generation in progress. |
| `minutes-generated` | `{ minutes }` | Minutes generation complete. |

#### Bookmark Events

| Event | Payload | Description |
|-------|---------|-------------|
| `bookmark-added` | `{ id, label, isActionItem, timestamp, ... }` | A bookmark was added. |
| `bookmark-removed` | `{ bookmarkId }` | A bookmark was removed. |

#### Error Events

| Event | Payload | Description |
|-------|---------|-------------|
| `server-error` | `{ message }` | A server-side error occurred. |
| `transport-error` | `{ error, id }` | WebRTC transport failed on the server. |
| `producer-error` | `{ error }` | WebRTC producer failed on the server. |

#### Socket Lifecycle

| Event | Type | Description |
|-------|------|-------------|
| `connect` | Client event | Socket connected successfully. |
| `disconnect` | Client event | Socket disconnected. |
| `reconnect` | Client event | Socket reconnected after a drop. |
| `error` | Client event | Socket-level error. |
| `statusChange` | Client event | Socket connection status changed (logged for debugging). |
