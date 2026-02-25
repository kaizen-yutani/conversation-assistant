#!/bin/bash
cd "$(dirname "$0")"

APP_NAME="ConversationAssistant"
APP_BUNDLE="${APP_NAME}.app"
SECONDS=0

# Spinner for long-running background commands
spin() {
    local pid=$1 msg=$2
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$SECONDS
        printf "\r  \033[36m%s\033[0m %s \033[2m(%ds)\033[0m   " "${chars:i%${#chars}:1}" "$msg" "$elapsed"
        i=$((i + 1))
        sleep 0.08
    done
    wait "$pid"
    local rc=$?
    printf "\r\033[K"
    return $rc
}

# Count source files
SRC_COUNT=$(ls conversation_assistant.swift \
    Domain/ValueObjects/Tab.swift \
    Domain/ValueObjects/AnalysisMode.swift \
    Domain/Model/AppSettings.swift \
    Domain/Model/Constants.swift \
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
    Infrastructure/Speech/SileroVADRecorder.swift \
    Infrastructure/Speech/SystemAudioCapture.swift \
    Infrastructure/Speech/GroqSpeechClient.swift \
    Infrastructure/Speech/DeepgramStreamingClient.swift \
    Infrastructure/Speech/StreamingSystemAudioCapture.swift \
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
    Presentation/Timeline/MessageViewFactory.swift \
    Presentation/Timeline/StreamingMessageHandler.swift 2>/dev/null | wc -l | tr -d ' ')

# Compile in background
swiftc -o "${APP_NAME}" \
    conversation_assistant.swift \
    Domain/ValueObjects/Tab.swift \
    Domain/ValueObjects/AnalysisMode.swift \
    Domain/Model/AppSettings.swift \
    Domain/Model/Constants.swift \
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
    Infrastructure/Speech/SileroVADRecorder.swift \
    Infrastructure/Speech/SystemAudioCapture.swift \
    Infrastructure/Speech/GroqSpeechClient.swift \
    Infrastructure/Speech/DeepgramStreamingClient.swift \
    Infrastructure/Speech/StreamingSystemAudioCapture.swift \
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
    Presentation/Timeline/MessageViewFactory.swift \
    Presentation/Timeline/StreamingMessageHandler.swift \
    -framework Cocoa \
    -framework Carbon \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework Speech \
    -framework Security \
    -framework Network \
    -framework CoreML \
    -framework Accelerate &

spin $! "Compiling ${SRC_COUNT} Swift files..."

if [ $? -ne 0 ]; then
    echo "  ❌ Build failed"
    exit 1
fi

echo "  ✅ Compiled in ${SECONDS}s"

# Create app bundle
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mv "${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Silero VAD model
if [ -d "SileroVAD.mlmodelc" ]; then
    cp -r SileroVAD.mlmodelc "${APP_BUNDLE}/Contents/Resources/"
    echo "  ✅ Bundled SileroVAD model"
fi

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
    <key>NSMicrophoneUsageDescription</key>
    <string>Conversation Assistant needs microphone access to transcribe your voice in real-time.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Conversation Assistant needs screen recording access to capture system audio from Zoom, Teams, and other apps.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Conversation Assistant uses speech recognition to transcribe conversations.</string>
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

# Sign the app to maintain consistent identity for macOS permissions
DEVELOPER_ID="${DEVELOPER_ID:-}"
ENTITLEMENTS="ConversationAssistant.entitlements"

# Auto-detect signing identity from keychain if not explicitly set
if [ -z "$DEVELOPER_ID" ]; then
    DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi

if [ -n "$DEVELOPER_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEVELOPER_ID"; then
    codesign --force --deep --sign "$DEVELOPER_ID" --entitlements "$ENTITLEMENTS" --options runtime "${APP_BUNDLE}" 2>/dev/null
    echo "  ✅ Signed with: $DEVELOPER_ID"
else
    # Ad-hoc sign as last resort (permissions may reset on each rebuild)
    codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null
    echo "  ⚠️  Ad-hoc signed (no Developer ID found — permissions may reset on rebuild)"
fi

echo ""
echo "  ✅ ${APP_BUNDLE} ready (${SECONDS}s)"
open "${APP_BUNDLE}"
