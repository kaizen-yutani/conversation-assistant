import Foundation
import AVFoundation

/// Voice Activity Detection Audio Recorder
/// Uses adaptive baseline detection - speech is detected when audio rises significantly
/// above the ambient noise level and ends when it falls back near baseline.
class VADAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var vadTimer: Timer?
    private var tempFileURL: URL?
    private var isListening = false

    // Adaptive VAD parameters - calibrated to filter AC/background noise
    private let speechMargin: Float = 18.0        // dB above baseline to detect speech (was 10.0)
    private let silenceMargin: Float = 10.0       // dB above baseline to consider "back to silence" (was 5.0)
    private let minSpeechDuration: TimeInterval = 0.6   // Minimum speech duration to process
    private let absoluteMinSpeechDb: Float = -35.0     // Absolute floor - ignore anything below this
    var silenceTimeout: TimeInterval = 1.0      // Time near baseline to end speech (configurable)
    private let baselineWindowSize: Int = 40            // ~2 seconds of samples for baseline (at 50ms intervals)
    private let baselineUpdateInterval: Int = 5         // Update baseline every N checks when quiet

    // Adaptive baseline tracking
    private var baselineBuffer: [Float] = []      // Rolling buffer of quiet levels
    private var currentBaseline: Float = -60.0    // Current estimated ambient noise level
    private var baselineUpdateCount: Int = 0

    // State tracking
    private var isSpeaking = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var peakLevel: Float = -100.0

    // Callbacks
    var onLevelUpdate: ((Float, Bool) -> Void)?
    var onSpeechSegment: ((Data) -> Void)?
    var onStatusChange: ((String) -> Void)?

    // Computed thresholds based on baseline
    private var speechThreshold: Float {
        return currentBaseline + speechMargin
    }

    private var silenceThreshold: Float {
        return currentBaseline + silenceMargin
    }

    func startListening() throws {
        // Reset baseline
        baselineBuffer = []
        currentBaseline = -60.0

        try startNewRecording()

        DispatchQueue.main.async {
            self.vadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.checkVAD()
            }
            RunLoop.main.add(self.vadTimer!, forMode: .common)
        }

        isListening = true
        onStatusChange?("🎤 Calibrating... (stay quiet briefly)")
    }

    func stopListening() {
        isListening = false
        vadTimer?.invalidate()
        vadTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startNewRecording() throws {
        audioRecorder?.stop()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("vad_\(UUID().uuidString).m4a")

        // Get audio input device (logging disabled)
        #if os(macOS)
        _ = AVCaptureDevice.default(for: .audio)
        #endif

        // Use 44.1kHz - works reliably with all devices including Bluetooth
        // AAC encoder handles the actual device capabilities
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        audioRecorder = try AVAudioRecorder(url: tempFileURL!, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        _ = audioRecorder?.record() ?? false
    }

    private var checkCount = 0
    private var lastLoggedDb: Float = -100.0

    private func updateBaseline(_ db: Float) {
        // Only update baseline when NOT speaking and level is reasonable
        guard !isSpeaking && db > -90.0 && db < -20.0 else { return }

        baselineUpdateCount += 1
        guard baselineUpdateCount >= baselineUpdateInterval else { return }
        baselineUpdateCount = 0

        // Add to rolling buffer
        baselineBuffer.append(db)
        if baselineBuffer.count > baselineWindowSize {
            baselineBuffer.removeFirst()
        }

        // Calculate baseline as the average of the quietest 50% of samples
        // This makes it robust to occasional spikes
        if baselineBuffer.count >= 10 {
            let sorted = baselineBuffer.sorted()
            let quietHalf = Array(sorted.prefix(sorted.count / 2))
            let newBaseline = quietHalf.reduce(0, +) / Float(quietHalf.count)

            // Smooth the baseline transition
            currentBaseline = currentBaseline * 0.7 + newBaseline * 0.3
        }
    }

    private func checkVAD() {
        guard isListening, let recorder = audioRecorder else { return }

        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let now = Date()

        checkCount += 1
        updateBaseline(db)

        let dynSpeechThreshold = speechThreshold
        let dynSilenceThreshold = silenceThreshold

        // Update status after initial calibration
        if checkCount == 20 && !isSpeaking {
            DispatchQueue.main.async {
                self.onStatusChange?("🎤 Listening...")
            }
        }

        let _ = db - currentBaseline
        let isAboveSpeech = db > dynSpeechThreshold
        lastLoggedDb = db

        DispatchQueue.main.async {
            self.onLevelUpdate?(db, self.isSpeaking)
        }

        // SPEECH DETECTION LOGIC
        let isAboveAbsoluteMin = db > absoluteMinSpeechDb
        if isAboveSpeech && isAboveAbsoluteMin {
            lastSpeechTime = now
            peakLevel = max(peakLevel, db)

            if !isSpeaking {
                isSpeaking = true
                speechStartTime = now
                peakLevel = db
                DispatchQueue.main.async {
                    self.onStatusChange?("🗣 Speaking...")
                }
            }
        } else if isSpeaking {
            let nearBaseline = db < dynSilenceThreshold
            let silenceDuration = lastSpeechTime.map { now.timeIntervalSince($0) } ?? 0

            if nearBaseline && silenceDuration > silenceTimeout {
                let peakAboveBaseline = peakLevel - currentBaseline

                if let startTime = speechStartTime {
                    let duration = now.timeIntervalSince(startTime)

                    if duration <= minSpeechDuration {
                        // Too short - skip
                        try? startNewRecording()
                    } else if peakAboveBaseline < speechMargin * 0.5 {
                        // Peak not significant - skip
                        try? startNewRecording()
                    } else {
                        // Process the audio
                        recorder.stop()
                        if let url = tempFileURL, let data = try? Data(contentsOf: url) {
                            DispatchQueue.main.async {
                                self.onStatusChange?("⏳ Processing...")
                                self.onSpeechSegment?(data)
                            }
                        }
                        try? startNewRecording()
                    }
                }

                isSpeaking = false
                speechStartTime = nil
                peakLevel = -100.0

                DispatchQueue.main.async {
                    self.onStatusChange?("🎤 Listening...")
                }
            }
        }
    }
}
