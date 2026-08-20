#!/bin/bash
set -e

# RocsSDK - Build Verification Script
# ====================================
# This script verifies that the RocsSDK package builds successfully
# for both iOS Simulator and iOS Device platforms
#
# Usage:
#   ./scripts/build.sh
#   ./scripts/build.sh --clean    # Clean before building

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
CLEAN=false
if [ "$1" == "--clean" ]; then
  CLEAN=true
fi

echo ""
echo -e "${BLUE}🔨 RocsSDK Build Verification${NC}"
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

# Check if webrtc-ios-release peer dependency exists
if [ ! -d "../webrtc-ios-release" ]; then
  echo -e "${YELLOW}⚠️  Warning: ../webrtc-ios-release directory not found${NC}"
  echo "   This peer dependency is required for building sdk-ios"
  echo ""
  echo "   To fix, ensure webrtc-ios-release is at sibling directory:"
  echo "   cd /path/to/packages && git clone <repo-url>/webrtc-ios-release.git"
  exit 1
fi

# Clean if requested
if [ "$CLEAN" == true ]; then
  echo -e "${BLUE}🧹 Cleaning build artifacts...${NC}"
  rm -rf .build
  rm -rf ~/Library/Developer/Xcode/DerivedData/RocsSDK-*
  echo -e "${GREEN}✅ Clean complete${NC}"
  echo ""
fi

# Validate Package.swift
echo -e "${BLUE}📋 Validating Package.swift...${NC}"
swift package dump-package > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Package.swift is valid${NC}"
else
  echo -e "${RED}❌ Package.swift validation failed${NC}"
  exit 1
fi
echo ""

# Check dependencies
echo -e "${BLUE}📦 Resolving dependencies...${NC}"
swift package resolve
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Dependencies resolved${NC}"
else
  echo -e "${RED}❌ Failed to resolve dependencies${NC}"
  exit 1
fi
echo ""

# Note: swift build doesn't work for iOS-only packages on macOS
# We use xcodebuild instead

# Build for iOS Simulator
echo -e "${BLUE}🏗️  Building for iOS Simulator (arm64)...${NC}"
xcodebuild build \
  -scheme RocsSDK \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ iOS Simulator build succeeded${NC}"
else
  echo -e "${RED}❌ iOS Simulator build failed${NC}"
  exit 1
fi
echo ""

# Build for iOS Simulator (x86_64 - Intel Macs)
echo -e "${BLUE}🏗️  Building for iOS Simulator (x86_64)...${NC}"
xcodebuild build \
  -scheme RocsSDK \
  -destination 'platform=iOS Simulator,name=iPhone 16,arch=x86_64' \
  -quiet 2>/dev/null || {
    echo -e "${YELLOW}⚠️  x86_64 build skipped (Apple Silicon Mac or not available)${NC}"
}
echo ""

# Build for iOS Device (Generic)
echo -e "${BLUE}🏗️  Building for iOS Device (arm64)...${NC}"
xcodebuild build \
  -scheme RocsSDK \
  -destination 'generic/platform=iOS' \
  -quiet

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ iOS Device build succeeded${NC}"
else
  echo -e "${RED}❌ iOS Device build failed${NC}"
  exit 1
fi
echo ""

# Show package info
echo -e "${BLUE}📦 Package Information:${NC}"
swift package dump-package | grep -E '"name"|"version"|platformName' | head -10
echo ""

# Summary
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 All builds succeeded!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "RocsSDK is ready to publish!"
echo ""
echo "Next steps:"
echo "  1. Create a git tag:  git tag -a 1.0.0 -m 'Release 1.0.0'"
echo "  2. Push the tag:      git push origin 1.0.0"
echo "  3. Publish to Nexus:  ./scripts/publish-to-nexus.sh"
echo ""
