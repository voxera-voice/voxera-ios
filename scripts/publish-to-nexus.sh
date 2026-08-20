#!/bin/bash
set -e

# RocsSDK - Publish to Nexus SPM Registry
# =========================================
# This script publishes the RocsSDK package to your Nexus repository
#
# Prerequisites:
#   - Git tag created for the version
#   - Nexus credentials configured via environment variables
#
# Usage:
#   export NEXUS_URL="https://your-nexus-server.com"
#   export NEXUS_REPO="swift-hosted"
#   export NEXUS_USER="your-username"
#   export NEXUS_PASS="your-password"
#   ./scripts/publish-to-nexus.sh
#
# Or pass version explicitly:
#   ./scripts/publish-to-nexus.sh 1.0.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration from environment
NEXUS_URL="${NEXUS_URL}"
NEXUS_REPO="${NEXUS_REPO}"
NEXUS_USER="${NEXUS_USER}"
NEXUS_PASS="${NEXUS_PASS}"

# Validate required environment variables
if [ -z "$NEXUS_URL" ]; then
  echo -e "${RED}❌ Error: NEXUS_URL environment variable not set${NC}"
  echo "   export NEXUS_URL='https://your-nexus-server.com'"
  exit 1
fi

if [ -z "$NEXUS_REPO" ]; then
  echo -e "${RED}❌ Error: NEXUS_REPO environment variable not set${NC}"
  echo "   export NEXUS_REPO='swift-hosted'"
  exit 1
fi

if [ -z "$NEXUS_USER" ]; then
  echo -e "${RED}❌ Error: NEXUS_USER environment variable not set${NC}"
  echo "   export NEXUS_USER='your-username'"
  exit 1
fi

if [ -z "$NEXUS_PASS" ]; then
  echo -e "${RED}❌ Error: NEXUS_PASS environment variable not set${NC}"
  echo "   export NEXUS_PASS='your-password'"
  exit 1
fi

# Get version
if [ -n "$1" ]; then
  # Version passed as argument
  VERSION="$1"
  echo -e "${BLUE}📌 Using version from argument: ${VERSION}${NC}"
else
  # Get version from git tag
  VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Error: No git tag found and no version argument provided${NC}"
    echo ""
    echo "Please create a git tag first:"
    echo "  git tag -a 1.0.0 -m 'Release 1.0.0'"
    echo "  git push origin 1.0.0"
    echo ""
    echo "Or pass version as argument:"
    echo "  ./scripts/publish-to-nexus.sh 1.0.0"
    exit 1
  fi
  VERSION=${VERSION#v}  # Remove 'v' prefix if exists
  echo -e "${BLUE}📌 Using version from git tag: ${VERSION}${NC}"
fi

# Validate version format (basic semver check)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo -e "${YELLOW}⚠️  Warning: Version '${VERSION}' doesn't match semantic versioning (e.g., 1.0.0)${NC}"
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo ""
echo -e "${BLUE}📦 Publishing RocsSDK version ${VERSION} to Nexus...${NC}"
echo "   Server: ${NEXUS_URL}"
echo "   Repository: ${NEXUS_REPO}"
echo "   User: ${NEXUS_USER}"
echo ""

# Ensure we're in the right directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}/.."

# Verify Package.swift exists
if [ ! -f "Package.swift" ]; then
  echo -e "${RED}❌ Error: Package.swift not found in current directory${NC}"
  echo "   Current dir: $(pwd)"
  exit 1
fi

# Create archive
ARCHIVE_NAME="RocsSDK-${VERSION}.zip"
echo -e "${BLUE}📁 Creating archive: ${ARCHIVE_NAME}${NC}"

git archive --format=zip --prefix="RocsSDK-${VERSION}/" HEAD > "$ARCHIVE_NAME"

if [ ! -f "$ARCHIVE_NAME" ]; then
  echo -e "${RED}❌ Error: Failed to create archive${NC}"
  exit 1
fi

ARCHIVE_SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
echo -e "${GREEN}✅ Created archive: ${ARCHIVE_NAME} (${ARCHIVE_SIZE})${NC}"

# Upload to Nexus
UPLOAD_URL="${NEXUS_URL}/repository/${NEXUS_REPO}/RocsSDK/${VERSION}/${ARCHIVE_NAME}"

echo ""
echo -e "${BLUE}⬆️  Uploading to Nexus...${NC}"
echo "   URL: ${UPLOAD_URL}"

HTTP_CODE=$(curl -w "%{http_code}" -s -o /tmp/nexus-upload-response.txt \
  -u "${NEXUS_USER}:${NEXUS_PASS}" \
  --upload-file "$ARCHIVE_NAME" \
  "$UPLOAD_URL")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo ""
  echo -e "${GREEN}✅ Successfully published RocsSDK ${VERSION} to Nexus!${NC}"
  echo ""
  echo "   Download URL:"
  echo "   ${UPLOAD_URL}"
  echo ""
  echo "   To use in Package.swift:"
  echo "   .package(url: \"${NEXUS_URL}/repository/${NEXUS_REPO}/RocsSDK.git\", from: \"${VERSION}\")"
  echo ""
else
  echo ""
  echo -e "${RED}❌ Failed to publish to Nexus${NC}"
  echo "   HTTP Status Code: ${HTTP_CODE}"
  echo "   Response:"
  cat /tmp/nexus-upload-response.txt
  echo ""
  exit 1
fi

# Cleanup
rm "$ARCHIVE_NAME"
rm -f /tmp/nexus-upload-response.txt
echo -e "${GREEN}🧹 Cleaned up temporary files${NC}"

echo ""
echo -e "${GREEN}🎉 Deployment complete!${NC}"
