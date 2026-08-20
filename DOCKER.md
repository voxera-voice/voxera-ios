# Docker Publishing Guide

This guide explains how to publish sdk-ios to Nexus using Docker.

## Overview

The Docker build process:
1. Uses Alpine Linux with git and curl
2. Creates a git archive (zip) of the package
3. Uploads to Nexus using curl with authentication
4. All in one `docker build` command

## Prerequisites

- Docker installed
- Git tag created for the version
- Nexus credentials

## Publishing Workflow

### 1. Publish WebRTC First (Required)

```bash
cd /path/to/packages/webrtc-ios-release

# Build and publish WebRTC
docker build \
  --build-arg REPOSITORY="https://nexus.example.com/repository/swift-hosted" \
  --build-arg USERNAME="your-username" \
  --build-arg PASSWORD="your-password" \
  --build-arg VERSION="1.0.0" \
  -t webrtc-publisher:1.0.0 \
  .

# Cleanup
docker rmi webrtc-publisher:1.0.0
```

### 2. Update sdk-ios Package.swift

After WebRTC is published, update `Package.swift` to reference WebRTC from Nexus:

```swift
// Change from:
.package(path: "../webrtc-ios-release")

// To:
.package(
    url: "https://nexus.example.com/repository/swift-hosted/WebRTC",
    from: "1.0.0"
)

// Also update package references in targets:
// "webrtc-ios-release" → "WebRTC"
```

Commit the change:
```bash
git add Package.swift
git commit -m "Configure WebRTC Nexus URL"
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin main 1.0.0
```

### 3. Publish sdk-ios

```bash
cd /path/to/packages/sdk-ios

# Build and publish sdk-ios
docker build \
  --build-arg REPOSITORY="https://nexus.example.com/repository/swift-hosted" \
  --build-arg USERNAME="your-username" \
  --build-arg PASSWORD="your-password" \
  --build-arg VERSION="1.0.0" \
  -t sdk-ios-publisher:1.0.0 \
  .

# Cleanup
docker rmi sdk-ios-publisher:1.0.0
```

## Using Environment Variables

```bash
# Set credentials once
export NEXUS_URL="https://nexus.example.com"
export NEXUS_REPO="swift-hosted"
export NEXUS_USER="your-username"
export NEXUS_PASS="your-password"
export VERSION="1.0.0"

# Publish WebRTC
cd webrtc-ios-release
docker build \
  --build-arg REPOSITORY="${NEXUS_URL}/repository/${NEXUS_REPO}" \
  --build-arg USERNAME="${NEXUS_USER}" \
  --build-arg PASSWORD="${NEXUS_PASS}" \
  --build-arg VERSION="${VERSION}" \
  -t webrtc-publisher:${VERSION} \
  .

# Publish sdk-ios
cd ../sdk-ios
docker build \
  --build-arg REPOSITORY="${NEXUS_URL}/repository/${NEXUS_REPO}" \
  --build-arg USERNAME="${NEXUS_USER}" \
  --build-arg PASSWORD="${NEXUS_PASS}" \
  --build-arg VERSION="${VERSION}" \
  -t sdk-ios-publisher:${VERSION} \
  .
```

## Jenkins Integration

A `Jenkinsfile` is provided for automated Docker publishing in Jenkins.

### Jenkins Setup

**1. Configure Credentials:**
- ID: `nexus-credentials`
- Type: Username with password
- Username: Your Nexus username
- Password: Your Nexus password

**2. Configure Environment:**
- Add global environment variable: `NEXUS_URL` → `https://nexus.example.com`

**3. Create Pipeline Job:**
- New Item → Pipeline
- Pipeline script from SCM
- Repository: Your git repository
- Script Path: `sdk-ios/Jenkinsfile` (or `webrtc-ios-release/Jenkinsfile`)

**4. Trigger Build:**
```bash
# Tag and push
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin 1.0.0

# Jenkins auto-builds on tag push
```

### Jenkins Pipeline Flow

```groovy
1. Validate version from git tag
2. Build Docker image with Nexus credentials
3. Docker build automatically:
   - Creates git archive
   - Uploads to Nexus
4. Cleanup Docker image
5. Success/failure notification
```

## Dockerfile Explanation

### Key Differences from npm Dockerfile

| Aspect | npm package | Swift (sdk-ios) |
|--------|----------------------------|-----------------|
| Base Image | `node:18-alpine` | `alpine:latest` |
| Tools | npm, jq | git, curl, bash |
| Publish Method | `npm publish` | `curl --upload-file` |
| Auth Config | `.npmrc` file | curl `-u` flag |
| Package Format | npm tarball | git archive zip |

### Dockerfile Structure

```dockerfile
FROM alpine:latest

# Install git + curl + bash
RUN apk add --no-cache git curl bash

# Copy repository
COPY . .

# Accept build arguments
ARG REPOSITORY
ARG USERNAME
ARG PASSWORD
ARG VERSION

# Initialize git if needed (for git archive)
RUN git init && git add -A && git commit

# Create archive
RUN git archive --format=zip ... > RocsSDK-${VERSION}.zip

# Upload to Nexus
RUN curl -u ${USERNAME}:${PASSWORD} --upload-file ... ${NEXUS_URL}
```

## Troubleshooting

### "ERROR: VERSION build arg is required"

**Solution:** Always provide `--build-arg VERSION=x.x.x`

```bash
docker build --build-arg VERSION="1.0.0" ...
```

### "fatal: not a git repository"

**Solution:** Ensure the build context includes `.git` directory, or the Dockerfile initializes git

The Dockerfile auto-initializes git if `.git` is not present.

### Upload fails with authentication error

**Solution:** Verify credentials are correct

```bash
# Test credentials
curl -u "${NEXUS_USER}:${NEXUS_PASS}" "${NEXUS_URL}/service/rest/v1/status"
```

### Large upload timeout (WebRTC)

**Solution:** WebRTC.xcframework is ~1.2GB, uploads may take 5-10 minutes

Increase Docker build timeout or use faster network.

## Verification

### Check Nexus Repository

After publishing, verify in Nexus UI:

**WebRTC:**
```
https://nexus.example.com/#browse/browse:swift-hosted
→ WebRTC/1.0.0/WebRTC-1.0.0.zip
```

**RocsSDK:**
```
https://nexus.example.com/#browse/browse:swift-hosted
→ RocsSDK/1.0.0/RocsSDK-1.0.0.zip
```

### Test Installation

Create test project:

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://nexus.example.com/repository/swift-hosted/RocsSDK",
        from: "1.0.0"
    )
]
```

```bash
swift package resolve
# Should resolve RocsSDK + WebRTC successfully
```

## CI/CD Integration Examples

### GitLab CI

A complete `.gitlab-ci.yml` is provided for GitLab CI/CD.

**Setup GitLab CI/CD Variables:**

Navigate to: Project Settings → CI/CD → Variables

Add the following variables:
- `NEXUS_URL` → `https://nexus.example.com` (masked)
- `NEXUS_USER` → Your Nexus username (masked)
- `NEXUS_PASS` → Your Nexus password (masked, protected)

**Trigger Pipeline:**

```bash
# Tag and push
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin 1.0.0

# GitLab auto-triggers pipeline on tag push
```

**Pipeline Flow:**

```
1. Validate → Check tag exists, extract version
2. Build → Docker build with Nexus credentials
3. Publish → Archive uploaded to Nexus
4. Notify → Success/failure message
```

**View in GitLab:**
- CI/CD → Pipelines → View latest tag pipeline
- Jobs: validate:version, build:docker, publish:nexus

**Manual Example (without CI file):**

```yaml
publish:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build
        --build-arg REPOSITORY="${NEXUS_URL}/repository/swift-hosted"
        --build-arg USERNAME="${NEXUS_USER}"
        --build-arg PASSWORD="${NEXUS_PASS}"
        --build-arg VERSION="${CI_COMMIT_TAG#v}"
        -t sdk-ios-publisher:${CI_COMMIT_TAG}
        .
  only:
    - tags
```

### GitHub Actions

```yaml
- name: Build and Publish
  run: |
    docker build \
      --build-arg REPOSITORY="${{ secrets.NEXUS_URL }}/repository/swift-hosted" \
      --build-arg USERNAME="${{ secrets.NEXUS_USER }}" \
      --build-arg PASSWORD="${{ secrets.NEXUS_PASS }}" \
      --build-arg VERSION="${{ github.ref_name }}" \
      -t sdk-ios-publisher:${{ github.ref_name }} \
      .
```

## References

- [DEPLOYMENT.md](DEPLOYMENT.md) - Complete deployment guide
- [Dockerfile](Dockerfile) - Docker build configuration
- [Jenkinsfile](Jenkinsfile) - Jenkins pipeline definition
- The web-client Dockerfile - npm publishing reference
