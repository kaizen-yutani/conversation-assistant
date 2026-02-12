#!/bin/bash
# Simple one-command startup for Conversation Assistant
cd "$(dirname "$0")"

# Compile with optimizations
swiftc -O \
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
    -o ConversationAssistant \
    -framework Cocoa \
    -framework Carbon \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework Speech \
    -framework Security \
    -framework Network \
    -framework CoreML \
    -framework Accelerate

# Run if compilation succeeded
if [ $? -eq 0 ]; then
    echo "✅ Build successful! Starting Conversation Assistant..."
    ./ConversationAssistant
else
    echo "❌ Build failed!"
    exit 1
fi
