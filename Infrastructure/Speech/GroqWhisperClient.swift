import Foundation
import AVFoundation

/// Client for Groq's Whisper API - ultra-fast speech-to-text
/// Achieves 216x realtime speed with whisper-large-v3-turbo
class GroqWhisperClient {
    private let apiKey: String
    private let baseURL = "https://api.groq.com/openai/v1/audio/transcriptions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Transcribe audio data to text
    /// - Parameter audioData: Audio data in supported format (mp3, wav, m4a, etc.)
    /// - Parameter filename: Filename with extension for format detection
    /// - Returns: Transcribed text
    func transcribe(audioData: Data, filename: String = "audio.wav") async throws -> TranscriptionResult {
        let startTime = Date()

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3-turbo\r\n".data(using: .utf8)!)

        // Add language hint for better accuracy (from app settings)
        let languageCode = AppSettings.shared.languageCode
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(languageCode)\r\n".data(using: .utf8)!)

        // Add audio file
        let mimeType = mimeTypeForFilename(filename)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        let latency = Date().timeIntervalSince(startTime) * 1000 // ms

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GroqError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(GroqTranscriptionResponse.self, from: data)

        return TranscriptionResult(
            text: result.text,
            latencyMs: latency
        )
    }

    private func mimeTypeForFilename(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        default: return "audio/wav"
        }
    }
}

struct TranscriptionResult {
    let text: String
    let latencyMs: Double
}

struct GroqTranscriptionResponse: Codable {
    let text: String
}

enum GroqError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Groq API"
        case .apiError(let code, let message):
            return "Groq API error (\(code)): \(message)"
        }
    }
}
