import Foundation

// MARK: - Chat Message Types for Multi-Turn Conversations

/// Represents a message in a multi-turn conversation
struct ChatMessage {
    enum Role: String {
        case user
        case assistant
    }

    let role: Role
    let content: String

    func toDictionary() -> [String: Any] {
        return ["role": role.rawValue, "content": content]
    }
}

/// Manages conversation history for multi-turn chats
class ChatHistory {
    private var messages: [ChatMessage] = []
    private let maxMessages: Int

    init(maxMessages: Int = 20) {
        self.maxMessages = maxMessages
    }

    /// Add a user message
    func addUser(_ content: String) {
        messages.append(ChatMessage(role: .user, content: content))
        trimIfNeeded()
    }

    /// Add an assistant message
    func addAssistant(_ content: String) {
        messages.append(ChatMessage(role: .assistant, content: content))
        trimIfNeeded()
    }

    /// Get messages as array for API
    func toAPIMessages() -> [[String: Any]] {
        return messages.map { $0.toDictionary() }
    }

    /// Get messages with a new user query appended (doesn't modify history)
    func toAPIMessagesWithQuery(_ query: String) -> [[String: Any]] {
        var result = messages.map { $0.toDictionary() }
        result.append(["role": "user", "content": query])
        return result
    }

    /// Clear conversation
    func clear() {
        messages.removeAll()
    }

    /// Check if empty
    var isEmpty: Bool {
        return messages.isEmpty
    }

    /// Get message count
    var count: Int {
        return messages.count
    }

    private func trimIfNeeded() {
        // Keep pairs (user + assistant) to maintain coherent context
        while messages.count > maxMessages {
            // Remove oldest pair
            if messages.count >= 2 {
                messages.removeFirst(2)
            } else {
                messages.removeFirst()
            }
        }
    }
}

/// Infrastructure: Anthropic API Client
/// Handles communication with Anthropic's Claude API
class AnthropicClient {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"
    private let maxTokens = 4096

    /// Retry configuration (matches Anthropic SDK defaults)
    private let maxRetries = 2
    private let retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 529]

    /// Shared URLSession for connection reuse (HTTP/2 multiplexing)
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// Track if connection has been warmed up
    private var isConnectionWarm = false

    private var currentTask: Task<Void, Error>?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    deinit {
        currentTask?.cancel()
        session.invalidateAndCancel()
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    /// Check if an HTTP status code is retryable
    private func isRetryable(statusCode: Int) -> Bool {
        retryableStatusCodes.contains(statusCode)
    }

    /// Calculate exponential backoff delay for retry attempt
    private func backoffDelay(attempt: Int) -> UInt64 {
        // Exponential backoff: 1s, 2s, 4s with jitter
        let baseDelay = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return UInt64((baseDelay + jitter) * 1_000_000_000)
    }

    /// Pre-warm the connection to Anthropic API (DNS + TCP + TLS handshake)
    /// Call this while STT is running to save ~50-100ms on first request
    func warmupConnection() async {
        guard !isConnectionWarm else { return }

        let startTime = Date()

        // HEAD request to establish connection without sending data
        guard let url = URL(string: "https://api.anthropic.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let _ = try await session.data(for: request)
            isConnectionWarm = true
            let latency = Date().timeIntervalSince(startTime) * 1000
            NSLog("🔥 Anthropic connection warmed up in %.0fms", latency)
        } catch {
            // Connection warmup failed, but that's okay - we'll connect on first real request
            NSLog("⚠️ Connection warmup failed (non-critical): %@", error.localizedDescription)
        }
    }

    /// Quick non-streaming message for fast answers
    func sendMessage(prompt: String, maxTokens: Int = 300) async throws -> (text: String, latencyMs: Double) {
        let startTime = Date()
        let maxAttempts = 3
        let backoffIntervals: [Double] = [0.5, 1.0, 1.5]

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

        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (400..<500).contains(httpResponse.statusCode) {
                    throw NSError(domain: "AnthropicClient", code: httpResponse.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }

                let latency = Date().timeIntervalSince(startTime) * 1000

                struct Response: Codable {
                    struct Content: Codable { let text: String }
                    let content: [Content]
                }

                let decoded = try JSONDecoder().decode(Response.self, from: data)
                let text = decoded.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                return (text, latency)
            } catch {
                let nsError = error as NSError
                if (400..<500).contains(nsError.code) && nsError.domain == "AnthropicClient" {
                    throw error
                }

                lastError = error
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: UInt64(backoffIntervals[attempt] * 1_000_000_000))
                }
            }
        }

        throw lastError!
    }

    /// Stream text-only message (no images) - for fast answers
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

        for attempt in 0..<2 {
            do {
                let (bytes, response) = try await session.bytes(for: request)

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

                    let error = NSError(domain: errorMessage, code: httpResponse.statusCode)

                    if (400..<500).contains(httpResponse.statusCode) {
                        return .failure(error)
                    }

                    if attempt < 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    return .failure(error)
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
                if isNetworkError(error) && attempt < 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                return .failure(error)
            }
        }

        return .failure(NSError(domain: "Failed after retries", code: -1))
    }

    /// Classification result for an utterance
    struct UtteranceClassification {
        let status: String   // "question", "incomplete", "answer", "filler"
        let topic: String?   // topic name or nil
    }

    /// Static system prompt for classification (cached) - OPTIMIZED: topics come from settings
    private static let classificationSystemPrompt = """
You are a helpful assistant that answers questions by searching connected knowledge sources.
Classify the user's utterance, then answer if it's a question or request.

=== CLASSIFY ===
Output ONE line: STATUS:xxx|TOPIC:yyy

STATUS:
- question = wants info OR requests action OR expresses curiosity DIRECTED AT THE ASSISTANT. Includes:
  • Direct questions ("What tickets are left?")
  • Implicit requests ("let's see what's in the sprint", "show me my tickets", "check the backlog")
  • Action phrases ("let's see", "let's check", "what's left", "what do we have")
  • Statements with uncertainty ("I wonder", "I'm not sure about", "I'm curious")
  • Rhetorical questions ("wouldn't that be", "isn't that", "right?", "correct?")
  • Requests starting with fillers ("okay so what about", "sure but how does", "thanks, now tell me")
- incomplete = genuinely cut off mid-word/mid-phrase (e.g., "What is the best w-", "How do you han")
  Do NOT mark as incomplete just because it ends with a preposition or conjunction - natural speech often does.
- answer = speech directed at OTHER PEOPLE, not the assistant. Includes:
  • Confirmations/acknowledgments ("Yes", "No", "Thanks", "Got it", "I see")
  • Requests to colleagues ("Can someone send it?", "John, can you check?", "Let's discuss this later")
  • Conversational speech between people ("I think we should", "Can you share that?", "Send it to the chat")
  • Phrases with "someone", "you guys", "we should", "can you" directed at humans in the room
- filler = ONLY for standalone noise words with zero meaning ("um", "hmm", "uh")

IMPORTANT: You are listening to a meeting/conversation. Not everything said is directed at you.
If the utterance asks "someone" to do something, or tells a person to act, it is NOT a question for you — classify as "answer".
If the utterance asks for factual information or to search/find/look up something, it IS a question for you.

CRITICAL: When in doubt, ALWAYS classify as "question". It is far better to answer a non-question than to skip a real question.
"let's see if we have any tickets" → question (wants ticket info)
"what's left for the sprint" → question (wants sprint status)
"okay, what about the deployment" → question (starts with filler but asks about deployment)
"so tell me about the architecture" → question (starts with conjunction but is a request)
"thank you, now what's next" → question (gratitude + question)
"can someone find it and send it to the chat" → answer (directed at colleagues, not the assistant)
"John, can you look into that?" → answer (directed at a person)
"let's move on to the next topic" → answer (meeting coordination, not an info request)

=== IF question, ADD ANSWER ===
After STATUS line, output "---" then answer in 3-4 bullet points. Be direct, no fluff.
When you need more information, indicate you would use available tools.
"""

    /// Get topics for classification
    private static func getTopicsForStack() -> String {
        return "oop, algorithms, systemDesign, api, aws, patterns, devops, personal, followUp, unknown"
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
            userParts.append("CONVERSATION SO FAR:\n\(conversationHistory)\(topicsSummary)")
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
            "max_tokens": 600,  // Increased for enumeration questions
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

        for attempt in 0..<2 {
            do {
                let (bytes, response) = try await session.bytes(for: request)

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

                    let error = NSError(domain: errorMessage, code: httpResponse.statusCode)

                    if (400..<500).contains(httpResponse.statusCode) {
                        return .failure(error)
                    }

                    if attempt < 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    return .failure(error)
                }

                var fullText = ""
                var classificationSent = false
                var answerStarted = false
                var answerContentStarted = false

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
                                        answerContentStarted = true
                                        onAnswerChunk(afterSeparator)
                                    }
                                }
                            } else if answerStarted {
                                if !answerContentStarted {
                                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        answerContentStarted = true
                                        onAnswerChunk(trimmed)
                                    }
                                } else {
                                    onAnswerChunk(text)
                                }
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
                if isNetworkError(error) && attempt < 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                return .failure(error)
            }
        }

        return .failure(NSError(domain: "Failed after retries", code: -1))
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
    /// - Parameters:
    ///   - images: Base64-encoded images to analyze
    ///   - prompt: The analysis prompt/instruction
    ///   - conversationContext: Recent conversation history for context
    ///   - userContext: Optional user-provided context for this specific analysis
    ///   - onChunk: Callback for streaming text chunks
    func sendMessageStream(
        images: [String],
        prompt: String,
        conversationContext: String? = nil,
        userContext: String? = nil,
        onChunk: @escaping (String) -> Void
    ) async -> Result<Void, Error> {

        // Build contextual prompt
        var contextualPrompt = prompt

        // Add user-specific context if provided
        if let userCtx = userContext, !userCtx.isEmpty {
            contextualPrompt += "\n\nUser's specific request: \(userCtx)"
        }

        // Build request body
        var contentBlocks: [[String: Any]] = []

        // Add conversation context as text first (if available)
        if let context = conversationContext, !context.isEmpty {
            contentBlocks.append([
                "type": "text",
                "text": "Recent conversation for context:\n\(context)\n\n---\n"
            ])
        }

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

        // Add prompt/instructions
        contentBlocks.append([
            "type": "text",
            "text": contextualPrompt
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

        for attempt in 0..<2 {
            do {
                let (bytes, response) = try await session.bytes(for: request)

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

                    let error = NSError(domain: errorMessage, code: httpResponse.statusCode)

                    if (400..<500).contains(httpResponse.statusCode) {
                        return .failure(error)
                    }

                    if attempt < 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    return .failure(error)
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
                if isNetworkError(error) && attempt < 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                return .failure(error)
            }
        }

        return .failure(NSError(domain: "Failed after retries", code: -1))
    }


    // MARK: - Tool Use Support
    
    /// Response content block types
    enum ContentBlock {
        case text(String)
        case toolUse(id: String, name: String, input: [String: Any])
    }
    
    /// Stop reason from API response
    enum StopReason: String {
        case endTurn = "end_turn"
        case toolUse = "tool_use"
        case maxTokens = "max_tokens"
        case stopSequence = "stop_sequence"
    }
    
    /// Response from streaming with tools
    struct ToolUseResponse {
        let contentBlocks: [ContentBlock]
        let stopReason: StopReason
        
        var textContent: String {
            contentBlocks.compactMap { block in
                if case .text(let text) = block { return text }
                return nil
            }.joined()
        }
        
        var toolUses: [ToolUseRequest] {
            contentBlocks.compactMap { block in
                if case .toolUse(let id, let name, let input) = block {
                    return ToolUseRequest(id: id, name: name, input: input)
                }
                return nil
            }
        }
    }
    
    /// Chat with tools - handles the full tool use loop
    /// - Parameters:
    ///   - question: The user's question
    ///   - tools: Available tool definitions
    ///   - systemPrompt: Optional system prompt
    ///   - conversationHistory: Optional previous messages for multi-turn context
    ///   - onToolUse: Callback when tools are being used (for UI updates) - receives array of tool names
    ///   - onChunk: Callback for streaming text chunks
    /// - Returns: The final answer after any tool use
    func chatWithTools(
        question: String,
        tools: [ToolDefinition],
        systemPrompt: String? = nil,
        conversationHistory: ChatHistory? = nil,
        onToolUse: @escaping ([String]) -> Void,
        onChunk: @escaping (String) -> Void
    ) async -> Result<String, Error> {
        // === LOGGING ===
        print("\n[AnthropicClient] ========== CHAT WITH TOOLS ==========")
        print("[AnthropicClient] QUESTION: \(question)")
        print("[AnthropicClient] TOOLS: \(tools.map { $0.name }.joined(separator: ", "))")
        if let system = systemPrompt {
            print("[AnthropicClient] SYSTEM PROMPT (first 500 chars): \(String(system.prefix(500)))...")
        }

        // Build messages: conversation history + current question
        var messages: [[String: Any]] = conversationHistory?.toAPIMessagesWithQuery(question)
            ?? [["role": "user", "content": question]
        ]

        var iterations = 0
        let maxIterations = 5  // Prevent infinite loops
        
        while iterations < maxIterations {
            iterations += 1
            
            let response = await sendMessageWithTools(
                messages: messages,
                tools: tools,
                systemPrompt: systemPrompt,
                onChunk: onChunk
            )
            
            switch response {
            case .failure(let error):
                print("[AnthropicClient] ERROR: \(error.localizedDescription)")
                print("[AnthropicClient] ========================================\n")
                return .failure(error)
                
            case .success(let toolResponse):
                // If end_turn, we're done
                if toolResponse.stopReason == .endTurn || toolResponse.stopReason == .maxTokens {
                    print("[AnthropicClient] FINAL ANSWER (first 500 chars): \(String(toolResponse.textContent.prefix(500)))...")
                    print("[AnthropicClient] ========================================\n")
                    return .success(toolResponse.textContent)
                }

                // If tool_use, execute tools and continue
                if toolResponse.stopReason == .toolUse && !toolResponse.toolUses.isEmpty {
                    // Notify UI about all tools being used at once
                    let toolNames = toolResponse.toolUses.map { $0.name }
                    for toolUse in toolResponse.toolUses {
                        print("[AnthropicClient] TOOL CALL: \(toolUse.name) with input: \(toolUse.input)")
                    }
                    onToolUse(toolNames)

                    // Execute tools
                    let toolResults = await ToolExecutor.shared.processToolUses(toolResponse.toolUses)
                    print("[AnthropicClient] TOOL RESULTS: \(toolResults.count) results received")
                    
                    // Build assistant message with tool uses
                    var assistantContent: [[String: Any]] = []
                    for block in toolResponse.contentBlocks {
                        switch block {
                        case .text(let text):
                            if !text.isEmpty {
                                assistantContent.append(["type": "text", "text": text])
                            }
                        case .toolUse(let id, let name, let input):
                            assistantContent.append([
                                "type": "tool_use",
                                "id": id,
                                "name": name,
                                "input": input
                            ])
                        }
                    }
                    
                    messages.append(["role": "assistant", "content": assistantContent])
                    
                    // Add tool results
                    let toolResultContent = toolResults.map { $0.toDictionary() }
                    messages.append(["role": "user", "content": toolResultContent])
                    
                    // Continue the loop
                    continue
                }
                
                // Default: return whatever text we have
                return .success(toolResponse.textContent)
            }
        }
        
        return .failure(NSError(domain: "Max tool use iterations reached", code: -1))
    }
    
    /// Chat with pre-fetched tool results — skips Claude's tool-decision round-trip.
    /// Claude still has tools available for follow-up calls if needed.
    func chatWithPreFetchedResults(
        question: String,
        preResults: [(toolName: String, result: String)],
        tools: [ToolDefinition],
        systemPrompt: String? = nil,
        conversationHistory: ChatHistory? = nil,
        onChunk: @escaping (String) -> Void
    ) async -> Result<String, Error> {
        NSLog("⚡ [PRE-ROUTED] Streaming question + %d pre-fetched results (no tool schema)", preResults.count)

        // Build context from pre-fetched tool results
        let toolContext = preResults.map { "[\($0.toolName) results]:\n\($0.result)" }.joined(separator: "\n\n")
        let enrichedQuestion = """
        \(question)

        Here are the search results:
        \(toolContext)

        Summarize these results to answer the question concisely. Use bullet points and include URLs.
        """

        // Direct streaming call WITHOUT tool definitions — much faster
        let messages: [[String: Any]] = conversationHistory?.toAPIMessagesWithQuery(enrichedQuestion)
            ?? [["role": "user", "content": enrichedQuestion]]

        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": messages
        ]

        if let sp = systemPrompt {
            requestBody["system"] = [["type": "text", "text": sp, "cache_control": ["type": "ephemeral"]]]
        }

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

        var fullResponse = ""

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let httpResponse = response as? HTTPURLResponse
                return .failure(NSError(domain: "HTTP \(httpResponse?.statusCode ?? 0)", code: httpResponse?.statusCode ?? 0))
            }

            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" { break }

                guard let data = jsonStr.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String else { continue }

                if type == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    fullResponse += text
                    onChunk(text)
                }
            }
        } catch {
            return .failure(error)
        }

        return .success(fullResponse)
    }

    /// Send a streaming message with tools support (includes retry with exponential backoff)
    private func sendMessageWithTools(
        messages: [[String: Any]],
        tools: [ToolDefinition],
        systemPrompt: String?,
        onChunk: @escaping (String) -> Void
    ) async -> Result<ToolUseResponse, Error> {
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": messages
        ]

        if let system = systemPrompt {
            requestBody["system"] = system
        }

        if !tools.isEmpty {
            requestBody["tools"] = tools.map { $0.toDictionary() }
            requestBody["tool_choice"] = ["type": "auto"]
        }

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

        // Retry loop with exponential backoff
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(NSError(domain: "Invalid response", code: -1))
                }

                // Check for retryable HTTP errors
                if !(200...299).contains(httpResponse.statusCode) {
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

                    let error = NSError(domain: errorMessage, code: httpResponse.statusCode)

                    // Retry if retryable and not last attempt
                    if isRetryable(statusCode: httpResponse.statusCode) && attempt < maxRetries {
                        lastError = error
                        try await Task.sleep(nanoseconds: backoffDelay(attempt: attempt))
                        continue
                    }
                    return .failure(error)
                }

                // Parse SSE stream (success path - no retry once streaming starts)
                var contentBlocks: [ContentBlock] = []
                var currentTextContent = ""
                var currentToolUse: (id: String, name: String, inputJson: String)? = nil
                var stopReason: StopReason = .endTurn

                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" { break }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }

                        switch type {
                        case "content_block_start":
                            if let contentBlock = json["content_block"] as? [String: Any],
                               let blockType = contentBlock["type"] as? String {
                                if blockType == "tool_use" {
                                    let id = contentBlock["id"] as? String ?? ""
                                    let name = contentBlock["name"] as? String ?? ""
                                    currentToolUse = (id: id, name: name, inputJson: "")
                                }
                            }

                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any] {
                                if let text = delta["text"] as? String {
                                    currentTextContent += text
                                    onChunk(text)
                                } else if let partialJson = delta["partial_json"] as? String {
                                    currentToolUse?.inputJson += partialJson
                                }
                            }

                        case "content_block_stop":
                            // Finalize current block
                            if let toolUse = currentToolUse {
                                // Parse the accumulated JSON
                                var input: [String: Any] = [:]
                                if let data = toolUse.inputJson.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    input = parsed
                                }
                                contentBlocks.append(.toolUse(id: toolUse.id, name: toolUse.name, input: input))
                                currentToolUse = nil
                            } else if !currentTextContent.isEmpty {
                                contentBlocks.append(.text(currentTextContent))
                                currentTextContent = ""
                            }

                        case "message_delta":
                            if let messageDelta = json["delta"] as? [String: Any],
                               let reason = messageDelta["stop_reason"] as? String {
                                stopReason = StopReason(rawValue: reason) ?? .endTurn
                            }

                        default:
                            break
                        }
                    }
                }

                // Add any remaining text content
                if !currentTextContent.isEmpty {
                    contentBlocks.append(.text(currentTextContent))
                }

                return .success(ToolUseResponse(contentBlocks: contentBlocks, stopReason: stopReason))

            } catch {
                // Connection errors - retry if possible
                if attempt < maxRetries {
                    lastError = error
                    try? await Task.sleep(nanoseconds: backoffDelay(attempt: attempt))
                    continue
                }
                return .failure(error)
            }
        }

        // Should never reach here, but return last error if we do
        return .failure(lastError ?? NSError(domain: "Unknown error after retries", code: -1))
    }

    // MARK: - Conversation Summarization

    func summarizeConversation(conversationText: String) async throws -> String {
        guard !conversationText.isEmpty else { return "" }

        let maxAttempts = 3
        let backoffIntervals: [Double] = [0.5, 1.0, 1.5]

        let prompt = """
        Summarize this conversation in 2-3 concise sentences.
        Focus on: main topics discussed, key technical concepts, and any important context for follow-up questions.

        Conversation:
        \(conversationText)

        Summary:
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 150,
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

        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (400..<500).contains(httpResponse.statusCode) {
                    throw NSError(domain: "AnthropicClient", code: httpResponse.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }

                struct Response: Codable {
                    struct Content: Codable { let text: String }
                    let content: [Content]
                }

                let decoded = try JSONDecoder().decode(Response.self, from: data)
                return decoded.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                let nsError = error as NSError
                if (400..<500).contains(nsError.code) && nsError.domain == "AnthropicClient" {
                    throw error
                }

                lastError = error
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: UInt64(backoffIntervals[attempt] * 1_000_000_000))
                }
            }
        }

        throw lastError!
    }
}
