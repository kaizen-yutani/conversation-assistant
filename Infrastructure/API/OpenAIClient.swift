import Foundation

/// Infrastructure: OpenAI Whisper Client
/// Handles speech-to-text transcription using OpenAI's Whisper API
class OpenAIClient {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let model = "whisper-1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Transcribe audio data to text
    func transcribe(audioData: [Float], sampleRate: Double) async -> Result<String, Error> {
        // Convert Float audio to WAV file data
        guard let wavData = encodeAudioToWavData(audioData: audioData, sampleRate: Int(sampleRate)) else {
            return .failure(NSError(domain: "Failed to encode audio", code: -1))
        }

        // Create multipart form data request
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: baseURL) else {
            return .failure(NSError(domain: "Invalid URL", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add language parameter to force English (prevents multilingual hallucinations)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                let transcript = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return .success(transcript)
            } else {
                return .failure(NSError(domain: "Failed to parse response", code: -1))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private Helpers

    private func encodeAudioToWavData(audioData: [Float], sampleRate: Int) -> Data? {
        // Convert Float32 to Int16 PCM
        let int16Data = audioData.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * 32767.0)
        }

        // Create WAV header
        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + int16Data.count * 2)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // Mono
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(int16Data.count * 2).littleEndian) { Data($0) })

        for sample in int16Data {
            wavData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }

        return wavData
    }
}
