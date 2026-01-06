import Foundation

/// HTTP client for Anthropic Messages API
class AnthropicApiClient {

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let session: URLSession

    enum ApiError: Error, LocalizedError {
        case invalidRequest
        case networkError(Error)
        case invalidResponse
        case httpError(statusCode: Int, message: String)
        case decodingError(Error)
        case invalidApiKey

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Invalid API request"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from API"
            case .httpError(let code, let message):
                return "HTTP \(code): \(message)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .invalidApiKey:
                return "Invalid API key format"
            }
        }
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    /// Send a message with streaming response
    /// - Parameters:
    ///   - images: Array of base64-encoded PNG images
    ///   - prompt: Text prompt
    ///   - model: Model name (default: claude-haiku-4.5)
    ///   - onChunk: Callback for each text chunk
    /// - Returns: Result indicating success or error
    func sendMessageStream(
        images: [String],
        prompt: String,
        model: String = "claude-haiku-4.5-20250514",
        onChunk: @escaping (String) -> Void
    ) async -> Result<Void, ApiError> {

        // Build content blocks
        var contentBlocks: [ContentBlock] = []

        // Add images first
        for imageBase64 in images {
            let imageContent = ContentBlock.ImageContent(
                type: "image",
                source: ContentBlock.ImageSource(
                    type: "base64",
                    mediaType: "image/png",
                    data: imageBase64
                )
            )
            contentBlocks.append(.image(imageContent))
        }

        // Add text prompt
        let textContent = ContentBlock.TextContent(type: "text", text: prompt)
        contentBlocks.append(.text(textContent))

        // Build request with stream: true
        var requestDict: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks.map { block -> [String: Any] in
                        switch block {
                        case .text(let content):
                            return ["type": "text", "text": content.text]
                        case .image(let content):
                            return [
                                "type": "image",
                                "source": [
                                    "type": content.source.type,
                                    "media_type": content.source.mediaType,
                                    "data": content.source.data
                                ]
                            ]
                        }
                    }
                ]
            ]
        ]

        // Create URL request
        guard let url = URL(string: baseURL) else {
            return .failure(.invalidRequest)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.addValue("application/json", forHTTPHeaderField: "content-type")

        // Encode body
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestDict)
        } catch {
            return .failure(.invalidRequest)
        }

        // Make streaming request
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.httpError(statusCode: httpResponse.statusCode, message: "Request failed"))
            }

            // Parse SSE stream
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))

                    if jsonString == "[DONE]" {
                        break
                    }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {

                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            onChunk(text)
                        }
                    }
                }
            }

            return .success(())

        } catch {
            return .failure(.networkError(error))
        }
    }

    /// Send a message with optional images to Claude
    /// - Parameters:
    ///   - images: Array of base64-encoded PNG images
    ///   - prompt: Text prompt
    ///   - model: Model name (default: claude-haiku-4.5)
    /// - Returns: Response text
    func sendMessage(
        images: [String],
        prompt: String,
        model: String = "claude-haiku-4.5-20250514"
    ) async -> Result<String, ApiError> {

        // Build content blocks
        var contentBlocks: [ContentBlock] = []

        // Add images first
        for imageBase64 in images {
            let imageContent = ContentBlock.ImageContent(
                type: "image",
                source: ContentBlock.ImageSource(
                    type: "base64",
                    mediaType: "image/png",
                    data: imageBase64
                )
            )
            contentBlocks.append(.image(imageContent))
        }

        // Add text prompt
        let textContent = ContentBlock.TextContent(type: "text", text: prompt)
        contentBlocks.append(.text(textContent))

        // Build request
        let request = AnthropicRequest(
            model: model,
            maxTokens: 4096,
            messages: [
                Message(role: "user", content: contentBlocks)
            ]
        )

        // Create URL request
        guard let url = URL(string: baseURL) else {
            return .failure(.invalidRequest)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.addValue("application/json", forHTTPHeaderField: "content-type")

        // Encode body
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            return .failure(.invalidRequest)
        }

        // Make request
        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }

            // Check status code
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                    return .failure(.httpError(
                        statusCode: httpResponse.statusCode,
                        message: errorResponse.error.message
                    ))
                }
                return .failure(.httpError(
                    statusCode: httpResponse.statusCode,
                    message: "Unknown error"
                ))
            }

            // Decode success response
            do {
                let decoder = JSONDecoder()
                let apiResponse = try decoder.decode(AnthropicResponse.self, from: data)

                // Extract text from content blocks
                let responseText = apiResponse.content
                    .compactMap { $0.text }
                    .joined(separator: "\n")

                return .success(responseText)
            } catch {
                return .failure(.decodingError(error))
            }

        } catch {
            return .failure(.networkError(error))
        }
    }
}
