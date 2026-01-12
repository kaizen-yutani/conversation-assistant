import Foundation

/// Groq API client for speech transcription and LLM responses (Whisper STT + LLM)
class GroqSpeechClient {
    private let apiKey: String
    private let whisperURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let chatURL = "https://api.groq.com/openai/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioData: Data, filename: String = "audio.m4a") async throws -> (text: String, latencyMs: Double) {
        let startTime = Date()

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: whisperURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)

        let languageCode = AppSettings.shared.languageCode
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(languageCode)\r\n".data(using: .utf8)!)

        // Vocabulary hints based on tech stack setting
        let vocabulary = AppSettings.shared.whisperVocabulary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(vocabulary)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct Response: Codable { let text: String }
        let result = try JSONDecoder().decode(Response.self, from: data)

        return (result.text, latency)
    }

    /// Generate a concise answer for a topic
    func generateAnswer(for topic: String, transcription: String, userBackground: String? = nil) async throws -> (answer: String, latencyMs: Double) {
        let startTime = Date()

        let backgroundContext = userBackground != nil && !userBackground!.isEmpty ? """

        === USER'S BACKGROUND ===
        \(userBackground!)
        === END BACKGROUND ===

        For personal questions (Tell me about yourself, experience, projects), use ONLY the background above.

        """ : ""

        let languageInstruction = AppSettings.shared.llmLanguageInstruction
        let prompt = """
        You are a helpful assistant. Provide concise, scannable answers.
        \(backgroundContext)
        Question: "\(transcription)"
        Topic: \(topic)

        NOTE: Speech-to-text input - interpret misheard words based on technical context.

        ANSWER FORMAT - pick the best format for quick scanning:

        For COMPARISONS (X vs Y, difference between):
        • X: [2-3 words] | Y: [2-3 words]
        • X: [key diff] | Y: [key diff]
        • When to use: X for ___, Y for ___

        For DEFINITIONS (What is X):
        [One sentence max]
        • Key point 1
        • Key point 2
        • Gotcha/tip (optional)

        For HOW-TO (commands, code):
        `command` or short code
        [One line explaining when/why]

        RULES:
        - MAX 4-5 lines total
        - Use | for side-by-side comparison
        - Bullet points, not paragraphs
        - No code blocks unless asked for code
        - No "In summary" or fluff
        Use plain text.\(languageInstruction)
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 200,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            struct ErrorDetail: Codable { let message: String }
            let choices: [Choice]?
            let error: ErrorDetail?
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        if let error = response.error {
            print("⚠️ Groq API error: \(error.message)")
            return ("API error: \(error.message)", latency)
        }

        let answer = response.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No answer generated"

        return (answer, latency)
    }

    /// Classification result for an utterance
    struct UtteranceClassification {
        let status: String   // "question", "incomplete", "answer", "filler"
        let topic: String?   // topic name or nil
    }

    /// Combined classification: status + topic in ONE call
    /// Replaces both checkCompleteness() and detectTopic()
    func classifyUtterance(_ text: String, buffer: String, lastTopic: String?) async throws -> (classification: UtteranceClassification, latencyMs: Double) {
        let startTime = Date()

        let combinedText = buffer.isEmpty ? text : "\(buffer) \(text)"
        let lastTopicNote = lastTopic != nil ? "Last topic: \(lastTopic!)" : ""

        let prompt = """
        Classify this utterance. Return: STATUS,TOPIC

        Text: "\(combinedText)"
        \(lastTopicNote)

        IMPORTANT: This is speech-to-text input. Words may be misheard.
        Use context to interpret what makes sense technically (e.g., "Ray vs ArrayList" → Array vs ArrayList).

        STATUS (pick one):
        - question = asking about something OR mentioning a topic (wants info)
        - incomplete = cut off mid-sentence ("What is the", "Can you")
        - answer = user responding/explaining (any length). Includes: "Yes, sure", "Thank you", "Okay, I understand", any explanation
        - filler = ONLY single meaningless sounds: "um", "uh", "hmm", "ah". NOT "okay", "yes", "thank you"

        Short topic mentions like "polymorphism", "singleton pattern" = question

        TOPICS:
        array, arrayList, linkedList, hashMap, hashSet, treeMap, queue, collections
        threads, process, synchronized, volatile, deadlock, locks
        jvm, jdk, jre, garbageCollection, heap, stack
        oop, inheritance, polymorphism, encapsulation, abstraction, abstractClass, interface
        lambda, streamApi, optional, functionalInterface
        exceptions, checkedExceptions, uncheckedExceptions
        closure, hoisting, eventLoop, promises, asyncAwait, this, scope
        reactHooks, useState, useEffect, useContext, virtualDOM, redux
        typescript, generics, interfaces, types
        bigO, sorting, binarySearch, recursion, dynamicProgramming, bfs, dfs
        systemDesign, caching, redis, loadBalancing, database, sql, nosql, microservices, rest
        singleton, factory, builder, observer, strategy, dependencyInjection, solid
        testing, unitTest, tdd, mocking
        docker, kubernetes, ci, cd, git, aws
        linux, bash, ssh, networking
        background, experience, tellMeAboutYourself, projects
        followUp (for "tell me more" with no new topic)
        unknown (if no match)

        EXAMPLES:
        "What is ray list?" → question,arrayList (ray list = ArrayList)
        "difference between a ray and ray list" → question,array (comparing Array vs ArrayList)
        "What is key developer?" → question,hashMap (nonsense phrase + last topic = asking about hashMap key)
        "What is the" → incomplete,none
        "Tell me more" → question,followUp

        NOTE: If phrase makes no sense (like "key developer"), use lastTopic - it's likely a misheard word.

        Return ONLY: STATUS,TOPIC (e.g., "question,array")
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 20,
            "temperature": 0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let raw = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "question,unknown"

        // Parse "status,topic" format - handle different separators
        let cleaned = raw.replacingOccurrences(of: ":", with: ",").replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ",").map { String($0) }
        let status = parts.first ?? "question"
        let topicRaw = parts.count > 1 ? parts[1] : "unknown"
        let topic: String? = (topicRaw == "none" || topicRaw.isEmpty) ? nil : topicRaw

        return (UtteranceClassification(status: status, topic: topic), latency)
    }

    /// Generate follow-up answer for current topic
    func generateFollowUpAnswer(for topic: String, transcription: String, context: String, userBackground: String? = nil) async throws -> (answer: String, latencyMs: Double) {
        let startTime = Date()

        let backgroundContext = userBackground != nil && !userBackground!.isEmpty ? """

        === USER'S BACKGROUND ===
        \(userBackground!)
        === END BACKGROUND ===

        """ : ""

        let languageInstruction = AppSettings.shared.llmLanguageInstruction
        let prompt = """
        Follow-up on: \(topic)
        Request: "\(transcription)"
        \(backgroundContext)
        Context: \(context)

        Add 2-3 NEW points not covered yet:
        • Edge case or gotcha
        • Implementation detail or trade-off
        • Related concept

        MAX 4 lines. Bullet points only. No intro.\(languageInstruction)
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 200,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            struct APIError: Codable { let message: String }
            let choices: [Choice]?
            let error: APIError?
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        // Check for API error
        if let error = response.error {
            print("⚠️ Groq API error: \(error.message)")
            return ("API error: \(error.message)", latency)
        }

        let answer = response.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No answer generated"

        return (answer, latency)
    }
}
