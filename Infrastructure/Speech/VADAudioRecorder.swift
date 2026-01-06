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
    private let silenceTimeout: TimeInterval = 1.0      // Time near baseline to end speech
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
        NSLog("🎤 VAD: startListening called (adaptive mode)")

        // Reset baseline
        baselineBuffer = []
        currentBaseline = -60.0

        try startNewRecording()
        NSLog("🎤 VAD: Recording started, setting up timer")

        DispatchQueue.main.async {
            self.vadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.checkVAD()
            }
            RunLoop.main.add(self.vadTimer!, forMode: .common)
            NSLog("🎤 VAD: Timer scheduled on main run loop")
        }

        isListening = true
        NSLog("🎤 VAD: isListening = true")
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

        // Log current audio input device
        #if os(macOS)
        let audioDevice = AVCaptureDevice.default(for: .audio)
        let deviceName = audioDevice?.localizedName ?? "unknown"
        NSLog("🎙️ VAD: Audio input device: %@", deviceName)
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

        // Log actual recording format
        if let format = audioRecorder?.format {
            NSLog("🎙️ VAD: Recording format - sampleRate=%.0f, channels=%d",
                  format.sampleRate, format.channelCount)
        }

        let started = audioRecorder?.record() ?? false
        if !started {
            NSLog("❌ VAD: Failed to start recording!")
        }
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
        guard isListening, let recorder = audioRecorder else {
            NSLog("❌ VAD checkVAD: guard failed - isListening=\(isListening), recorder=\(audioRecorder != nil)")
            return
        }

        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let now = Date()

        checkCount += 1

        // Update baseline when quiet
        updateBaseline(db)

        // Calculate dynamic thresholds
        let dynSpeechThreshold = speechThreshold
        let dynSilenceThreshold = silenceThreshold

        // Log every ~1 second with adaptive info
        if checkCount % 20 == 0 {
            NSLog("🔊 VAD[%d]: db=%.1f, baseline=%.1f, speechThr=%.1f, absMin=%.1f, speaking=%@, peak=%.1f",
                  checkCount, db, currentBaseline, dynSpeechThreshold, absoluteMinSpeechDb,
                  isSpeaking ? "YES" : "NO", peakLevel)

            // Update status after calibration
            if checkCount == 20 && !isSpeaking {
                DispatchQueue.main.async {
                    self.onStatusChange?("🎤 Listening... (baseline: \(Int(self.currentBaseline)) dB)")
                }
            }
        }

        // Calculate how far above baseline we are
        let aboveBaseline = db - currentBaseline

        // Log threshold crossings
        let isAboveSpeech = db > dynSpeechThreshold
        let wasAboveSpeech = lastLoggedDb > dynSpeechThreshold
        if isAboveSpeech != wasAboveSpeech {
            NSLog("📊 VAD: Level crossed speech threshold! db=%.1f (threshold=%.1f, baseline=%.1f, +%.1f dB) direction=%@",
                  db, dynSpeechThreshold, currentBaseline, aboveBaseline,
                  isAboveSpeech ? "UP⬆️" : "DOWN⬇️")
        }

        lastLoggedDb = db

        // Update UI with current state
        DispatchQueue.main.async {
            self.onLevelUpdate?(db, self.isSpeaking)
        }

        // SPEECH DETECTION LOGIC
        // Must be above both relative threshold AND absolute minimum
        let isAboveAbsoluteMin = db > absoluteMinSpeechDb
        if isAboveSpeech && isAboveAbsoluteMin {
            // Audio is significantly above baseline - this is speech
            lastSpeechTime = now
            let oldPeak = peakLevel
            peakLevel = max(peakLevel, db)

            if peakLevel > oldPeak && checkCount % 10 == 0 {
                NSLog("📈 VAD: New peak: %.1f dB (+%.1f above baseline)", peakLevel, peakLevel - currentBaseline)
            }

            if !isSpeaking {
                // Speech just started
                isSpeaking = true
                speechStartTime = now
                peakLevel = db
                NSLog("🟢 VAD: Speech STARTED - db=%.1f, baseline=%.1f, +%.1f dB above",
                      db, currentBaseline, aboveBaseline)
                print("🟢 Speech STARTED at \(db) dB (+\(Int(aboveBaseline)) above baseline)")
                DispatchQueue.main.async {
                    self.onStatusChange?("🗣 Speaking... (+\(Int(aboveBaseline)) dB)")
                }
            }
        } else if isSpeaking {
            // We were speaking, check if we've returned to baseline
            let nearBaseline = db < dynSilenceThreshold
            let silenceDuration = lastSpeechTime.map { now.timeIntervalSince($0) } ?? 0

            if checkCount % 10 == 0 {
                NSLog("🔇 VAD: Checking silence - db=%.1f, silenceThr=%.1f, nearBaseline=%@, silenceDuration=%.2fs",
                      db, dynSilenceThreshold, nearBaseline ? "YES" : "NO", silenceDuration)
            }

            // End speech if we've been near baseline for long enough
            if nearBaseline && silenceDuration > silenceTimeout {
                let speechDuration = speechStartTime.map { now.timeIntervalSince($0) } ?? 0
                let peakAboveBaseline = peakLevel - currentBaseline

                NSLog("🔴 VAD: Speech ENDED - duration=%.2fs, peak=%.1f dB (+%.1f above baseline), silence=%.2fs",
                      speechDuration, peakLevel, peakAboveBaseline, silenceDuration)
                print("🔴 Speech ENDED after \(String(format: "%.1f", silenceDuration))s silence")

                if let startTime = speechStartTime {
                    let duration = now.timeIntervalSince(startTime)

                    if duration <= minSpeechDuration {
                        NSLog("⏱️ VAD: SKIPPED - Too short! duration=%.2fs (min=%.1fs)", duration, minSpeechDuration)
                        print("⏱️ Too short: \(duration)s - skipping")
                        try? startNewRecording()
                    } else if peakAboveBaseline < speechMargin * 0.5 {
                        // Peak wasn't significantly above baseline - probably just noise fluctuation
                        NSLog("🔇 VAD: SKIPPED - Peak not significant! peak=%.1f dB, only +%.1f above baseline (need +%.1f)",
                              peakLevel, peakAboveBaseline, speechMargin * 0.5)
                        print("🔇 Peak not significant enough - skipping")
                        try? startNewRecording()
                    } else {
                        // SUCCESS - Process the audio!
                        NSLog("✅ VAD: PROCESSING - duration=%.2fs, peak=%.1f dB (+%.1f above baseline)",
                              duration, peakLevel, peakAboveBaseline)
                        print("✅ Processing \(String(format: "%.1f", duration))s of speech (peak: +\(Int(peakAboveBaseline)) dB)")

                        recorder.stop()

                        if let url = tempFileURL, let data = try? Data(contentsOf: url) {
                            NSLog("🎙️ VAD: Got audio data %d bytes, calling onSpeechSegment", data.count)
                            DispatchQueue.main.async {
                                self.onStatusChange?("⏳ Processing...")
                                self.onSpeechSegment?(data)
                            }
                        } else {
                            NSLog("❌ VAD: Failed to get audio data from file")
                        }

                        try? startNewRecording()
                    }
                }

                // Reset state
                isSpeaking = false
                speechStartTime = nil
                peakLevel = -100.0
                NSLog("🔄 VAD: State reset - ready for new speech")

                DispatchQueue.main.async {
                    self.onStatusChange?("🎤 Listening... (baseline: \(Int(self.currentBaseline)) dB)")
                }
            } else if !nearBaseline {
                // Still above silence threshold but below speech - in "winding down" zone
                // Don't reset lastSpeechTime, let it accumulate
                if checkCount % 20 == 0 {
                    NSLog("🟡 VAD: In transition zone - db=%.1f (+%.1f above baseline), waiting for silence...",
                          db, aboveBaseline)
                }
            }
        }
    }
}
