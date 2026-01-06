import Foundation

/// Audio source for speaker identification
enum AudioSource {
    case microphone    // Your voice (you speaking)
    case systemAudio   // Interviewer voice (Zoom/Teams output)
}

/// Represents a message in the interview timeline
struct InterviewMessage: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: MessageType
    let content: String
    let topic: String?
    var screenshotId: UUID?  // For screenshot type messages
    var audioSource: AudioSource?  // Source of audio for speaker identification
    var isCollapsed: Bool = true   // For userResponse - collapsed by default

    enum MessageType {
        case question      // Interviewer question
        case answer        // Generated AI answer
        case userResponse  // User's spoken response (detected as "answer")
        case followUp      // Follow-up answer
        case status        // System status message
        case screenshot    // Screenshot thumbnail in timeline
    }

    init(type: MessageType, content: String, topic: String? = nil, screenshotId: UUID? = nil, audioSource: AudioSource? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.content = content
        self.topic = topic
        self.screenshotId = screenshotId
        self.audioSource = audioSource
        self.isCollapsed = (type == .userResponse)  // Collapsed by default for user responses
    }

    var isQuestion: Bool {
        type == .question
    }

    var isAnswer: Bool {
        type == .answer || type == .followUp
    }

    var displayTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}
