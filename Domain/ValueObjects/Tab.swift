import Foundation

/// Value Object: Tab
/// Represents the different tabs/views in the application
enum Tab {
    case notes
    case coding
    case voice

    var title: String {
        switch self {
        case .notes:
            return "📝 Notes"
        case .coding:
            return "💻 Coding Task"
        case .voice:
            return "🎤 Voice Assistant"
        }
    }

    var keyboardShortcut: String {
        switch self {
        case .notes:
            return "⌘1"
        case .coding:
            return "⌘2"
        case .voice:
            return "⌘3"
        }
    }
}
