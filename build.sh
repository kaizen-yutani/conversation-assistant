#!/bin/bash
cd "$(dirname "$0")"

APP_NAME="ConversationAssistant"
APP_BUNDLE="${APP_NAME}.app"

# Compile
swiftc -o "${APP_NAME}" \
    conversation_assistant.swift \
    Domain/ValueObjects/Tab.swift \
    Domain/ValueObjects/AnalysisMode.swift \
    Domain/Model/AppSettings.swift \
    Domain/Model/ConversationContext.swift \
    Domain/Model/ConversationMessage.swift \
    Domain/Model/DataSourceConfig.swift \
    Domain/Entities/Screenshot.swift \
    Domain/Model/ValueObjects/ScreenshotId.swift \
    Infrastructure/API/AnthropicClient.swift \
    Infrastructure/API/OpenAIClient.swift \
    Infrastructure/Capture/ScreenCaptureService.swift \
    Infrastructure/Capture/MacScreenCapture.swift \
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
    Infrastructure/Auth/OAuthCallbackServer.swift \
    Presentation/Settings/SettingsWindowController.swift \
    Presentation/Styling/SyntaxHighlighter.swift \
    Presentation/Styling/MarkdownRenderer.swift \
    Presentation/Windows/ScreenshotAlertWindow.swift \
    Presentation/Windows/WindowFactory.swift \
    Presentation/Onboarding/PermissionsOnboardingWindow.swift \
    Presentation/Onboarding/AtlassianOnboardingWindow.swift \
    -framework Cocoa \
    -framework Carbon \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework Speech \
    -framework Security \
    -framework Network

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"

# Create app bundle
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mv "${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ConversationAssistant</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikolayprosenikov.conversationassistant</string>
    <key>CFBundleName</key>
    <string>Conversation Assistant</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>conversationassistant</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Sign with Developer ID if available, otherwise skip (preserves permissions)
DEVELOPER_ID="Developer ID Application: Nikolay Prosenikov (2Q562K9C7N)"
ENTITLEMENTS="ConversationAssistant.entitlements"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEVELOPER_ID"; then
    codesign --force --deep --sign "$DEVELOPER_ID" --entitlements "$ENTITLEMENTS" --options runtime "${APP_BUNDLE}" 2>/dev/null
    echo "✅ Signed with Developer ID and entitlements"
else
    echo "⚠️  No Developer ID found - app unsigned (permissions may need re-granting after rebuild)"
fi

echo "✅ App bundle created: ${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
