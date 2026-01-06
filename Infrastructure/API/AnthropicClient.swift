import Foundation

/// Infrastructure: Anthropic API Client
/// Handles communication with Anthropic's Claude API
class AnthropicClient {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"
    private let maxTokens = 4096

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Quick non-streaming message for interview answers
    func sendMessage(prompt: String, maxTokens: Int = 300) async throws -> (text: String, latencyMs: Double) {
        let startTime = Date()

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct Response: Codable {
            struct Content: Codable { let text: String }
            let content: [Content]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let text = response.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (text, latency)
    }

    /// Stream text-only message (no images) - for interview answers
    func streamTextMessage(
        prompt: String,
        maxTokens: Int = 300,
        onChunk: @escaping (String) -> Void
    ) async -> Result<Void, Error> {
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            return .failure(NSError(domain: "Invalid URL", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return .failure(error)
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "Invalid response", code: -1))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line + "\n"
                    if errorBody.count > 500 { break }
                }

                if let data = errorBody.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }

                return .failure(NSError(domain: errorMessage, code: httpResponse.statusCode))
            }

            // Parse SSE stream
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if jsonString == "[DONE]" { break }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String,
                       type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        onChunk(text)
                    }
                }
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Classification result for an utterance
    struct UtteranceClassification {
        let status: String   // "question", "incomplete", "answer", "filler"
        let topic: String?   // topic name or nil
    }

    /// Static system prompt for classification (cached) - OPTIMIZED: topics come from settings
    private static let classificationSystemPrompt = """
You help someone being interviewed. Classify their utterance, then answer if it's a question.

=== CLASSIFY ===
Output ONE line: STATUS:xxx|TOPIC:yyy

STATUS:
- question = asking about something (wants info)
- incomplete = cut off mid-sentence
- answer = responding/explaining, confirmations, thanks

=== IF question, ADD ANSWER ===
After STATUS line, output "---" then answer in 3-4 bullet points. Be direct, no fluff.
"""

    /// Get topics based on current tech stack setting
    private static func getTopicsForStack() -> String {
        let stack = AppSettings.shared.techStack
        let common = "oop, algorithms, systemDesign, api, aws, patterns, devops, personal, followUp, unknown"

        switch stack {
        case .java:
            return "java, collections, threads, jvm, spring, \(common)"
        case .python:
            return "python, django, fastapi, asyncio, \(common)"
        case .javascript:
            return "javascript, node, react, eventLoop, promises, \(common)"
        case .typescript:
            return "typescript, react, types, generics, \(common)"
        case .go:
            return "go, goroutines, channels, \(common)"
        case .csharp:
            return "csharp, dotnet, linq, async, \(common)"
        case .cpp:
            return "cpp, stl, pointers, memory, \(common)"
        case .rust:
            return "rust, ownership, traits, async, \(common)"
        case .general:
            return "java, python, javascript, \(common)"
        }
    }

    /// Combined classify + answer in ONE streaming call with PROMPT CACHING
    /// Returns classification immediately, then streams answer if status is "question"
    func classifyAndStreamAnswer(
        transcription: String,
        buffer: String,
        lastTopic: String?,
        userBackground: String?,
        conversationHistory: String,
        topicsSummary: String,
        pinnedSolution: String?,
        onClassification: @escaping (UtteranceClassification) -> Void,
        onAnswerChunk: @escaping (String) -> Void
    ) async -> Result<Void, Error> {
        let combinedText = buffer.isEmpty ? transcription : "\(buffer) \(transcription)"

        // Build dynamic user message (compact)
        var userParts: [String] = []
        userParts.append("UTTERANCE: \"\(combinedText)\"")
        userParts.append("TOPICS: \(Self.getTopicsForStack())")
        if let topic = lastTopic { userParts.append("Last topic: \(topic)") }

        if let bg = userBackground, !bg.isEmpty {
            userParts.append("YOUR BACKGROUND: \(bg)")
        }
        if !conversationHistory.isEmpty {
            userParts.append("INTERVIEW SO FAR:\n\(conversationHistory)\(topicsSummary)")
        }
        if let pinned = pinnedSolution {
            userParts.append("CURRENT CODE SOLUTION:\n\(pinned)")
        }

        let languageInstruction = AppSettings.shared.llmLanguageInstruction
        if !languageInstruction.isEmpty {
            userParts.append(languageInstruction)
        }

        let userMessage = userParts.joined(separator: "\n\n")

        // Build request with PROMPT CACHING - system message is cached
        let systemContent: [[String: Any]] = [
            [
                "type": "text",
                "text": Self.classificationSystemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "stream": true,
            "system": systemContent,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            return .failure(NSError(domain: "Invalid URL", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return .failure(error)
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "Invalid response", code: -1))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line + "\n"
                    if errorBody.count > 500 { break }
                }
                if let data = errorBody.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }
                return .failure(NSError(domain: errorMessage, code: httpResponse.statusCode))
            }

            var fullText = ""
            var classificationSent = false
            var answerStarted = false

            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if jsonString == "[DONE]" { break }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String,
                       type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        fullText += text

                        // Parse classification from first line
                        if !classificationSent && fullText.contains("\n") {
                            let lines = fullText.components(separatedBy: "\n")
                            if let firstLine = lines.first, firstLine.contains("STATUS:") {
                                let classification = parseClassification(firstLine)
                                classificationSent = true
                                onClassification(classification)

                                // If not a question, we're done after classification
                                if classification.status != "question" {
                                    return .success(())
                                }
                            }
                        }

                        // Stream answer after "---"
                        if classificationSent && !answerStarted && fullText.contains("---") {
                            answerStarted = true
                            // Send any content after ---
                            if let range = fullText.range(of: "---") {
                                let afterSeparator = String(fullText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !afterSeparator.isEmpty {
                                    onAnswerChunk(afterSeparator)
                                }
                            }
                        } else if answerStarted {
                            onAnswerChunk(text)
                        }
                    }
                }
            }

            // Handle case where classification wasn't parsed (fallback)
            if !classificationSent {
                let classification = parseClassification(fullText)
                onClassification(classification)
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Parse STATUS:xxx|TOPIC:yyy format
    private func parseClassification(_ text: String) -> UtteranceClassification {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        var status = "question"
        var topic: String? = "unknown"

        // Parse STATUS:xxx
        if let statusRange = cleaned.range(of: "status:") {
            let afterStatus = String(cleaned[statusRange.upperBound...])
            let statusEnd = afterStatus.firstIndex(of: "|") ?? afterStatus.endIndex
            status = String(afterStatus[..<statusEnd])
        }

        // Parse TOPIC:yyy
        if let topicRange = cleaned.range(of: "topic:") {
            let afterTopic = String(cleaned[topicRange.upperBound...])
            let topicEnd = afterTopic.firstIndex(of: "|") ?? afterTopic.firstIndex(of: "-") ?? afterTopic.endIndex
            let topicValue = String(afterTopic[..<topicEnd])
            topic = (topicValue == "none" || topicValue.isEmpty) ? nil : topicValue
        }

        return UtteranceClassification(status: status, topic: topic)
    }

    /// Send a message with images and stream the response
    func sendMessageStream(
        images: [String],
        prompt: String,
        onChunk: @escaping (String) -> Void
    ) async -> Result<Void, Error> {

        // Build request body
        var contentBlocks: [[String: Any]] = []

        // Add images
        for imageBase64 in images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": imageBase64
                ]
            ])
        }

        // Add text
        contentBlocks.append([
            "type": "text",
            "text": prompt
        ])

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks
                ]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            return .failure(NSError(domain: "Invalid URL", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return .failure(error)
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "Invalid response", code: -1))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to read error message
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line + "\n"
                    if errorBody.count > 500 { break } // Limit error message size
                }

                if let data = errorBody.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }

                return .failure(NSError(domain: errorMessage, code: httpResponse.statusCode))
            }

            // Parse SSE stream
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if jsonString == "[DONE]" { break }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String,
                       type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        onChunk(text)
                    }
                }
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
