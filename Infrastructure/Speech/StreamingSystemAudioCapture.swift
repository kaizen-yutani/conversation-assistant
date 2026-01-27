import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreML
import Accelerate

/// Streaming System Audio Capture - combines ScreenCaptureKit + Silero VAD + Deepgram streaming
/// Achieves ~300-500ms latency reduction by transcribing system audio during speech in real-time
@available(macOS 13.0, *)
class StreamingSystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var isCapturing = false

    // Silero VAD
    private var vadModel: MLModel?
    private var hiddenState: MLMultiArray?
    private var cellState: MLMultiArray?
    private let vadChunkSize: Int = 576  // 36ms chunks at 16kHz
    private let speechThreshold: Float = 0.5
    private var vadBuffer: [Float] = []

    // Deepgram streaming
    private var deepgramClient: DeepgramStreamingClient?

    // Audio resampling (48kHz → 16kHz)
    private let sourceSampleRate: Double = 48000
    private let targetSampleRate: Double = 16000
    private var resampleBuffer: [Float] = []

    // Speech state
    private var isSpeaking = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private let minSpeechDuration: TimeInterval = 0.3
    // Silero VAD used only for speech START detection - Deepgram handles utterance end via endpointing

    // Current transcription
    private var currentTranscript = ""
    private var hasDetectedQuestion = false

    // Callbacks
    var onTranscript: ((String, Bool) -> Void)?  // (text, isFinal)
    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: (() -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onLevelUpdate: ((Float, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    // Language setting
    private var language: String = "en"

    init(deepgramApiKey: String, language: String = "en") {
        self.language = language
        super.init()
        loadVADModel()
        initializeVADState()
        setupDeepgramClient(apiKey: deepgramApiKey)
    }

    // MARK: - Setup

    private func loadVADModel() {
        let modelPath = Bundle.main.path(forResource: "SileroVAD", ofType: "mlmodelc")
            ?? "./SileroVAD.mlmodelc"

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            vadModel = try MLModel(contentsOf: URL(fileURLWithPath: modelPath), configuration: config)
            NSLog("✅ StreamingSystemAudio: Silero model loaded")
        } catch {
            NSLog("❌ StreamingSystemAudio: Failed to load Silero model: %@", error.localizedDescription)
        }
    }

    private func initializeVADState() {
        do {
            hiddenState = try MLMultiArray(shape: [1, 128], dataType: .float32)
            cellState = try MLMultiArray(shape: [1, 128], dataType: .float32)
            for i in 0..<128 {
                hiddenState?[i] = 0.0
                cellState?[i] = 0.0
            }
        } catch {
            NSLog("❌ StreamingSystemAudio: Failed to initialize LSTM state: %@", error.localizedDescription)
        }
    }

    private func setupDeepgramClient(apiKey: String) {
        deepgramClient = DeepgramStreamingClient(apiKey: apiKey)

        deepgramClient?.onConnected = { [weak self] in
            NSLog("✅ StreamingSystemAudio: Deepgram connected")
            DispatchQueue.main.async {
                self?.onStatusChange?("🔊 Streaming ready...")
            }
        }

        deepgramClient?.onPartialTranscript = { [weak self] text in
            guard let self = self else { return }
            self.currentTranscript = text

            // Check for early question detection
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("?") && !self.hasDetectedQuestion {
                self.hasDetectedQuestion = true
                NSLog("❓ StreamingSystemAudio: Question detected early: %@", trimmed)
                DispatchQueue.main.async {
                    self.onTranscript?(trimmed, true)
                }
            } else {
                DispatchQueue.main.async {
                    self.onTranscript?(text, false)
                }
            }
        }

        deepgramClient?.onFinalTranscript = { [weak self] text in
            guard let self = self else { return }
            NSLog("✅ StreamingSystemAudio: Final transcript (Deepgram UtteranceEnd): %@", text)

            // Reset speech state - Deepgram detected utterance end
            self.isSpeaking = false
            self.speechStartTime = nil
            self.currentTranscript = ""
            self.hasDetectedQuestion = false
            self.initializeVADState()

            DispatchQueue.main.async {
                self.onTranscript?(text, true)
                self.onSpeechEnd?()
                self.onStatusChange?("🔊 Listening (streaming)...")
            }
        }

        deepgramClient?.onDisconnected = { [weak self] in
            NSLog("🔌 StreamingSystemAudio: Deepgram disconnected")
            DispatchQueue.main.async {
                self?.onStatusChange?("🔌 Disconnected")
            }
        }

        deepgramClient?.onError = { [weak self] error in
            NSLog("❌ StreamingSystemAudio: Deepgram error: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self?.onError?(error)
            }
        }
    }

    // MARK: - Capture Control

    func startCapturing() async throws {
        guard vadModel != nil else {
            throw NSError(domain: "StreamingSystemAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "VAD model not loaded"])
        }

        NSLog("🔊 StreamingSystemAudio: Starting...")

        // Check screen recording permission
        let hasPermission = CGPreflightScreenCaptureAccess()
        NSLog("🔊 StreamingSystemAudio: Screen recording permission = %@", hasPermission ? "YES" : "NO")

        if !hasPermission {
            NSLog("🔊 StreamingSystemAudio: Requesting screen recording permission...")
            CGRequestScreenCaptureAccess()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let nowHasPermission = CGPreflightScreenCaptureAccess()
            NSLog("🔊 StreamingSystemAudio: After request, permission = %@", nowHasPermission ? "YES" : "NO")
            if !nowHasPermission {
                throw NSError(domain: "StreamingSystemAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Screen recording permission denied"])
            }
        }

        // Setup ScreenCaptureKit FIRST (before Deepgram)
        NSLog("🔊 StreamingSystemAudio: Getting shareable content...")
        let content = try await SCShareableContent.current
        NSLog("🔊 StreamingSystemAudio: Found %d displays, %d apps", content.displays.count, content.applications.count)

        guard let display = content.displays.first else {
            throw NSError(domain: "StreamingSystemAudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        NSLog("🔊 StreamingSystemAudio: Using display %d", display.displayID)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // Minimal video (required but unused)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // Audio settings
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        NSLog("🔊 StreamingSystemAudio: Creating stream...")
        stream = SCStream(filter: filter, configuration: config, delegate: self)

        NSLog("🔊 StreamingSystemAudio: Adding audio output...")
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "streaming.system.audio"))

        NSLog("🔊 StreamingSystemAudio: Starting capture...")
        try await stream?.startCapture()
        NSLog("🔊 StreamingSystemAudio: Capture started!")

        // Connect to Deepgram AFTER ScreenCaptureKit is working
        NSLog("🔊 StreamingSystemAudio: Connecting to Deepgram...")
        deepgramClient?.connect(language: language)

        isCapturing = true
        initializeVADState()
        vadBuffer.removeAll()
        resampleBuffer.removeAll()

        DispatchQueue.main.async {
            self.onStatusChange?("🔊 Listening (streaming)...")
        }

        NSLog("🔊 StreamingSystemAudio: Started successfully")
    }

    func stopCapturing() async {
        isCapturing = false
        try? await stream?.stopCapture()
        stream = nil

        deepgramClient?.disconnect()

        vadBuffer.removeAll()
        resampleBuffer.removeAll()
        isSpeaking = false
        speechStartTime = nil
        lastSpeechTime = nil
        currentTranscript = ""
        hasDetectedQuestion = false

        NSLog("🔊 StreamingSystemAudio: Stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isCapturing else { return }

        // Get audio buffer
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        let buffer = audioBufferList.mBuffers
        guard let data = buffer.mData else { return }

        // ScreenCaptureKit provides 32-bit float samples at 48kHz
        let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let floatPointer = data.bindMemory(to: Float.self, capacity: floatCount)
        let samples48k = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))

        // Resample 48kHz → 16kHz (factor of 3)
        let samples16k = resample(samples48k, from: sourceSampleRate, to: targetSampleRate)

        // Calculate level for UI
        var rmsSum: Float = 0
        for sample in samples16k { rmsSum += sample * sample }
        let rms = sqrt(rmsSum / Float(max(samples16k.count, 1)))
        let db = 20 * log10(max(rms, 0.0000001))

        DispatchQueue.main.async {
            self.onLevelUpdate?(db, self.isSpeaking)
        }

        // Accumulate for VAD processing
        vadBuffer.append(contentsOf: samples16k)

        // Process VAD chunks
        processVADChunks()

        // If speaking, stream to Deepgram
        if isSpeaking {
            streamAudioToDeepgram(samples16k)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let errorDesc = error.localizedDescription
        NSLog("❌ StreamingSystemAudio: Stream error: %@", errorDesc)

        // Check if this is the known transient "application connection interrupted" error
        // This can happen during startup but doesn't always mean the stream failed
        if errorDesc.contains("application connection being interrupted") {
            NSLog("⚠️ StreamingSystemAudio: Ignoring transient connection error, stream may still work")
            // Don't propagate this error - it's often transient
            return
        }

        isCapturing = false
        DispatchQueue.main.async {
            self.onError?(error)
        }
    }

    // MARK: - Audio Resampling

    private func resample(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        let ratio = sourceRate / targetRate  // 48000/16000 = 3
        let outputLength = Int(Double(input.count) / ratio)
        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)

        // Simple decimation with averaging (low-pass filter)
        let step = Int(ratio)
        for i in 0..<outputLength {
            let start = i * step
            let end = min(start + step, input.count)
            var sum: Float = 0
            for j in start..<end {
                sum += input[j]
            }
            output[i] = sum / Float(end - start)
        }

        return output
    }

    // MARK: - VAD Processing

    private func processVADChunks() {
        while vadBuffer.count >= vadChunkSize {
            let chunk = Array(vadBuffer.prefix(vadChunkSize))
            vadBuffer.removeFirst(vadChunkSize)
            processVADChunk(chunk)
        }
    }

    private func processVADChunk(_ chunk: [Float]) {
        guard let model = vadModel,
              let hidden = hiddenState,
              let cell = cellState else {
            return
        }

        do {
            let audioInput = try MLMultiArray(shape: [1, NSNumber(value: vadChunkSize)], dataType: .float32)
            for (i, sample) in chunk.enumerated() {
                audioInput[i] = NSNumber(value: sample)
            }

            let input = StreamingSileroVADInput(audio_input: audioInput, hidden_state: hidden, cell_state: cell)
            let prediction = try model.prediction(from: input)

            guard let vadOutput = prediction.featureValue(for: "vad_output")?.multiArrayValue,
                  let newHidden = prediction.featureValue(for: "new_hidden_state")?.multiArrayValue,
                  let newCell = prediction.featureValue(for: "new_cell_state")?.multiArrayValue else {
                return
            }

            hiddenState = newHidden
            cellState = newCell

            let speechProb = vadOutput[0].floatValue
            let isSpeechDetected = speechProb > speechThreshold

            handleSpeechState(isSpeechDetected: isSpeechDetected, probability: speechProb)

        } catch {
            NSLog("❌ StreamingSystemAudio: VAD inference error: %@", error.localizedDescription)
        }
    }

    private func handleSpeechState(isSpeechDetected: Bool, probability: Float) {
        let now = Date()

        if isSpeechDetected {
            lastSpeechTime = now

            if !isSpeaking {
                isSpeaking = true
                speechStartTime = now
                currentTranscript = ""
                hasDetectedQuestion = false

                NSLog("🟢 StreamingSystemAudio: Speech started (prob: %.2f)", probability)

                DispatchQueue.main.async {
                    self.onSpeechStart?()
                    self.onStatusChange?("🗣 Speaker detected...")
                }
            }
        }
        // Speech END is handled by Deepgram's UtteranceEnd event, not Silero VAD timeout
        // This allows natural pauses in speech without cutting off the stream
    }

    private func streamAudioToDeepgram(_ samples: [Float]) {
        // Convert Float32 [-1, 1] to Int16 for Deepgram (linear16)
        var int16Data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * 32767.0)
            withUnsafeBytes(of: int16Value.littleEndian) { int16Data.append(contentsOf: $0) }
        }

        deepgramClient?.sendAudio(int16Data)
    }
}

// MARK: - CoreML Input Wrapper

private class StreamingSileroVADInput: MLFeatureProvider {
    let audio_input: MLMultiArray
    let hidden_state: MLMultiArray
    let cell_state: MLMultiArray

    var featureNames: Set<String> {
        return ["audio_input", "hidden_state", "cell_state"]
    }

    init(audio_input: MLMultiArray, hidden_state: MLMultiArray, cell_state: MLMultiArray) {
        self.audio_input = audio_input
        self.hidden_state = hidden_state
        self.cell_state = cell_state
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "audio_input": return MLFeatureValue(multiArray: audio_input)
        case "hidden_state": return MLFeatureValue(multiArray: hidden_state)
        case "cell_state": return MLFeatureValue(multiArray: cell_state)
        default: return nil
        }
    }
}
