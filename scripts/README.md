# RocsSDK Build & Publish Scripts

Collection of automation scripts for building, verifying, and publishing RocsSDK to Nexus SPM registry.

---

## Scripts

### 1. `build.sh` - Build Verification

Verifies that the SDK builds successfully for all iOS platforms (Simulator + Device).

**Usage:**

```bash
# Standard build
./scripts/build.sh

# Clean build (removes .build and DerivedData)
./scripts/build.sh --clean
```

**What it does:**

- ✅ Validates `Package.swift` structure
- ✅ Resolves Swift package dependencies
- ✅ Builds for iOS Simulator (arm64)
- ✅ Builds for iOS Simulator (x86_64, if available)
- ✅ Builds for iOS Device (arm64)
- ✅ Displays package information

**Requirements:**

- Xcode 15.0+ installed
- `../webrtc-ios-release` dependency available

---

### 2. `publish-to-nexus.sh` - Nexus Publishing

Publishes the SDK package to your Nexus SPM repository.

**Usage:**

```bash
# Set environment variables
export NEXUS_URL="https://your-nexus-server.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"

# Publish using git tag version
./scripts/publish-to-nexus.sh

# Or specify version explicitly
./scripts/publish-to-nexus.sh 1.0.0
```

**What it does:**

- 📌 Detects version from git tag (or uses provided version)
- 📦 Creates archive from current HEAD
- ⬆️ Uploads to Nexus repository
- ✅ Validates upload success
- 🧹 Cleans up temporary files

**Prerequisites:**

- Git tag created: `git tag -a 1.0.0 -m 'Release 1.0.0'`
- Nexus credentials configured
- Valid Nexus SPM repository

**Environment Variables:**

| Variable | Description | Example |
|----------|-------------|---------|
| `NEXUS_URL` | Nexus server URL | `https://nexus.example.com` |
| `NEXUS_REPO` | Repository name | `swift-hosted` |
| `NEXUS_USER` | Nexus username | `deploy-user` |
| `NEXUS_PASS` | Nexus password/token | `your-secure-token` |

---

## Typical Workflow

### 1. Development & Testing

```bash
# Make changes to SDK
# ...

# Verify build
./scripts/build.sh --clean
```

### 2. Create Release

```bash
# Update version in code/docs if needed
# Commit changes
git add .
git commit -m "Release 1.0.0"

# Create and push tag
git tag -a 1.0.0 -m "Release version 1.0.0"
git push origin main
git push origin 1.0.0
```

### 3. Publish to Nexus

```bash
# Set credentials (one-time, or use .env file)
export NEXUS_URL="https://nexus.example.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"

# Publish
./scripts/publish-to-nexus.sh
```

### 4. Consume from Nexus

```swift
// Add to Package.swift
dependencies: [
    .package(
        url: "https://nexus.example.com/repository/swift-hosted/RocsSDK.git",
        from: "1.0.0"
    )
]
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build & Publish

on:
  push:
    tags:
      - '*.*.*'

jobs:
  build-and-publish:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify Build
        run: ./scripts/build.sh
      
      - name: Publish to Nexus
        env:
          NEXUS_URL: ${{ secrets.NEXUS_URL }}
          NEXUS_REPO: ${{ secrets.NEXUS_REPO }}
          NEXUS_USER: ${{ secrets.NEXUS_USER }}
          NEXUS_PASS: ${{ secrets.NEXUS_PASS }}
        run: ./scripts/publish-to-nexus.sh
```

---

## Troubleshooting

### Build Script Issues

**Error: "Package.swift not found"**

Make sure you're running from the `sdk-ios` directory or the scripts are in `sdk-ios/scripts/`.

**Error: "../webrtc-ios-release directory not found"**

Clone the dependency to sibling directory:

```bash
cd /path/to/packages
git clone <repo-url>/webrtc-ios-release.git
```

**Error: "iOS Simulator build failed"**

Check Xcode version (requires 15.0+):

```bash
xcodebuild -version
```

### Publish Script Issues

**Error: "NEXUS_URL environment variable not set"**

Set required environment variables:

```bash
export NEXUS_URL="https://your-nexus.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="username"
export NEXUS_PASS="password"
```

**Error: "No git tag found"**

Create a git tag first:

```bash
git tag -a 1.0.0 -m "Release 1.0.0"
```

Or pass version explicitly:

```bash
./scripts/publish-to-nexus.sh 1.0.0
```

**HTTP 401 Unauthorized**

Verify credentials:

```bash
curl -u "$NEXUS_USER:$NEXUS_PASS" "$NEXUS_URL/service/rest/v1/status"
```

**HTTP 404 Not Found**

Check repository name and ensure Swift SPM plugin is installed in Nexus.

---

## Security Notes

**Never commit credentials to git!**

Use one of these approaches:

1. **Environment variables** (recommended for CI/CD)
2. **`.env` file** (add to `.gitignore`)
3. **Keychain on macOS**
4. **Secrets manager** (Vault, AWS Secrets Manager, etc.)

Example `.env` file:

```bash
# .env
export NEXUS_URL="https://nexus.example.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="deploy-user"
export NEXUS_PASS="secure-token-here"
```

Load before publishing:

```bash
source .env
./scripts/publish-to-nexus.sh
```

---

## Additional Resources

- [Main Deployment Guide](../DEPLOYMENT.md)
- [SDK Documentation](../DOCUMENTATION.md)
- [Usage Examples](../README.md)
