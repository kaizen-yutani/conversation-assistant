#!/usr/bin/env swift
//
// Keyword Spotter Test Harness
// Records audio, sends to Groq Whisper, matches interview keywords
//
// Usage: swift keyword_spotter_test.swift <GROQ_API_KEY>
//
// Get your free API key at: https://console.groq.com
//

import Foundation
import AVFoundation
import Cocoa

// MARK: - Groq Whisper Client

class GroqWhisperClient {
    private let apiKey: String
    private let whisperURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let chatURL = "https://api.groq.com/openai/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Use Groq's LLM to fix/interpret the transcription
    func fixTranscription(_ text: String) async throws -> (fixed: String, latencyMs: Double) {
        let startTime = Date()

        let prompt = """
        You are an interview topic detector. The user said something during a technical interview, but speech recognition may have errors.

        Common interview topics: closures, hoisting, event loop, promises, async/await, prototypes, React hooks, useState, useEffect, virtual DOM, TypeScript, generics, linked list, hash map, trees, graphs, Big O, sorting, recursion, dynamic programming, system design, caching, load balancing, microservices, SOLID, design patterns, testing.

        Transcription: "\(text)"

        If this sounds like they're asking about an interview topic, respond with ONLY the topic name (e.g., "closure" or "event loop").
        If you can't determine the topic, respond with "unknown".

        Response (single word or short phrase only):
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",  // Fastest model on Groq
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 20,
            "temperature": 0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let fixed = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"

        return (fixed, latency)
    }

    func transcribe(audioData: Data, filename: String = "audio.wav") async throws -> (text: String, latencyMs: Double) {
        let startTime = Date()

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: whisperURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GroqAPI", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorBody])
        }

        struct Response: Codable { let text: String }
        let result = try JSONDecoder().decode(Response.self, from: data)

        return (result.text, latency)
    }
}

// MARK: - Keyword Matcher

enum InterviewTopic: String, CaseIterable {
    case closure, hoisting, eventLoop, promises, asyncAwait, prototypes
    case reactHooks, useState, useEffect, virtualDOM
    case typescript, generics
    case linkedList, hashMap, trees, graphs, bigO
    case sorting, recursion, dynamicProgramming
    case systemDesign, caching, loadBalancing, microservices
    case solid, designPatterns, testing

    var keywords: [String] {
        switch self {
        case .closure: return ["closure", "closures", "lexical scope"]
        case .hoisting: return ["hoisting", "hoist", "variable hoisting"]
        case .eventLoop: return ["event loop", "call stack", "callback queue", "microtask"]
        case .promises: return ["promise", "promises", "then catch"]
        case .asyncAwait: return ["async await", "async/await", "asynchronous"]
        case .prototypes: return ["prototype", "prototypes", "prototype chain"]
        case .reactHooks: return ["react hooks", "hooks", "custom hook"]
        case .useState: return ["usestate", "use state"]
        case .useEffect: return ["useeffect", "use effect"]
        case .virtualDOM: return ["virtual dom", "reconciliation"]
        case .typescript: return ["typescript", "type script"]
        case .generics: return ["generics", "generic types"]
        case .linkedList: return ["linked list", "linkedlist"]
        case .hashMap: return ["hash map", "hashmap", "hash table"]
        case .trees: return ["tree", "binary tree", "bst"]
        case .graphs: return ["graph", "graphs", "dfs", "bfs"]
        case .bigO: return ["big o", "time complexity", "space complexity"]
        case .sorting: return ["sorting", "quicksort", "mergesort"]
        case .recursion: return ["recursion", "recursive"]
        case .dynamicProgramming: return ["dynamic programming", "dp", "memoization"]
        case .systemDesign: return ["system design", "architecture"]
        case .caching: return ["caching", "cache", "redis"]
        case .loadBalancing: return ["load balancing", "load balancer"]
        case .microservices: return ["microservices", "micro services"]
        case .solid: return ["solid", "solid principles"]
        case .designPatterns: return ["design patterns", "singleton", "factory"]
        case .testing: return ["testing", "unit test", "tdd"]
        }
    }

    var displayName: String {
        switch self {
        case .closure: return "Closures"
        case .hoisting: return "Hoisting"
        case .eventLoop: return "Event Loop"
        case .promises: return "Promises"
        case .asyncAwait: return "Async/Await"
        case .prototypes: return "Prototypes"
        case .reactHooks: return "React Hooks"
        case .useState: return "useState"
        case .useEffect: return "useEffect"
        case .virtualDOM: return "Virtual DOM"
        case .typescript: return "TypeScript"
        case .generics: return "Generics"
        case .linkedList: return "Linked Lists"
        case .hashMap: return "Hash Maps"
        case .trees: return "Trees"
        case .graphs: return "Graphs"
        case .bigO: return "Big O"
        case .sorting: return "Sorting"
        case .recursion: return "Recursion"
        case .dynamicProgramming: return "Dynamic Programming"
        case .systemDesign: return "System Design"
        case .caching: return "Caching"
        case .loadBalancing: return "Load Balancing"
        case .microservices: return "Microservices"
        case .solid: return "SOLID"
        case .designPatterns: return "Design Patterns"
        case .testing: return "Testing"
        }
    }

    var quickAnswer: String {
        switch self {
        case .closure:
            return """
            CLOSURE: A function that retains access to its lexical scope even when executed outside that scope.

            function outer() {
              let x = 10;
              return function inner() { return x; }
            }
            const fn = outer();
            fn(); // 10 - still has access to x!

            Key points:
            • Created every time a function is created
            • Used for data privacy, callbacks, partial application
            """
        case .hoisting:
            return """
            HOISTING: JS moves declarations to top of scope during compilation.

            • var: hoisted + initialized to undefined
            • let/const: hoisted but NOT initialized (TDZ)
            • functions: fully hoisted (can call before declaration)

            console.log(x); // undefined
            console.log(y); // ReferenceError!
            var x = 1;
            let y = 2;
            """
        case .eventLoop:
            return """
            EVENT LOOP: How JS handles async operations

            1. Call Stack - runs sync code (LIFO)
            2. Web APIs - handles async (setTimeout, fetch)
            3. Microtask Queue - Promises, queueMicrotask
            4. Macrotask Queue - setTimeout, setInterval

            Order: Sync → All Microtasks → One Macrotask → Repeat
            """
        case .promises:
            return """
            PROMISE: Object representing eventual completion/failure of async operation

            States: pending → fulfilled OR rejected

            const p = new Promise((resolve, reject) => {
              // async work
              resolve(value); // or reject(error)
            });
            p.then(v => {}).catch(e => {}).finally(() => {});

            Promise.all([]) - all must succeed
            Promise.race([]) - first to settle
            Promise.allSettled([]) - wait for all
            """
        case .asyncAwait:
            return """
            ASYNC/AWAIT: Syntactic sugar over Promises

            async function getData() {
              try {
                const res = await fetch(url);
                return await res.json();
              } catch (e) {
                console.error(e);
              }
            }

            • async function always returns Promise
            • await pauses until Promise resolves
            • Use try/catch for error handling
            """
        default:
            return "Topic: \(displayName) - Add content for this topic"
        }
    }
}

class KeywordMatcher {
    func findMatch(in text: String) -> (topic: InterviewTopic, keyword: String, confidence: Double)? {
        let normalized = text.lowercased()

        for topic in InterviewTopic.allCases {
            for keyword in topic.keywords {
                if normalized.contains(keyword.lowercased()) {
                    return (topic, keyword, 1.0)
                }
            }
        }
        return nil
    }
}

// MARK: - Audio Recorder (simple approach using AVAudioRecorder)

class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var tempFileURL: URL?
    private var levelTimer: Timer?

    var onLevelUpdate: ((Float) -> Void)?

    func startRecording() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        self.tempFileURL = tempFile

        // M4A format works great with Whisper and is simple to record
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: tempFile, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        // Start level monitoring
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.audioRecorder?.updateMeters()
            let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
            // Convert dB to 0-100 scale (dB typically -160 to 0)
            let normalized = max(0, (level + 50) * 2)  // -50dB to 0dB -> 0 to 100
            DispatchQueue.main.async {
                self?.onLevelUpdate?(normalized)
            }
        }
    }

    func stopRecording() -> Data {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil

        guard let url = tempFileURL, let data = try? Data(contentsOf: url) else {
            return Data()
        }

        // Clean up
        try? FileManager.default.removeItem(at: url)
        return data
    }
}

// MARK: - Main Test App

class KeywordSpotterApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var resultLabel: NSTextField!
    var recordButton: NSButton!
    var latencyLabel: NSTextField!
    var levelIndicator: NSProgressIndicator!
    var levelLabel: NSTextField!

    let groqClient: GroqWhisperClient
    let matcher = KeywordMatcher()
    let recorder = AudioRecorder()
    var isRecording = false

    init(apiKey: String) {
        self.groqClient = GroqWhisperClient(apiKey: apiKey)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupAudioLevelCallback()
    }

    func setupAudioLevelCallback() {
        recorder.onLevelUpdate = { [weak self] level in
            self?.levelIndicator.doubleValue = Double(min(level * 5, 100))
            self?.levelLabel.stringValue = String(format: "Level: %.1f", level)
        }
    }

    func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyword Spotter Test"
        window.center()

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Title
        let titleLabel = NSTextField(labelWithString: "🎤 Interview Keyword Spotter")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.frame = NSRect(x: 20, y: 480, width: 560, height: 40)
        contentView.addSubview(titleLabel)

        // Instructions
        let instructions = NSTextField(labelWithString: "Press Record, say an interview topic (e.g., 'Tell me about closures'), then Stop")
        instructions.font = .systemFont(ofSize: 13)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 20, y: 450, width: 560, height: 20)
        contentView.addSubview(instructions)

        // Record button
        recordButton = NSButton(title: "🔴 Start Recording", target: self, action: #selector(toggleRecording))
        recordButton.bezelStyle = .rounded
        recordButton.font = .systemFont(ofSize: 16, weight: .medium)
        recordButton.frame = NSRect(x: 200, y: 390, width: 200, height: 40)
        contentView.addSubview(recordButton)

        // Audio level indicator
        levelIndicator = NSProgressIndicator(frame: NSRect(x: 100, y: 360, width: 350, height: 20))
        levelIndicator.style = .bar
        levelIndicator.minValue = 0
        levelIndicator.maxValue = 100
        levelIndicator.doubleValue = 0
        contentView.addSubview(levelIndicator)

        levelLabel = NSTextField(labelWithString: "Level: 0.0")
        levelLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        levelLabel.textColor = .secondaryLabelColor
        levelLabel.frame = NSRect(x: 460, y: 358, width: 100, height: 20)
        contentView.addSubview(levelLabel)

        // Status
        statusLabel = NSTextField(labelWithString: "Ready - speak clearly into your microphone")
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 20, y: 325, width: 560, height: 25)
        contentView.addSubview(statusLabel)

        // Latency
        latencyLabel = NSTextField(labelWithString: "")
        latencyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        latencyLabel.textColor = .systemGreen
        latencyLabel.alignment = .center
        latencyLabel.frame = NSRect(x: 20, y: 300, width: 560, height: 20)
        contentView.addSubview(latencyLabel)

        // Result box
        let resultBox = NSBox(frame: NSRect(x: 20, y: 20, width: 560, height: 270))
        resultBox.title = "Detected Topic"
        resultBox.titleFont = .systemFont(ofSize: 13, weight: .semibold)

        let scrollView = NSScrollView(frame: NSRect(x: 10, y: 10, width: 540, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        resultLabel = NSTextField(wrappingLabelWithString: "Waiting for audio...")
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        resultLabel.maximumNumberOfLines = 0

        scrollView.documentView = resultLabel
        resultBox.addSubview(scrollView)
        contentView.addSubview(resultBox)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
    }

    @objc func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        do {
            try recorder.startRecording()
            isRecording = true
            recordButton.title = "⏹ Stop Recording"
            statusLabel.stringValue = "🎙 Recording... Speak now!"
            statusLabel.textColor = .systemRed
            resultLabel.stringValue = "Listening..."
            latencyLabel.stringValue = ""
        } catch {
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
            statusLabel.textColor = .systemRed
        }
    }

    func stopRecording() {
        let audioData = recorder.stopRecording()
        isRecording = false
        recordButton.title = "🔴 Start Recording"
        statusLabel.stringValue = "Processing with Groq Whisper..."
        statusLabel.textColor = .systemOrange

        Task {
            await processAudio(audioData)
        }
    }

    func processAudio(_ audioData: Data) async {
        let totalStart = Date()

        do {
            // Step 1: Transcribe with Groq Whisper
            let (rawText, transcriptionLatency) = try await groqClient.transcribe(audioData: audioData, filename: "audio.m4a")

            // Step 2: Try direct keyword match first
            var match = matcher.findMatch(in: rawText)
            var llmLatency: Double = 0
            var fixedTopic: String? = nil

            // Step 3: If no match, use LLM to interpret
            if match == nil && !rawText.trimmingCharacters(in: .whitespaces).isEmpty {
                let (fixed, llmTime) = try await groqClient.fixTranscription(rawText)
                llmLatency = llmTime
                fixedTopic = fixed

                // Try matching the LLM's interpretation
                if fixed != "unknown" {
                    match = matcher.findMatch(in: fixed)
                }
            }

            let totalLatency = Date().timeIntervalSince(totalStart) * 1000

            await MainActor.run {
                if llmLatency > 0 {
                    latencyLabel.stringValue = String(format: "⚡ Whisper: %.0fms | LLM: %.0fms | Total: %.0fms", transcriptionLatency, llmLatency, totalLatency)
                } else {
                    latencyLabel.stringValue = String(format: "⚡ Whisper: %.0fms | Total: %.0fms", transcriptionLatency, totalLatency)
                }

                if let match = match {
                    statusLabel.stringValue = "✅ Detected: \(match.topic.displayName)"
                    statusLabel.textColor = .systemGreen

                    var details = "Raw transcription: \"\(rawText)\"\n"
                    if let fixed = fixedTopic, fixed != "unknown" {
                        details += "LLM interpreted as: \"\(fixed)\"\n"
                    }
                    details += "Matched keyword: \"\(match.keyword)\"\n"
                    details += "Confidence: \(Int(match.confidence * 100))%"

                    resultLabel.stringValue = """
                    \(details)

                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    \(match.topic.quickAnswer)
                    """
                } else {
                    statusLabel.stringValue = "❓ No topic matched"
                    statusLabel.textColor = .systemYellow

                    var details = "Raw transcription: \"\(rawText)\"\n"
                    if let fixed = fixedTopic {
                        details += "LLM interpretation: \"\(fixed)\"\n"
                    }

                    resultLabel.stringValue = """
                    \(details)

                    No interview topic detected.

                    Try saying things like:
                    • "Tell me about closures"
                    • "Explain the event loop"
                    • "What is hoisting"
                    • "How do promises work"
                    """
                }
            }
        } catch {
            await MainActor.run {
                statusLabel.stringValue = "❌ Error"
                statusLabel.textColor = .systemRed
                resultLabel.stringValue = "Error: \(error.localizedDescription)"
                latencyLabel.stringValue = ""
            }
        }
    }
}

// MARK: - Entry Point

guard CommandLine.arguments.count > 1 else {
    print("""
    Usage: swift keyword_spotter_test.swift <GROQ_API_KEY>

    Get your free API key at: https://console.groq.com

    Example:
      swift keyword_spotter_test.swift gsk_xxxxxxxxxxxxx
    """)
    exit(1)
}

let apiKey = CommandLine.arguments[1]
let app = NSApplication.shared
let delegate = KeywordSpotterApp(apiKey: apiKey)
app.delegate = delegate
app.run()
