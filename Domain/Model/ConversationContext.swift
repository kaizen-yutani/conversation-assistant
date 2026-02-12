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

    /// Message format for multi-turn API calls
    struct MultiTurnMessage {
        let role: String  // "user" or "assistant"
        let content: String
    }

    private var history: [Utterance] = []
    private(set) var currentTopic: String?
    private let maxHistory = 50
    private let historyQueue = DispatchQueue(label: "com.conversationassistant.history")

    // Multi-turn conversation support
    private(set) var conversationSummary: String?
    private let slidingWindowSize = 6
    private let summarizationThreshold = 10

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

        let isFollowUpPhrase = lowercased.contains("tell me more") ||
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
        if wordCount < 25 && (hasQuestionMark || startsWithQuestion || isFollowUpPhrase || isInterviewerPhrase) {
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

    /// Add utterance to history (thread-safe)
    func addUtterance(text: String, topic: String?, isQuestion: Bool = false) {
        let speaker = classifySpeaker(text: text, isQuestion: isQuestion)
        let utterance = Utterance(text: text, speaker: speaker, topic: topic, timestamp: Date())

        historyQueue.sync {
            history.append(utterance)

            let topicLower = topic?.lowercased()
            if let topic = topic, topicLower != "unknown", topicLower != "followup", topicLower != "answer" {
                currentTopic = topic
            }

            if history.count > maxHistory {
                history.removeFirst()
            }
        }
    }

    /// Get recent context for LLM (last 5 utterances)
    func getContextForLLM() -> String {
        return historyQueue.sync {
            guard !history.isEmpty else { return "No previous conversation." }

            let recent = history.suffix(5)
            return recent.map { utterance in
                let topicStr = utterance.topic != nil ? " [topic: \(utterance.topic!)]" : ""
                return "[\(utterance.speaker.rawValue)]: \(utterance.text)\(topicStr)"
            }.joined(separator: "\n")
        }
    }

    /// Get full conversation history for comprehensive context
    func getFullConversation() -> String {
        return historyQueue.sync {
            guard !history.isEmpty else { return "" }

            return history.map { utterance in
                let role = utterance.speaker == .interviewer ? "Q" : "A"
                return "\(role): \(utterance.text)"
            }.joined(separator: "\n")
        }
    }

    /// Get conversation summary (topics discussed)
    func getTopicsSummary() -> String {
        return historyQueue.sync {
            let topics = history.compactMap { $0.topic }.filter {
                $0.lowercased() != "unknown" && $0.lowercased() != "followup" && $0.lowercased() != "answer"
            }
            let unique = Array(Set(topics))
            return unique.isEmpty ? "" : "Topics discussed: \(unique.joined(separator: ", "))"
        }
    }

    /// Get the last topic discussed (for follow-ups)
    var lastTopic: String? {
        return currentTopic
    }

    func clear() {
        historyQueue.sync {
            history.removeAll()
            currentTopic = nil
            conversationSummary = nil
        }
    }

    // MARK: - Multi-Turn Conversation Support

    /// Check if summarization is needed (history exceeds threshold)
    var needsSummarization: Bool {
        return historyQueue.sync {
            conversationSummary == nil && history.count > summarizationThreshold
        }
    }

    /// Get messages older than sliding window (for summarization)
    func getMessagesForSummarization() -> [Utterance] {
        return historyQueue.sync {
            guard history.count > slidingWindowSize else { return [] }
            return Array(history.prefix(history.count - slidingWindowSize))
        }
    }

    /// Get formatted text of old messages for summarization API call
    func getTextForSummarization() -> String {
        let oldMessages = getMessagesForSummarization()
        return oldMessages.map { utterance in
            let role = utterance.speaker == .interviewer ? "User" : "Assistant"
            return "\(role): \(utterance.text)"
        }.joined(separator: "\n")
    }

    /// Set the conversation summary (called after LLM summarizes)
    func setSummary(_ summary: String) {
        let count = historyQueue.sync { () -> Int in
            conversationSummary = summary
            if history.count > slidingWindowSize {
                history = Array(history.suffix(slidingWindowSize))
            }
            return history.count
        }
        print("📋 Conversation summarized. Keeping last \(count) messages.")
    }

    /// Build multi-turn messages array for API call
    /// Structure: [Summary context] + [Recent sliding window] + [Current utterance]
    func buildMultiTurnMessages(currentUtterance: String, pinnedSolution: String? = nil) -> [MultiTurnMessage] {
        return historyQueue.sync {
            var messages: [MultiTurnMessage] = []

            if let summary = conversationSummary {
                var contextContent = "Previous conversation context: \(summary)"
                if let pinned = pinnedSolution {
                    contextContent += "\n\nCurrent code solution being discussed:\n\(pinned)"
                }
                messages.append(MultiTurnMessage(role: "user", content: contextContent))
                messages.append(MultiTurnMessage(role: "assistant", content: "I understand the context. I'll help with your questions."))
            } else if let pinned = pinnedSolution {
                messages.append(MultiTurnMessage(role: "user", content: "Current code solution being discussed:\n\(pinned)"))
                messages.append(MultiTurnMessage(role: "assistant", content: "I see the code. I'll help with questions about it."))
            }

            let recentHistory = conversationSummary != nil ? history : Array(history.suffix(slidingWindowSize))

            for utterance in recentHistory {
                let role = utterance.speaker == .interviewer ? "user" : "assistant"
                messages.append(MultiTurnMessage(role: role, content: utterance.text))
            }

            messages.append(MultiTurnMessage(role: "user", content: currentUtterance))

            return messages
        }
    }

    /// Convert multi-turn messages to API format
    func messagesToAPIFormat(_ messages: [MultiTurnMessage]) -> [[String: String]] {
        var result: [[String: String]] = []
        var lastRole: String?

        for msg in messages {
            if msg.role == lastRole, var lastMsg = result.last {
                lastMsg["content"] = (lastMsg["content"] ?? "") + "\n\n" + msg.content
                result[result.count - 1] = lastMsg
            } else {
                result.append(["role": msg.role, "content": msg.content])
                lastRole = msg.role
            }
        }

        if result.first?["role"] != "user" {
            result.insert(["role": "user", "content": "(Conversation in progress)"], at: 0)
        }

        return result
    }
}
