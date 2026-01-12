#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔨 Building Conversation Assistant for Release${NC}"

# Configuration
DEVELOPER_ID="Developer ID Application: Nikolay Prosenikov (2Q562K9C7N)"
APP_NAME="ConversationAssistant"
BUNDLE_ID="com.nikolayprosenikov.conversationassistant"
VERSION="1.0.0"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
ENTITLEMENTS="ConversationAssistant.entitlements"

# Step 1: Build the Swift binary
echo -e "\n${YELLOW}Step 1: Compiling Swift binary${NC}"
swiftc conversation_assistant.swift \
    Domain/Entities/Screenshot.swift \
    Domain/ValueObjects/AnalysisMode.swift \
    Domain/ValueObjects/Tab.swift \
    Domain/Model/AppSettings.swift \
    Domain/Model/ConversationContext.swift \
    Domain/Model/ConversationMessage.swift \
    Domain/Model/DataSourceConfig.swift \
    Domain/Model/ValueObjects/ScreenshotId.swift \
    Infrastructure/Capture/ScreenCaptureService.swift \
    Infrastructure/Capture/MacScreenCapture.swift \
    Infrastructure/API/AnthropicClient.swift \
    Infrastructure/API/OpenAIClient.swift \
    Infrastructure/Speech/VADAudioRecorder.swift \
    Infrastructure/Speech/SystemAudioCapture.swift \
    Infrastructure/Speech/GroqSpeechClient.swift \
    Infrastructure/QADatabase.swift \
    Infrastructure/Storage/ApiKeyManager.swift \
    Infrastructure/Tools/ToolDefinitions.swift \
    Infrastructure/Tools/ToolProtocol.swift \
    Infrastructure/Tools/ToolExecutor.swift \
    Infrastructure/Tools/Clients/ConfluenceClient.swift \
    Infrastructure/Tools/Clients/JiraClient.swift \
    Infrastructure/Tools/Clients/GitHubClient.swift \
    Infrastructure/Tools/Clients/DatabaseClient.swift \
    Infrastructure/Tools/Clients/WebSearchClient.swift \
    Infrastructure/Auth/OAuthConfig.swift \
    Infrastructure/Auth/OAuthManager.swift \
    Presentation/Settings/SettingsWindowController.swift \
    Presentation/Styling/SyntaxHighlighter.swift \
    Presentation/Styling/MarkdownRenderer.swift \
    Presentation/Windows/ScreenshotAlertWindow.swift \
    Presentation/Windows/WindowFactory.swift \
    Presentation/Onboarding/PermissionsOnboardingWindow.swift \
    Presentation/Onboarding/AtlassianOnboardingWindow.swift \
    -o "${BUILD_DIR}/${APP_NAME}" \
    -O \
    -whole-module-optimization \
    -target arm64-apple-macosx14.0 \
    -framework Cocoa \
    -framework Carbon \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework Speech \
    -framework Security

# Step 2: Create app bundle structure
echo -e "\n${YELLOW}Step 2: Creating app bundle${NC}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Move binary to app bundle
mv "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Privacy Manifest
if [ -f "PrivacyInfo.xcprivacy" ]; then
    cp "PrivacyInfo.xcprivacy" "${APP_BUNDLE}/Contents/Resources/"
    echo "  ✓ Added Privacy Manifest"
fi

# Step 3: Create Info.plist
echo -e "\n${YELLOW}Step 3: Creating Info.plist${NC}"
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Conversation Assistant</string>
    <key>CFBundleDisplayName</key>
    <string>Conversation Assistant</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>

    <!-- URL Scheme for OAuth callbacks -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.nikolayprosenikov.conversationassistant</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>conversationassistant</string>
            </array>
        </dict>
    </array>

    <!-- App Store Required -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Nikolay Prosenikov. All rights reserved.</string>

    <!-- Privacy Usage Descriptions (Required for App Store) -->
    <key>NSScreenCaptureUsageDescription</key>
    <string>Conversation Assistant needs screen recording permission to capture screenshots for AI-powered analysis.</string>
</dict>
</plist>
EOF

# Step 4: Code sign the app with hardened runtime
echo -e "\n${YELLOW}Step 4: Code signing with hardened runtime${NC}"
echo "Using certificate: ${DEVELOPER_ID}"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo -e "${RED}❌ Error: No Developer ID Application certificate found!${NC}"
    echo -e "${YELLOW}To get a certificate:${NC}"
    echo "1. Go to https://developer.apple.com/account/resources/certificates/list"
    echo "2. Click '+' to create a new certificate"
    echo "3. Select 'Developer ID Application'"
    echo "4. Download and install the certificate"
    echo "5. Run: security find-identity -v -p codesigning"
    exit 1
fi

codesign --force \
    --sign "${DEVELOPER_ID}" \
    --entitlements "${ENTITLEMENTS}" \
    --options runtime \
    --timestamp \
    --deep \
    "${APP_BUNDLE}"

# Verify signature
echo -e "\n${YELLOW}Verifying code signature...${NC}"
codesign --verify --verbose=4 "${APP_BUNDLE}"

echo -e "\n${GREEN}✅ App signed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Create DMG: ./create-dmg.sh"
echo "2. Notarize: ./notarize.sh"
