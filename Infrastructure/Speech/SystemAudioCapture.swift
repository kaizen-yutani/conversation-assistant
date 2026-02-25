import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system audio (Zoom, Teams, etc.) using ScreenCaptureKit
@available(macOS 13.0, *)
class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var isCapturing = false

    // VAD parameters (matching VADAudioRecorder)
    private let speechMargin: Float = 18.0
    private let silenceMargin: Float = 10.0
    private let minSpeechDuration: TimeInterval = 0.6
    private let absoluteMinSpeechDb: Float = -35.0
    private let silenceTimeout: TimeInterval = 0.8
    private let baselineWindowSize: Int = 40
    private let baselineUpdateInterval: Int = 5

    // Baseline tracking
    private var baselineBuffer: [Float] = []
    private var currentBaseline: Float = -60.0
    private var baselineUpdateCount: Int = 0

    // State tracking
    private var isSpeaking = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var peakLevel: Float = -100.0

    // Audio recording
    private var recordedSamples: [Float] = []
    private var sampleRate: Double = 48000.0

    // Callbacks
    var onLevelUpdate: ((Float, Bool) -> Void)?
    var onSpeechSegment: ((Data) -> Void)?
    var onStatusChange: ((String) -> Void)?

    private var speechThreshold: Float { currentBaseline + speechMargin }
    private var silenceThreshold: Float { currentBaseline + silenceMargin }

    func startCapturing() async throws {

        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

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

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "system.audio.capture"))
        try await stream?.startCapture()

        isCapturing = true
        baselineBuffer = []
        currentBaseline = -60.0

        DispatchQueue.main.async {
            self.onStatusChange?("🔊 Listening to system audio...")
        }
    }

    func stopCapturing() async {
        isCapturing = false
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: - SCStreamOutput

    private var formatLogged = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isCapturing else { return }

        // Get sample rate from format
        if !formatLogged, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                sampleRate = asbd.mSampleRate
            }
            formatLogged = true
        }

        // Get audio buffer list
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let size = MemoryLayout<AudioBufferList>.size

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            NSLog("🔊 SysAudio: Failed to get audio buffer: %d", status)
            return
        }

        // Extract samples from buffer
        let buffer = audioBufferList.mBuffers
        guard let data = buffer.mData else { return }

        // ScreenCaptureKit provides 32-bit float samples
        let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let floatPointer = data.bindMemory(to: Float.self, capacity: floatCount)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))

        // Calculate RMS level
        var rmsSum: Float = 0
        for sample in samples {
            rmsSum += sample * sample
        }
        let rms = sqrt(rmsSum / Float(max(samples.count, 1)))
        let db = 20 * log10(max(rms, 0.0000001))

        if isSpeaking {
            recordedSamples.append(contentsOf: samples)
        }

        processVAD(db: db)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("🔊 SystemAudio: Stream error: %@", error.localizedDescription)
        isCapturing = false
        DispatchQueue.main.async {
            self.onStatusChange?("⚠️ System audio stopped")
        }
    }

    // MARK: - VAD

    private var checkCount = 0

    private func updateBaseline(_ db: Float) {
        guard !isSpeaking && db > -90.0 && db < -20.0 else { return }

        baselineUpdateCount += 1
        guard baselineUpdateCount >= baselineUpdateInterval else { return }
        baselineUpdateCount = 0

        baselineBuffer.append(db)
        if baselineBuffer.count > baselineWindowSize {
            baselineBuffer.removeFirst()
        }

        if baselineBuffer.count >= 10 {
            let sorted = baselineBuffer.sorted()
            let quietHalf = Array(sorted.prefix(sorted.count / 2))
            let newBaseline = quietHalf.reduce(0, +) / Float(quietHalf.count)
            currentBaseline = currentBaseline * 0.7 + newBaseline * 0.3
        }
    }

    private func processVAD(db: Float) {
        let now = Date()
        checkCount += 1
        updateBaseline(db)

        DispatchQueue.main.async {
            self.onLevelUpdate?(db, self.isSpeaking)
        }

        let isAboveSpeech = db > speechThreshold && db > absoluteMinSpeechDb

        if isAboveSpeech {
            lastSpeechTime = now
            peakLevel = max(peakLevel, db)

            if !isSpeaking {
                isSpeaking = true
                speechStartTime = now
                peakLevel = db
                recordedSamples = []
                DispatchQueue.main.async {
                    self.onStatusChange?("🗣 Speaker detected...")
                }
            }
        } else if isSpeaking {
            let nearBaseline = db < silenceThreshold
            let silenceDuration = lastSpeechTime.map { now.timeIntervalSince($0) } ?? 0

            if nearBaseline && silenceDuration > silenceTimeout {
                let speechDuration = speechStartTime.map { now.timeIntervalSince($0) } ?? 0
                let peakAboveBaseline = peakLevel - currentBaseline

                if speechDuration > minSpeechDuration && peakAboveBaseline >= speechMargin * 0.5 {
                    if let audioData = convertSamplesToM4A() {
                        DispatchQueue.main.async {
                            self.onStatusChange?("⏳ Processing...")
                            self.onSpeechSegment?(audioData)
                        }
                    }
                }

                isSpeaking = false
                speechStartTime = nil
                peakLevel = -100.0
                recordedSamples = []

                DispatchQueue.main.async {
                    self.onStatusChange?("🔊 Listening to system audio...")
                }
            }
        }
    }

    private func convertSamplesToM4A() -> Data? {
        guard !recordedSamples.isEmpty else { return nil }

        // Write to temp WAV file, then convert to M4A for Whisper compatibility
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("sysaudio_\(UUID().uuidString).wav")
        let m4aURL = tempDir.appendingPathComponent("sysaudio_\(UUID().uuidString).m4a")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: m4aURL)
        }

        // Create WAV data
        var wavData = Data(createWAVHeader(sampleCount: recordedSamples.count))
        for sample in recordedSamples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16.littleEndian) { wavData.append(contentsOf: $0) }
        }

        do {
            try wavData.write(to: wavURL)

            // Convert to M4A using AVAssetWriter
            let asset = AVURLAsset(url: wavURL)
            let reader = try AVAssetReader(asset: asset)

            // Load tracks using async API (non-deprecated)
            var audioTrackResult: AVAssetTrack?
            let trackSemaphore = DispatchSemaphore(value: 0)
            Task {
                audioTrackResult = try? await asset.loadTracks(withMediaType: .audio).first
                trackSemaphore.signal()
            }
            trackSemaphore.wait()

            guard let audioTrack = audioTrackResult else {
                NSLog("❌ SysAudio: No audio track in WAV")
                return wavData // Fall back to WAV
            }

            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            reader.add(readerOutput)

            let writer = try AVAssetWriter(outputURL: m4aURL, fileType: .m4a)
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ])
            writer.add(writerInput)

            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            let queue = DispatchQueue(label: "audio.convert")
            let semaphore = DispatchSemaphore(value: 0)

            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        semaphore.signal()
                        break
                    }
                }
            }

            semaphore.wait()
            writer.finishWriting {}

            // Wait for writer to finish
            while writer.status == .writing {
                Thread.sleep(forTimeInterval: 0.01)
            }

            if writer.status == .completed {
                return try Data(contentsOf: m4aURL)
            } else {
                NSLog("❌ SysAudio: Writer failed: %@", writer.error?.localizedDescription ?? "unknown")
                return wavData
            }
        } catch {
            NSLog("❌ SysAudio: Conversion error: %@", error.localizedDescription)
            return wavData
        }
    }

    private func createWAVHeader(sampleCount: Int) -> [UInt8] {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(Int(sampleRate) * Int(channels) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let dataSize = UInt32(sampleCount * Int(blockAlign))
        let fileSize = dataSize + 36

        var header = [UInt8]()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        return header
    }
}
