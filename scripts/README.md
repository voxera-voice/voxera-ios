# VoxeraSDK Build Scripts

Automation for building and verifying the VoxeraSDK Swift package.

---

## Scripts

### `build.sh` — Build Verification

Verifies that the SDK builds successfully for all iOS platforms
(Simulator + Device).

**Usage:**

```bash
# Standard build
./scripts/build.sh

# Clean build (removes .build and DerivedData)
./scripts/build.sh --clean
```

**What it does:**

- Validates `Package.swift` structure
- Resolves Swift package dependencies
- Builds for iOS Simulator (arm64)
- Builds for iOS Simulator (x86_64, if available)
- Builds for iOS Device (arm64)
- Displays package information

**Requirements:**

- Xcode 15.0+

Dependencies resolve from public sources — no registry credentials are needed:

| Dependency | Source |
| --- | --- |
| WebRTC | `github.com/stasel/WebRTC` |
| SocketIO | `github.com/socketio/socket.io-client-swift` |

---

## Publishing

There is no publish script. Swift Package Manager consumes packages directly
from a git URL, so publishing a version is just tagging the repository:

```bash
./scripts/build.sh --clean          # verify first
git tag 1.1.43
git push origin 1.1.43
```

Consumers then depend on it as:

```swift
.package(url: "https://github.com/voxera-voice/voxera-ios.git", from: "1.1.43")
```

For CocoaPods, see `pod trunk push` / private Podspec repo guidance in the
repository-root `RELEASE.md`.
