#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}📦 Creating DMG for Conversation Assistant${NC}"

# Configuration
APP_NAME="ConversationAssistant"
DMG_NAME="ConversationAssistant-v1.0.0"
VOLUME_NAME="Conversation Assistant"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_FILE="${BUILD_DIR}/${DMG_NAME}.dmg"
DEVELOPER_ID="Developer ID Application: Nikolay Prosenikov (2Q562K9C7N)"

# Check if app exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo -e "${RED}❌ Error: ${APP_BUNDLE} not found!${NC}"
    echo "Run ./build-release.sh first"
    exit 1
fi

# Clean up previous DMG
rm -rf "${DMG_DIR}"
rm -f "${DMG_FILE}"
mkdir -p "${DMG_DIR}"

# Copy app to DMG staging directory
echo -e "\n${YELLOW}Copying app to DMG staging directory...${NC}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"

# Create Applications symlink
echo -e "${YELLOW}Creating Applications symlink...${NC}"
ln -s /Applications "${DMG_DIR}/Applications"

# Create temporary DMG
echo -e "\n${YELLOW}Creating DMG image...${NC}"
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_FILE}"

# Sign the DMG
echo -e "\n${YELLOW}Signing DMG...${NC}"
codesign --force \
    --sign "${DEVELOPER_ID}" \
    --timestamp \
    "${DMG_FILE}"

# Verify DMG signature
echo -e "\n${YELLOW}Verifying DMG signature...${NC}"
codesign --verify --verbose=4 "${DMG_FILE}"

# Display DMG info
echo -e "\n${GREEN}✅ DMG created successfully!${NC}"
echo -e "Location: ${DMG_FILE}"
ls -lh "${DMG_FILE}"

echo -e "\n${YELLOW}Next step: Notarize the DMG${NC}"
echo "./notarize.sh"
