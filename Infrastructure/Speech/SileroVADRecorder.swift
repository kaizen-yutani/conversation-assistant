import Foundation
import AVFoundation
import CoreML

/// Voice Activity Detection using Silero VAD CoreML model
/// 87.7% accuracy vs ~60% for dB-threshold based VAD
class SileroVADRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var vadModel: MLModel?
    private var isListening = false

    // Model expects 576 samples at 16kHz (36ms chunks)
    private let sampleRate: Double = 16000
    private let chunkSize: Int = 576
    private let speechThreshold: Float = AppConstants.Thresholds.speechThreshold

    // LSTM state (must persist between chunks)
    private var hiddenState: MLMultiArray?
    private var cellState: MLMultiArray?

    // Audio buffer for accumulating samples
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    // Speech segment tracking
    private var isSpeaking = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var recordedAudioData: [Float] = []

    // Parameters - tuned for Silero VAD accuracy
    private let minSpeechDuration: TimeInterval = AppConstants.Thresholds.minSpeechDuration
    private let silenceTimeout: TimeInterval = AppConstants.Thresholds.silenceTimeout

    // Callbacks (same interface as VADAudioRecorder)
    var onLevelUpdate: ((Float, Bool) -> Void)?
    var onSpeechSegment: ((Data) -> Void)?
    var onStatusChange: ((String) -> Void)?

    override init() {
        super.init()
        loadModel()
        initializeState()
    }

    private func loadModel() {
        let modelPath = Bundle.main.path(forResource: "SileroVAD", ofType: "mlmodelc")
            ?? "./SileroVAD.mlmodelc"

        let modelURL = URL(fileURLWithPath: modelPath)

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            vadModel = try MLModel(contentsOf: modelURL, configuration: config)
            NSLog("✅ Silero VAD model loaded successfully")
        } catch {
            NSLog("❌ Failed to load Silero VAD model: \(error)")
        }
    }

    private func initializeState() {
        do {
            hiddenState = try MLMultiArray(shape: [1, 128], dataType: .float32)
            cellState = try MLMultiArray(shape: [1, 128], dataType: .float32)

            // Initialize to zeros
            for i in 0..<128 {
                hiddenState?[i] = 0.0
                cellState?[i] = 0.0
            }
        } catch {
            NSLog("❌ Failed to initialize LSTM state: \(error)")
        }
    }

    func startListening() throws {
        guard vadModel != nil else {
            throw NSError(domain: "SileroVAD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        NSLog("🎤 Silero VAD: Starting...")

        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode

        guard let inputNode = inputNode else {
            throw NSError(domain: "SileroVAD", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio input"])
        }

        // Get native format and convert to 16kHz mono
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "SileroVAD", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create target format"])
        }

        // Install converter if sample rates differ
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw NSError(domain: "SileroVAD", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot create converter"])
        }

        // Tap audio at native rate and convert
        let bufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1) // 100ms buffer
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        try audioEngine?.start()
        isListening = true
        initializeState() // Reset LSTM state

        DispatchQueue.main.async {
            self.onStatusChange?("🎤 Silero VAD listening...")
        }

        NSLog("🎤 Silero VAD: Started successfully (16kHz, \(chunkSize) samples/chunk)")
    }

    func stopListening() {
        isListening = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        bufferLock.lock()
        audioBuffer.removeAll()
        recordedAudioData.removeAll()
        bufferLock.unlock()

        isSpeaking = false
        speechStartTime = nil
        lastSpeechTime = nil

        NSLog("🎤 Silero VAD: Stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // Convert to 16kHz
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let floatData = convertedBuffer.floatChannelData else {
            return
        }

        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(convertedBuffer.frameLength)))

        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)

        // Also store for recording during speech
        if isSpeaking {
            recordedAudioData.append(contentsOf: samples)
        }
        bufferLock.unlock()

        // Process complete chunks
        processChunks()
    }

    private func processChunks() {
        bufferLock.lock()

        while audioBuffer.count >= chunkSize {
            let chunk = Array(audioBuffer.prefix(chunkSize))
            audioBuffer.removeFirst(chunkSize)
            bufferLock.unlock()

            processVADChunk(chunk)

            bufferLock.lock()
        }

        bufferLock.unlock()
    }

    private func processVADChunk(_ chunk: [Float]) {
        guard let model = vadModel,
              let hidden = hiddenState,
              let cell = cellState else {
            return
        }

        do {
            // Create input array
            let audioInput = try MLMultiArray(shape: [1, NSNumber(value: chunkSize)], dataType: .float32)
            for (i, sample) in chunk.enumerated() {
                audioInput[i] = NSNumber(value: sample)
            }

            // Create prediction input
            let input = SileroVADInput(
                audio_input: audioInput,
                hidden_state: hidden,
                cell_state: cell
            )

            // Run inference
            let prediction = try model.prediction(from: input)

            // Extract outputs
            guard let vadOutput = prediction.featureValue(for: "vad_output")?.multiArrayValue,
                  let newHidden = prediction.featureValue(for: "new_hidden_state")?.multiArrayValue,
                  let newCell = prediction.featureValue(for: "new_cell_state")?.multiArrayValue else {
                return
            }

            // Update LSTM state
            hiddenState = newHidden
            cellState = newCell

            // Get speech probability
            let speechProb = vadOutput[0].floatValue
            let isSpeechDetected = speechProb > speechThreshold

            // Update UI
            let dbEquivalent = speechProb > 0.01 ? 20 * log10(speechProb) : -40
            DispatchQueue.main.async {
                self.onLevelUpdate?(Float(dbEquivalent), self.isSpeaking)
            }

            // Handle speech state transitions
            handleSpeechState(isSpeechDetected: isSpeechDetected, probability: speechProb)

        } catch {
            NSLog("❌ VAD inference error: \(error)")
        }
    }

    private func handleSpeechState(isSpeechDetected: Bool, probability: Float) {
        let now = Date()

        if isSpeechDetected {
            lastSpeechTime = now

            if !isSpeaking {
                // Speech just started
                isSpeaking = true
                speechStartTime = now

                bufferLock.lock()
                recordedAudioData.removeAll()
                bufferLock.unlock()

                NSLog("🟢 Silero VAD: Speech started (prob: %.2f)", probability)
                DispatchQueue.main.async {
                    self.onStatusChange?("🗣 Speaking... (conf: \(Int(probability * 100))%)")
                }
            }
        } else if isSpeaking {
            // Check if silence timeout exceeded
            let silenceDuration = lastSpeechTime.map { now.timeIntervalSince($0) } ?? 0

            if silenceDuration > silenceTimeout {
                let speechDuration = speechStartTime.map { now.timeIntervalSince($0) } ?? 0

                NSLog("🔴 Silero VAD: Speech ended - duration: %.2fs", speechDuration)

                if speechDuration >= minSpeechDuration {
                    // Export recorded audio
                    bufferLock.lock()
                    let audioData = recordedAudioData
                    recordedAudioData.removeAll()
                    bufferLock.unlock()

                    if !audioData.isEmpty {
                        let wavData = createWAVData(from: audioData)
                        NSLog("✅ Silero VAD: Processing %.2fs of speech (%d bytes)", speechDuration, wavData.count)

                        DispatchQueue.main.async {
                            self.onStatusChange?("⏳ Processing...")
                            self.onSpeechSegment?(wavData)
                        }
                    }
                } else {
                    NSLog("⏱️ Silero VAD: Too short (%.2fs < %.2fs)", speechDuration, minSpeechDuration)
                    bufferLock.lock()
                    recordedAudioData.removeAll()
                    bufferLock.unlock()
                }

                // Reset state
                isSpeaking = false
                speechStartTime = nil
                initializeState() // Reset LSTM for next utterance

                DispatchQueue.main.async {
                    self.onStatusChange?("🎤 Silero VAD listening...")
                }
            }
        }
    }

    private func createWAVData(from samples: [Float]) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateInt = UInt32(sampleRate)
        let byteRate = sampleRateInt * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert Float32 [-1, 1] to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: int16Value.littleEndian) { Array($0) })
        }

        return data
    }
}

// MARK: - CoreML Input Wrapper

private class SileroVADInput: MLFeatureProvider {
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
