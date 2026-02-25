#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔐 Notarizing Conversation Assistant DMG${NC}"

# Configuration
DMG_NAME="ConversationAssistant-v1.0.0"
BUILD_DIR="build"
DMG_FILE="${BUILD_DIR}/${DMG_NAME}.dmg"
BUNDLE_ID="com.nikolayprosenikov.conversationassistant"
APPLE_ID="${APPLE_ID:?Set APPLE_ID env var (your Apple ID email)}"
TEAM_ID="${TEAM_ID:?Set TEAM_ID env var (your Apple Developer Team ID)}"
KEYCHAIN_PROFILE="notarytool-password"

# Check if DMG exists
if [ ! -f "${DMG_FILE}" ]; then
    echo -e "${RED}❌ Error: ${DMG_FILE} not found!${NC}"
    echo "Run ./create-dmg.sh first"
    exit 1
fi

# Check if notarytool credentials are stored
echo -e "\n${YELLOW}Checking for notarytool credentials...${NC}"
if ! xcrun notarytool history --keychain-profile "${KEYCHAIN_PROFILE}" &> /dev/null; then
    echo -e "${RED}❌ No credentials found for profile '${KEYCHAIN_PROFILE}'${NC}"
    echo -e "\n${BLUE}Setting up notarytool credentials...${NC}"
    echo "You'll need:"
    echo "  1. Your Apple ID email"
    echo "  2. An app-specific password (NOT your Apple ID password)"
    echo "  3. Your Team ID"
    echo ""
    echo -e "${YELLOW}To create an app-specific password:${NC}"
    echo "  1. Go to https://appleid.apple.com"
    echo "  2. Sign in with your Apple ID"
    echo "  3. Go to 'Security' section"
    echo "  4. Under 'App-Specific Passwords', click 'Generate password...'"
    echo "  5. Enter a label like 'Notarization Tool'"
    echo "  6. Copy the generated password"
    echo ""
    read -p "Press Enter when you have your app-specific password ready..."

    xcrun notarytool store-credentials "${KEYCHAIN_PROFILE}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${TEAM_ID}" \
        --password

    echo -e "${GREEN}✅ Credentials stored successfully!${NC}"
fi

# Upload to Apple for notarization
echo -e "\n${YELLOW}Uploading DMG to Apple notary service...${NC}"
echo "This may take a few minutes..."

SUBMISSION_OUTPUT=$(xcrun notarytool submit "${DMG_FILE}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait)

echo "${SUBMISSION_OUTPUT}"

# Check if successful
if echo "${SUBMISSION_OUTPUT}" | grep -q "status: Accepted"; then
    echo -e "\n${GREEN}✅ Notarization successful!${NC}"

    # Staple the notarization ticket
    echo -e "\n${YELLOW}Stapling notarization ticket to DMG...${NC}"
    xcrun stapler staple "${DMG_FILE}"

    # Verify stapling
    echo -e "\n${YELLOW}Verifying stapled ticket...${NC}"
    xcrun stapler validate "${DMG_FILE}"

    echo -e "\n${GREEN}🎉 Success! Your DMG is fully notarized and ready to distribute!${NC}"
    echo -e "DMG location: ${DMG_FILE}"

    # Test on another machine or with Gatekeeper
    echo -e "\n${BLUE}To test:${NC}"
    echo "1. Copy ${DMG_FILE} to another Mac (or Downloads folder)"
    echo "2. Open the DMG and drag the app to Applications"
    echo "3. Try to open it - it should open without warnings"

elif echo "${SUBMISSION_OUTPUT}" | grep -q "status: Invalid"; then
    echo -e "\n${RED}❌ Notarization failed!${NC}"

    # Get submission ID and show log
    SUBMISSION_ID=$(echo "${SUBMISSION_OUTPUT}" | grep "id:" | head -1 | awk '{print $2}')
    if [ -n "${SUBMISSION_ID}" ]; then
        echo -e "\n${YELLOW}Fetching detailed error log...${NC}"
        xcrun notarytool log "${SUBMISSION_ID}" \
            --keychain-profile "${KEYCHAIN_PROFILE}"
    fi

    exit 1
else
    echo -e "\n${RED}❌ Unexpected notarization status${NC}"
    echo "${SUBMISSION_OUTPUT}"
    exit 1
fi
