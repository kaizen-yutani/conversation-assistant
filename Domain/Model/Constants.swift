import Foundation

struct LayoutConstants {
    struct Typography {
        // Display scale (SF Pro Display threshold at 20pt+)
        static let display: CGFloat = 28
        static let h1: CGFloat = 22
        // Text scale (SF Pro Text)
        static let h2: CGFloat = 18
        static let h3: CGFloat = 16
        static let h4: CGFloat = 14
        static let bodyLarge: CGFloat = 15
        static let body: CGFloat = 13
        static let caption: CGFloat = 11
        static let micro: CGFloat = 10
        // Monospace
        static let code: CGFloat = 13
        static let codeSmall: CGFloat = 12

        // Line heights
        static let lineHeightDisplay: CGFloat = 36
        static let lineHeightH1: CGFloat = 28
        static let lineHeightH2: CGFloat = 24
        static let lineHeightBodyLarge: CGFloat = 22
        static let lineHeightBody: CGFloat = 18
        static let lineHeightCaption: CGFloat = 16
        static let lineHeightCode: CGFloat = 20
    }
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    struct CornerRadius {
        static let tight: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 10
        static let xlarge: CGFloat = 12
        static let pill: CGFloat = 16
    }
    struct IconButton {
        static let size: CGFloat = 32
        static let iconSize: CGFloat = 15
        static let spacing: CGFloat = 8
    }
    struct Toolbar {
        static let height: CGFloat = 48
        static let dropdownHeight: CGFloat = 28
    }
    struct Timeline {
        static let messageSpacing: CGFloat = 16
        static let messagePadding: CGFloat = 20
        static let badgeSize: CGFloat = 28
        static let badgeGap: CGFloat = 10
        static let accentBarWidth: CGFloat = 3
    }
    struct Animation {
        static let fast: TimeInterval = 0.08
        static let normal: TimeInterval = 0.15
        static let slow: TimeInterval = 0.25
        static let spring: TimeInterval = 0.4
        static let pulse: TimeInterval = 2.0
    }
    struct Alpha {
        static let activeBackground: CGFloat = 0.15
        static let inactiveBackground: CGFloat = 0.06
        static let hoverBackground: CGFloat = 0.12
        static let subtleText: CGFloat = 0.45
        static let secondaryText: CGFloat = 0.70
        static let border: CGFloat = 0.15
    }
}

struct AppConstants {
    struct Models {
        static let anthropicHaiku = "claude-haiku-4-5-20251001"
        static let groqWhisper = "whisper-large-v3"
    }
    struct APIURLs {
        static let anthropicMessages = "https://api.anthropic.com/v1/messages"
        static let groqTranscriptions = "https://api.groq.com/openai/v1/audio/transcriptions"
    }
    struct Thresholds {
        static let dedupeWindow: TimeInterval = 5.0
        static let similarityThreshold: Double = 0.5
        static let bufferTimeout: TimeInterval = 10.0
        static let answerCooldown: TimeInterval = 12.0
        static let speechThreshold: Float = 0.5
        static let silenceTimeout: TimeInterval = 0.65
        static let minSpeechDuration: TimeInterval = 0.5
        static let slidingWindowSize = 6
        static let summarizationThreshold = 10
        static let maxConversationHistory = 50
    }
    struct MaxTokens {
        static let classification = 600
        static let answerStream = 300
        static let summarization = 150
        static let imageAnalysis = 4096
    }
}
