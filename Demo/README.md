# Rocs Chat – iOS Demo

A SwiftUI demo showing how to integrate the Rocs iOS SDK into an
iPhone or iPad application.

## Prerequisites

- Xcode 15+
- iOS 16.0+ deployment target
- Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Git access to the private conference SDK repository:
  - `https://gitlab-eu.avrioc.io/comera/mobile-apps/ios/conference-sdk-ios-release.git`
- A running Rocs media server

## Setup

### 1. Generate the Xcode project

```bash
cd ios/Demo
xcodegen generate
```

This reads `project.yml` and creates `VoiceChatDemo.xcodeproj`.

### 2. Open in Xcode

```bash
open VoiceChatDemo.xcodeproj
```

Xcode will automatically resolve SPM dependencies:

| Package | Source | Version |
|---------|--------|---------|
| **RocsSDK** | Local (`../`) | — |
| **WebRTC** | GitHub `stasel/WebRTC` | 149.0.0 |
| **JitsiMeetSDK** | GitLab `conference-sdk-ios-release` | 11.6.4 |
| **GiphyUISDK** | GitHub `giphy-ios-sdk` | 2.2.4 |
| **SocketIO** | GitHub `socket.io-client-swift` | 16.1.0+ |

### 3. Configure server URL

Edit `Sources/Config.swift` and update the server list, `appKey`, and `userId`
for your environment.

### 4. Run

Select your device and press **⌘R**.

> **Note:** WebRTC does not work in the iOS Simulator for audio/video capture.
> Use a real device for full functionality.

## Project Structure

```
Sources/
  Config.swift         – Server URL and app key constants
  VoiceChatApp.swift   – SwiftUI @main entry point
  ContentView.swift    – Main chat UI
  ChatViewModel.swift  – Observable ViewModel wrapping RocsClient
```

## Features

- Connect / disconnect from the media server
- Start and end voice conversations
- Display real-time conversation messages
- Mute / unmute microphone
- Enable / disable camera video
- Speaking status indicator (user / AI)
- Error handling with dismissable banners
