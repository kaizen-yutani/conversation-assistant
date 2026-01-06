import Foundation

/// Tracks conversation history for follow-up detection and context-aware responses
class ConversationContext {
    struct Utterance {
        let text: String
        let speaker: Speaker
        let topic: String?
        let timestamp: Date
    }

    enum Speaker: String {
        case interviewer
        case interviewee
        case unknown
    }

    private var history: [Utterance] = []
    private(set) var currentTopic: String?
    private let maxHistory = 50  // Keep more history for full context

    /// Classify speaker based on heuristics
    func classifySpeaker(text: String, isQuestion: Bool = false) -> Speaker {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        let wordCount = words.count
        let lowercased = trimmed.lowercased()

        // If LLM already classified as question, it's the interviewer
        if isQuestion {
            return .interviewer
        }

        // Question indicators
        let hasQuestionMark = trimmed.contains("?")
        let startsWithQuestion = lowercased.hasPrefix("what") ||
                                  lowercased.hasPrefix("how") ||
                                  lowercased.hasPrefix("why") ||
                                  lowercased.hasPrefix("can you") ||
                                  lowercased.hasPrefix("could you") ||
                                  lowercased.hasPrefix("tell me") ||
                                  lowercased.hasPrefix("explain") ||
                                  lowercased.hasPrefix("describe") ||
                                  lowercased.hasPrefix("walk me") ||
                                  lowercased.hasPrefix("so ") ||
                                  lowercased.hasPrefix("let's assume")

        let isFollowUp = lowercased.contains("tell me more") ||
                         lowercased.contains("dig deeper") ||
                         lowercased.contains("elaborate") ||
                         lowercased.contains("can you expand") ||
                         lowercased.contains("more details") ||
                         lowercased.contains("give me an example")

        // Interview greetings/transitions - likely interviewer
        let isInterviewerPhrase = lowercased.contains("welcome to") ||
                                   lowercased.contains("good evening") ||
                                   lowercased.contains("good morning") ||
                                   lowercased.contains("shall proceed") ||
                                   lowercased.contains("gone through your resume") ||
                                   lowercased.contains("let me ask")

        // Short questions = interviewer
        if wordCount < 25 && (hasQuestionMark || startsWithQuestion || isFollowUp || isInterviewerPhrase) {
            return .interviewer
        }

        // Long explanations = interviewee
        if wordCount > 30 {
            return .interviewee
        }

        // Medium length with technical terms might be interviewee answering
        if wordCount > 15 {
            return .interviewee
        }

        return .unknown
    }

    /// Check if this is a follow-up request
    func isFollowUp(text: String) -> Bool {
        let lowercased = text.lowercased()
        let followUpPhrases = [
            "tell me more", "dig deeper", "elaborate", "expand on",
            "more details", "give me an example", "can you explain",
            "what else", "go deeper", "more about", "continue"
        ]
        return followUpPhrases.contains { lowercased.contains($0) }
    }

    /// Add utterance to history
    func addUtterance(text: String, topic: String?, isQuestion: Bool = false) {
        let speaker = classifySpeaker(text: text, isQuestion: isQuestion)
        let utterance = Utterance(text: text, speaker: speaker, topic: topic, timestamp: Date())
        history.append(utterance)

        // Update current topic if we detected one (case-insensitive check)
        let topicLower = topic?.lowercased()
        if let topic = topic, topicLower != "unknown", topicLower != "followup", topicLower != "answer" {
            currentTopic = topic
        }

        // Trim history
        if history.count > maxHistory {
            history.removeFirst()
        }

        print("📝 [\(speaker.rawValue)] \(text.prefix(50))... | Topic: \(topic ?? "none")")
    }

    /// Get recent context for LLM (last 5 utterances)
    func getContextForLLM() -> String {
        guard !history.isEmpty else { return "No previous conversation." }

        let recent = history.suffix(5)
        return recent.map { utterance in
            let topicStr = utterance.topic != nil ? " [topic: \(utterance.topic!)]" : ""
            return "[\(utterance.speaker.rawValue)]: \(utterance.text)\(topicStr)"
        }.joined(separator: "\n")
    }

    /// Get full conversation history for comprehensive context
    func getFullConversation() -> String {
        guard !history.isEmpty else { return "" }

        return history.map { utterance in
            let role = utterance.speaker == .interviewer ? "Q" : "A"
            return "\(role): \(utterance.text)"
        }.joined(separator: "\n")
    }

    /// Get conversation summary (topics discussed)
    func getTopicsSummary() -> String {
        let topics = history.compactMap { $0.topic }.filter {
            $0.lowercased() != "unknown" && $0.lowercased() != "followup" && $0.lowercased() != "answer"
        }
        let unique = Array(Set(topics))
        return unique.isEmpty ? "" : "Topics discussed: \(unique.joined(separator: ", "))"
    }

    /// Get the last topic discussed (for follow-ups)
    var lastTopic: String? {
        return currentTopic
    }

    func clear() {
        history.removeAll()
        currentTopic = nil
    }
}
