import Foundation

// MARK: - Request Models

struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

struct Message: Codable {
    let role: String
    let content: [ContentBlock]
}

enum ContentBlock: Codable {
    case text(TextContent)
    case image(ImageContent)

    struct TextContent: Codable {
        let type: String
        let text: String
    }

    struct ImageContent: Codable {
        let type: String
        let source: ImageSource
    }

    struct ImageSource: Codable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let content):
            try container.encode(content)
        case .image(let content):
            try container.encode(content)
        }
    }

    // Custom decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(TextContent.self) {
            self = .text(text)
        } else if let image = try? container.decode(ImageContent.self) {
            self = .image(image)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid content block type"
            )
        }
    }
}

// MARK: - Response Models

struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ResponseContent]
    let model: String
    let stopReason: String?
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }
}

struct ResponseContent: Codable {
    let type: String
    let text: String?
}

struct Usage: Codable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Error Response

struct AnthropicErrorResponse: Codable {
    let type: String
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let type: String
        let message: String
    }
}
