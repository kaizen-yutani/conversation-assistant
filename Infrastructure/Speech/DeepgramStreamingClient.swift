import Foundation
import AVFoundation

/// Deepgram Nova-3 Streaming STT Client
/// Uses WebSocket for real-time transcription with ~100-150ms latency
class DeepgramStreamingClient: NSObject {
    private let apiKey: String
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio streaming state
    private var isConnected = false
    private var isStreaming = false

    // Configuration
    private let model = "nova-3"
    private let sampleRate = 16000
    private let encoding = "linear16"

    // Callbacks
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    // Transcript accumulation
    private var currentUtterance = ""
    private var finalizedText = ""

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    /// Connect to Deepgram WebSocket
    func connect(language: String = "en") {
        guard !isConnected else {
            NSLog("⚠️ Deepgram: Already connected")
            return
        }

        // Build WebSocket URL with query parameters
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: encoding),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),  // 300ms silence = end of utterance
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "smart_format", value: "true")
        ]

        guard let url = components.url else {
            NSLog("❌ Deepgram: Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocket = urlSession?.webSocketTask(with: request)

        webSocket?.resume()
        isConnected = true

        NSLog("🔌 Deepgram: Connecting to %@", url.absoluteString)

        // Start receiving messages
        receiveMessage()
    }

    /// Disconnect from WebSocket
    func disconnect() {
        guard isConnected else { return }

        // Send close stream message
        let closeMessage = "{\"type\": \"CloseStream\"}"
        webSocket?.send(.string(closeMessage)) { [weak self] error in
            if let error = error {
                NSLog("⚠️ Deepgram: Error sending close: %@", error.localizedDescription)
            }
            self?.webSocket?.cancel(with: .normalClosure, reason: nil)
            self?.isConnected = false
            self?.isStreaming = false
            NSLog("🔌 Deepgram: Disconnected")

            DispatchQueue.main.async {
                self?.onDisconnected?()
            }
        }
    }

    /// Send audio data to Deepgram
    /// - Parameter audioData: Raw PCM Int16 audio data at 16kHz mono
    func sendAudio(_ audioData: Data) {
        guard isConnected, let webSocket = webSocket else {
            NSLog("⚠️ Deepgram: Not connected, can't send audio")
            return
        }

        isStreaming = true

        webSocket.send(.data(audioData)) { error in
            if let error = error {
                NSLog("❌ Deepgram: Error sending audio: %@", error.localizedDescription)
            }
        }
    }

    /// Signal end of audio stream (finalize current utterance)
    func finalizeUtterance() {
        guard isConnected else { return }

        let finalizeMessage = "{\"type\": \"Finalize\"}"
        webSocket?.send(.string(finalizeMessage)) { error in
            if let error = error {
                NSLog("⚠️ Deepgram: Error sending finalize: %@", error.localizedDescription)
            }
        }
    }

    /// Send keep-alive to maintain connection
    func keepAlive() {
        guard isConnected else { return }

        let keepAliveMessage = "{\"type\": \"KeepAlive\"}"
        webSocket?.send(.string(keepAliveMessage)) { _ in }
    }

    // MARK: - Private Methods

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleTextMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleTextMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue receiving
                if self.isConnected {
                    self.receiveMessage()
                }

            case .failure(let error):
                NSLog("❌ Deepgram: Receive error: %@", error.localizedDescription)
                self.isConnected = false
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            // Handle different message types
            switch response.type {
            case "Results":
                handleTranscriptResults(response)
            case "Metadata":
                NSLog("📋 Deepgram: Metadata received - request_id: %@", response.requestId ?? "unknown")
                DispatchQueue.main.async {
                    self.onConnected?()
                }
            case "SpeechStarted":
                NSLog("🎤 Deepgram: Speech started")
            case "UtteranceEnd":
                NSLog("🔚 Deepgram: Utterance end")
                // Finalize current utterance
                if !currentUtterance.isEmpty {
                    let final = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !final.isEmpty {
                        DispatchQueue.main.async {
                            self.onFinalTranscript?(final)
                        }
                    }
                    currentUtterance = ""
                }
            default:
                NSLog("📨 Deepgram: Unknown message type: %@", response.type ?? "nil")
            }

        } catch {
            // Try to parse as a simple error message
            NSLog("⚠️ Deepgram: Parse error: %@ - Raw: %@", error.localizedDescription, String(text.prefix(200)))
        }
    }

    private func handleTranscriptResults(_ response: DeepgramResponse) {
        guard let channel = response.channel,
              let alternatives = channel.alternatives,
              let firstAlt = alternatives.first else {
            return
        }

        let transcript = firstAlt.transcript ?? ""
        let isFinal = response.isFinal ?? false

        if transcript.isEmpty { return }

        if isFinal {
            // Final result for this segment
            currentUtterance = transcript
            NSLog("✅ Deepgram [FINAL]: %@", transcript)

            // Only early-finalize on questions (?) - let UtteranceEnd handle statements
            // This prevents "ok." from cutting off "ok. tell me about OOP"
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("?") {
                DispatchQueue.main.async {
                    self.onFinalTranscript?(trimmed)
                }
                currentUtterance = ""
            }
            // Statements (. !) wait for UtteranceEnd to allow continuation
        } else {
            // Interim result
            currentUtterance = transcript
            NSLog("📝 Deepgram [interim]: %@", transcript)

            DispatchQueue.main.async {
                self.onPartialTranscript?(transcript)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension DeepgramStreamingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        NSLog("✅ Deepgram: WebSocket connected")
        isConnected = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        NSLog("🔌 Deepgram: WebSocket closed with code: %d", closeCode.rawValue)
        isConnected = false
        isStreaming = false

        DispatchQueue.main.async {
            self.onDisconnected?()
        }
    }
}

// MARK: - Response Models

private struct DeepgramResponse: Codable {
    let type: String?
    let requestId: String?
    let channel: DeepgramChannel?
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case requestId = "request_id"
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case start
        case duration
    }
}

private struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]?
}

private struct DeepgramAlternative: Codable {
    let transcript: String?
    let confidence: Double?
    let words: [DeepgramWord]?
}

private struct DeepgramWord: Codable {
    let word: String?
    let start: Double?
    let end: Double?
    let confidence: Double?
}
