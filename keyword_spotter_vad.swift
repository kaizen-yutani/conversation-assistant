#!/usr/bin/env swift
//
// Keyword Spotter with Voice Activity Detection (VAD)
// Continuously listens and automatically detects speech segments
//
// Usage: swift keyword_spotter_vad.swift <GROQ_API_KEY>
//

import Foundation
import AVFoundation
import Cocoa
import Speech

// MARK: - Voice Profile (Speaker Identification)

/// Stores voice characteristics extracted from SFVoiceAnalytics
class VoiceProfile: Codable {
    var avgPitch: Double = 0
    var pitchStdDev: Double = 0
    var avgJitter: Double = 0
    var avgShimmer: Double = 0
    var sampleCount: Int = 0

    private static let profilePath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".interview_master_voice_profile.json")
    }()

    /// Check if a voice profile exists
    static var exists: Bool {
        FileManager.default.fileExists(atPath: profilePath.path)
    }

    /// Load saved profile from disk
    static func load() -> VoiceProfile? {
        guard let data = try? Data(contentsOf: profilePath) else { return nil }
        return try? JSONDecoder().decode(VoiceProfile.self, from: data)
    }

    /// Save profile to disk
    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: VoiceProfile.profilePath)
        print("💾 Voice profile saved to: \(VoiceProfile.profilePath.path)")
    }

    /// Delete saved profile
    static func delete() {
        try? FileManager.default.removeItem(at: profilePath)
    }

    /// Update profile with new voice analytics sample
    func addSample(pitch: [Double], jitter: [Double], shimmer: [Double]) {
        guard !pitch.isEmpty else { return }

        let pitchAvg = pitch.reduce(0, +) / Double(pitch.count)
        let pitchVariance = pitch.map { ($0 - pitchAvg) * ($0 - pitchAvg) }.reduce(0, +) / Double(pitch.count)
        let pitchStd = sqrt(pitchVariance)

        let jitterAvg = jitter.isEmpty ? 0 : jitter.reduce(0, +) / Double(jitter.count)
        let shimmerAvg = shimmer.isEmpty ? 0 : shimmer.reduce(0, +) / Double(shimmer.count)

        // Running average
        let n = Double(sampleCount)
        avgPitch = (avgPitch * n + pitchAvg) / (n + 1)
        pitchStdDev = (pitchStdDev * n + pitchStd) / (n + 1)
        avgJitter = (avgJitter * n + jitterAvg) / (n + 1)
        avgShimmer = (avgShimmer * n + shimmerAvg) / (n + 1)
        sampleCount += 1
    }

    /// Compare incoming voice against this profile
    /// Returns similarity score 0.0 (different) to 1.0 (same person)
    func similarity(pitch: [Double], jitter: [Double], shimmer: [Double]) -> Double {
        guard sampleCount > 0, !pitch.isEmpty else { return 0.5 } // Unknown

        let incomingPitchAvg = pitch.reduce(0, +) / Double(pitch.count)
        let incomingJitterAvg = jitter.isEmpty ? avgJitter : jitter.reduce(0, +) / Double(jitter.count)
        let incomingShimmerAvg = shimmer.isEmpty ? avgShimmer : shimmer.reduce(0, +) / Double(shimmer.count)

        // Pitch is the strongest differentiator (fundamental frequency)
        // Allow 2 standard deviations of variation
        let pitchTolerance = max(pitchStdDev * 2, 20) // At least 20 Hz tolerance
        let pitchDiff = abs(incomingPitchAvg - avgPitch)
        let pitchScore = max(0, 1 - (pitchDiff / pitchTolerance))

        // Jitter and shimmer are secondary (voice quality)
        let jitterTolerance = max(avgJitter * 0.5, 0.01)
        let jitterDiff = abs(incomingJitterAvg - avgJitter)
        let jitterScore = max(0, 1 - (jitterDiff / jitterTolerance))

        let shimmerTolerance = max(avgShimmer * 0.5, 0.01)
        let shimmerDiff = abs(incomingShimmerAvg - avgShimmer)
        let shimmerScore = max(0, 1 - (shimmerDiff / shimmerTolerance))

        // Weighted average: pitch matters most
        return pitchScore * 0.6 + jitterScore * 0.2 + shimmerScore * 0.2
    }

    var description: String {
        return "VoiceProfile(pitch: \(String(format: "%.1f", avgPitch))Hz ±\(String(format: "%.1f", pitchStdDev)), jitter: \(String(format: "%.4f", avgJitter)), shimmer: \(String(format: "%.4f", avgShimmer)), samples: \(sampleCount))"
    }
}

// MARK: - Voice Analyzer (extracts features using Speech framework)

class VoiceAnalyzer {
    private let speechRecognizer: SFSpeechRecognizer?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Request speech recognition authorization
    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Extract voice analytics from audio file
    func analyzeAudio(url: URL, completion: @escaping (Result<(pitch: [Double], jitter: [Double], shimmer: [Double], text: String), Error>) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            completion(.failure(NSError(domain: "VoiceAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])))
            return
        }

        print("🎙️ Speech recognizer available, supports on-device: \(recognizer.supportsOnDeviceRecognition)")

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Voice analytics requires server-side processing (not available on-device)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false
        // Request voice analytics
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                print("❌ Recognition error: \(error)")
                completion(.failure(error))
                return
            }

            guard let result = result else {
                print("⚠️ No result yet")
                return
            }

            print("📝 Result - isFinal: \(result.isFinal), text: \"\(result.bestTranscription.formattedString.prefix(50))...\"")

            guard result.isFinal else { return }

            // Extract voice analytics
            var pitchValues: [Double] = []
            var jitterValues: [Double] = []
            var shimmerValues: [Double] = []

            if let metadata = result.speechRecognitionMetadata {
                print("📊 Got metadata, speakingRate: \(metadata.speakingRate), averagePauseDuration: \(metadata.averagePauseDuration)")

                if let voiceAnalytics = metadata.voiceAnalytics {
                    print("🔊 Got voiceAnalytics!")

                    // Pitch (fundamental frequency)
                    let pitchFeature = voiceAnalytics.pitch
                    print("   Pitch - acousticFeatureValuePerFrame type: \(type(of: pitchFeature.acousticFeatureValuePerFrame))")

                    if let pitch = pitchFeature.acousticFeatureValuePerFrame as? [Double] {
                        print("   Pitch values count: \(pitch.count)")
                        if pitch.count > 0 {
                            let nonZero = pitch.filter { $0 != 0 }
                            print("   Pitch sample (first 10): \(Array(pitch.prefix(10)))")
                            print("   Pitch non-zero count: \(nonZero.count), min: \(nonZero.min() ?? 0), max: \(nonZero.max() ?? 0)")
                        }
                        // Keep all non-zero values (pitch is in Hz, but might be normalized differently)
                        pitchValues = pitch.filter { $0 > 0 }
                    } else if let pitch = pitchFeature.acousticFeatureValuePerFrame as? [Float] {
                        print("   Pitch values (Float) count: \(pitch.count)")
                        pitchValues = pitch.map { Double($0) }.filter { $0 > 0 }
                    } else if let pitch = pitchFeature.acousticFeatureValuePerFrame as? [NSNumber] {
                        print("   Pitch values (NSNumber) count: \(pitch.count)")
                        pitchValues = pitch.map { $0.doubleValue }.filter { $0 > 0 }
                    }

                    // Jitter
                    if let jitter = voiceAnalytics.jitter.acousticFeatureValuePerFrame as? [Double] {
                        jitterValues = jitter.filter { $0 >= 0 && $0 < 1 }
                    } else if let jitter = voiceAnalytics.jitter.acousticFeatureValuePerFrame as? [Float] {
                        jitterValues = jitter.map { Double($0) }.filter { $0 >= 0 && $0 < 1 }
                    } else if let jitter = voiceAnalytics.jitter.acousticFeatureValuePerFrame as? [NSNumber] {
                        jitterValues = jitter.map { $0.doubleValue }.filter { $0 >= 0 && $0 < 1 }
                    }

                    // Shimmer
                    if let shimmer = voiceAnalytics.shimmer.acousticFeatureValuePerFrame as? [Double] {
                        shimmerValues = shimmer.filter { $0 >= 0 && $0 < 1 }
                    } else if let shimmer = voiceAnalytics.shimmer.acousticFeatureValuePerFrame as? [Float] {
                        shimmerValues = shimmer.map { Double($0) }.filter { $0 >= 0 && $0 < 1 }
                    } else if let shimmer = voiceAnalytics.shimmer.acousticFeatureValuePerFrame as? [NSNumber] {
                        shimmerValues = shimmer.map { $0.doubleValue }.filter { $0 >= 0 && $0 < 1 }
                    }

                    print("   Final: pitch=\(pitchValues.count), jitter=\(jitterValues.count), shimmer=\(shimmerValues.count)")
                } else {
                    print("⚠️ No voiceAnalytics in metadata")
                }
            } else {
                print("⚠️ No speechRecognitionMetadata")
            }

            let text = result.bestTranscription.formattedString
            completion(.success((pitchValues, jitterValues, shimmerValues, text)))
        }
    }
}

// MARK: - Scenario Logger

class ScenarioLogger {
    private var events: [[String: Any]] = []
    private let startTime = Date()
    private var scenarioName: String?
    private let outputDir: URL

    init() {
        // Save to ~/interview_scenarios/
        let home = FileManager.default.homeDirectoryForCurrentUser
        outputDir = home.appendingPathComponent("interview_scenarios", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func startScenario(_ name: String) {
        scenarioName = name
        events = []
        log("scenario_start", ["name": name])
        print("📝 Scenario started: \(name)")
    }

    func log(_ type: String, _ data: [String: Any] = [:]) {
        var event: [String: Any] = [
            "t_ms": Int(Date().timeIntervalSince(startTime) * 1000),
            "type": type
        ]
        for (key, value) in data {
            event[key] = value
        }
        events.append(event)
    }

    func save() -> URL? {
        guard !events.isEmpty else { return nil }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = scenarioName ?? "unnamed"
        let filename = "\(name)_\(timestamp).json"
        let fileURL = outputDir.appendingPathComponent(filename)

        let output: [String: Any] = [
            "scenario": name,
            "recorded_at": timestamp,
            "events": events,
            "summary": generateSummary()
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL)
            print("💾 Saved scenario to: \(fileURL.path)")
            return fileURL
        } catch {
            print("❌ Failed to save scenario: \(error)")
            return nil
        }
    }

    private func generateSummary() -> [String: Any] {
        var sttLatencies: [Double] = []
        var topicLatencies: [Double] = []
        var answerLatencies: [Double] = []
        var speechDurations: [Int] = []
        var silenceDurations: [Int] = []

        for event in events {
            let type = event["type"] as? String ?? ""
            switch type {
            case "stt_end":
                if let lat = event["latency_ms"] as? Double { sttLatencies.append(lat) }
            case "topic_end":
                if let lat = event["latency_ms"] as? Double { topicLatencies.append(lat) }
            case "answer_end":
                if let lat = event["latency_ms"] as? Double { answerLatencies.append(lat) }
            case "speech_end":
                if let dur = event["duration_ms"] as? Int { speechDurations.append(dur) }
            case "silence_end":
                if let dur = event["duration_ms"] as? Int { silenceDurations.append(dur) }
            default:
                break
            }
        }

        func avg(_ arr: [Double]) -> Double? {
            guard !arr.isEmpty else { return nil }
            return arr.reduce(0, +) / Double(arr.count)
        }
        func avgInt(_ arr: [Int]) -> Int? {
            guard !arr.isEmpty else { return nil }
            return arr.reduce(0, +) / arr.count
        }

        var summary: [String: Any] = [
            "total_events": events.count,
            "speech_segments": speechDurations.count,
            "api_calls": sttLatencies.count + topicLatencies.count + answerLatencies.count
        ]
        if let v = avg(sttLatencies) { summary["avg_stt_ms"] = v }
        if let v = avg(topicLatencies) { summary["avg_topic_ms"] = v }
        if let v = avg(answerLatencies) { summary["avg_answer_ms"] = v }
        if let v = avgInt(speechDurations) { summary["avg_speech_duration_ms"] = v }
        if let v = avgInt(silenceDurations) { summary["avg_silence_duration_ms"] = v }

        return summary
    }
}

// Global logger instance
let scenarioLogger = ScenarioLogger()

// MARK: - Groq Client

class GroqClient {
    private let apiKey: String
    private let whisperURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let chatURL = "https://api.groq.com/openai/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioData: Data, filename: String = "audio.m4a") async throws -> (text: String, latencyMs: Double) {
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
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct Response: Codable { let text: String }
        let result = try JSONDecoder().decode(Response.self, from: data)

        return (result.text, latency)
    }

    /// Generate a concise interview answer for a topic
    func generateAnswer(for topic: String, transcription: String) async throws -> (answer: String, latencyMs: Double) {
        let startTime = Date()

        let prompt = """
        You are a senior software engineer helping someone in a technical interview.

        Question asked: "\(transcription)"
        Topic: \(topic)

        Give a concise but complete interview answer. Include:
        1. One-line definition
        2. Key points (3-4 bullets)
        3. Quick code example if relevant (short!)
        4. One common interview follow-up or edge case

        Keep it SHORT - this needs to fit on screen and be read quickly. No fluff.
        Use plain text, no markdown headers.
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 400,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let answer = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No answer generated"

        return (answer, latency)
    }

    func detectTopic(_ text: String, context: String, lastTopic: String?) async throws -> (topic: String, latencyMs: Double) {
        let startTime = Date()

        let lastTopicHint = lastTopic != nil ? "Last discussed topic: \(lastTopic!)" : "No previous topic"

        let prompt = """
        You are an interview topic detector. Analyze the transcription and conversation context.

        KNOWN TOPICS (use exact names):

        JavaScript/Frontend:
        closure, hoisting, eventLoop, promises, asyncAwait, prototypes, this, scope, callbacks, modules, dom, eventDelegation, debounce, throttle

        React:
        reactHooks, useState, useEffect, useContext, useReducer, useMemo, useCallback, virtualDOM, jsx, props, state, lifecycle, contextApi, redux, ssr, hydration

        TypeScript:
        typescript, generics, interfaces, types, enums, decorators, typeGuards, utilityTypes

        Java/OOP:
        jvm, jdk, jre, garbageCollection, heap, stack, oop, inheritance, polymorphism, encapsulation, abstraction, abstractClass, interface, overloading, overriding, constructor, staticKeyword, finalKeyword, immutability, string, stringBuilder, stringBuffer

        Java Collections:
        collections, arrayList, linkedList, hashMap, hashSet, treeSet, treeMap, queue, stack, iterator, comparable, comparator

        Java Concurrency:
        threads, process, synchronized, volatile, deadlock, raceCondition, threadPool, executors, locks, semaphore, atomicVariables, concurrentCollections

        Java 8+:
        lambda, streamApi, optional, functionalInterface, methodReference, defaultMethods, completableFuture

        Java Exceptions:
        exceptions, checkedExceptions, uncheckedExceptions, trycatch, finally, throw, throws, customExceptions

        Data Structures:
        array, linkedList, hashMap, hashTable, trees, binaryTree, bst, avl, redBlack, heap, minHeap, maxHeap, graphs, trie, stack, queue, deque, priorityQueue

        Algorithms:
        bigO, timeComplexity, spaceComplexity, sorting, quickSort, mergeSort, heapSort, binarySearch, recursion, dynamicProgramming, greedy, backtracking, bfs, dfs, dijkstra, topologicalSort, slidingWindow, twoPointers

        System Design:
        systemDesign, caching, redis, memcached, loadBalancing, cdn, dns, database, sql, nosql, sharding, replication, cap, consistency, availability, partitioning, messageQueue, kafka, rabbitmq, microservices, monolith, api, rest, graphql, websockets, oauth, jwt, ssl, rateLimit

        Design Patterns:
        singleton, factory, abstractFactory, builder, prototype, adapter, decorator, facade, proxy, observer, strategy, command, state, templateMethod, dependencyInjection, ioc, solid, dryPrinciple, kiss, yagni

        Testing:
        testing, unitTest, integrationTest, e2eTest, tdd, bdd, mocking, stubbing, testCoverage, junit, mockito

        DevOps/Cloud:
        docker, kubernetes, ci, cd, jenkins, git, gitflow, aws, azure, gcp, terraform, monitoring, logging

        \(lastTopicHint)

        Recent conversation:
        \(context)

        Current utterance: "\(text)"

        INSTRUCTIONS:
        1. If this is clearly a NEW question about a DIFFERENT topic → return the new topic name (ONE WORD from the list above)
        2. If this is a FOLLOW-UP request (e.g., "tell me more", "dig deeper", "elaborate", "what about X") → return "followUp"
        3. If the person is ANSWERING/EXPLAINING (long response, not asking) → return "answer"
        4. If unclear but we have a last topic and it seems related → return "followUp"
        5. Only return "unknown" if there's NO last topic AND the question doesn't match any known topic

        CRITICAL: Return ONLY ONE WORD - the topic name or "followUp" or "answer" or "unknown". No explanations.

        Mapping rules:
        - "Clojure" or "closure" → closure
        - "hash map", "hashmap", "hash table" → hashMap
        - "linked list" → linkedList
        - "big O", "time complexity", "complexity" → bigO
        - "event loop" → eventLoop
        - "checked exceptions", "unchecked exceptions" → exceptions
        - "garbage collection", "GC" → garbageCollection
        - "dependency injection", "DI" → dependencyInjection
        - "abstract class" → abstractClass
        - "stream api", "streams" → streamApi
        - "async await" → asyncAwait
        - "react hooks" → reactHooks
        - "virtual DOM" → virtualDOM
        - "dynamic programming", "DP" → dynamicProgramming
        - "system design" → systemDesign
        - "load balancing" → loadBalancing
        - "design patterns" → designPatterns

        Respond with ONLY ONE word: the exact topic name, "followUp", "answer", or "unknown".
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 20,
            "temperature": 0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let topic = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"

        return (topic, latency)
    }

    /// Check if utterance is complete or needs more context
    /// Returns: "complete" | "incomplete" | "filler"
    func checkCompleteness(_ text: String, buffer: String, context: String) async throws -> (status: String, latencyMs: Double) {
        let startTime = Date()

        let bufferContext = buffer.isEmpty ? "No previous buffer." : "Buffered text: \"\(buffer)\""
        let combinedText = buffer.isEmpty ? text : "\(buffer) \(text)"

        let prompt = """
        Classify if this speech is complete. Be BIASED TOWARD "complete" - only say "incomplete" if CLEARLY cut off mid-sentence.

        \(bufferContext)
        New text: "\(text)"
        Combined: "\(combinedText)"

        Rules:
        1. "filler" = ONLY if text is just "Hmm", "Um", "Uh", "Okay", "Right" (1-2 words, no real content)
        2. "incomplete" = ONLY if clearly cut off mid-sentence like "What is the" or "Can you explain" (missing object)
        3. "complete" = DEFAULT. Any full sentence, question, or statement. When in doubt, say complete.

        Examples:
        - "What is the difference between JDK and JVM?" → complete
        - "Okay good. Now can you explain?" → complete (it's a question, even if vague)
        - "What is the" → incomplete (cut off)
        - "Can you explain" → incomplete (missing what to explain)
        - "Hmm" → filler
        - "The four pillars of OOP" → complete (statement)
        - "Tell me about closures" → complete
        - "And also" → incomplete

        Respond with ONLY: complete, incomplete, or filler
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 10,
            "temperature": 0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let status = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "complete"

        return (status, latency)
    }

    /// Generate follow-up answer for current topic
    func generateFollowUpAnswer(for topic: String, transcription: String, context: String) async throws -> (answer: String, latencyMs: Double) {
        let startTime = Date()

        let prompt = """
        You are a senior software engineer helping someone in a technical interview.

        The interviewer asked for more details about: \(topic)
        Follow-up request: "\(transcription)"

        Recent conversation:
        \(context)

        Provide ADDITIONAL information about \(topic) that wasn't covered before:
        - Go deeper into implementation details
        - Cover edge cases or gotchas
        - Provide a more complex example
        - Mention related concepts or trade-offs

        Keep it concise but insightful. Use plain text, no markdown headers.
        """

        var request = URLRequest(url: URL(string: chatURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 500,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime) * 1000

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let answer = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No answer generated"

        return (answer, latency)
    }
}

// MARK: - Conversation Context (tracks history for follow-ups)

class ConversationContext {
    struct Utterance {
        let text: String
        let speaker: Speaker
        let topic: String?
        let timestamp: Date
    }

    enum Speaker: String {
        case interviewer
        case interviewee
        case unknown
    }

    private var history: [Utterance] = []
    private(set) var currentTopic: String?
    private let maxHistory = 10

    /// Classify speaker based on heuristics
    func classifySpeaker(text: String) -> Speaker {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        let wordCount = words.count
        let lowercased = trimmed.lowercased()

        // Question indicators
        let hasQuestionMark = trimmed.contains("?")
        let startsWithQuestion = lowercased.hasPrefix("what") ||
                                  lowercased.hasPrefix("how") ||
                                  lowercased.hasPrefix("why") ||
                                  lowercased.hasPrefix("can you") ||
                                  lowercased.hasPrefix("could you") ||
                                  lowercased.hasPrefix("tell me") ||
                                  lowercased.hasPrefix("explain") ||
                                  lowercased.hasPrefix("describe") ||
                                  lowercased.hasPrefix("walk me")

        let isFollowUp = lowercased.contains("tell me more") ||
                         lowercased.contains("dig deeper") ||
                         lowercased.contains("elaborate") ||
                         lowercased.contains("can you expand") ||
                         lowercased.contains("more details") ||
                         lowercased.contains("give me an example")

        // Short questions = interviewer
        if wordCount < 20 && (hasQuestionMark || startsWithQuestion || isFollowUp) {
            return .interviewer
        }

        // Long explanations = interviewee
        if wordCount > 30 {
            return .interviewee
        }

        // Medium length with technical terms might be interviewee answering
        if wordCount > 15 {
            return .interviewee
        }

        return .unknown
    }

    /// Check if this is a follow-up request
    func isFollowUp(text: String) -> Bool {
        let lowercased = text.lowercased()
        let followUpPhrases = [
            "tell me more", "dig deeper", "elaborate", "expand on",
            "more details", "give me an example", "can you explain",
            "what else", "go deeper", "more about", "continue"
        ]
        return followUpPhrases.contains { lowercased.contains($0) }
    }

    /// Add utterance to history
    func addUtterance(text: String, topic: String?) {
        let speaker = classifySpeaker(text: text)
        let utterance = Utterance(text: text, speaker: speaker, topic: topic, timestamp: Date())
        history.append(utterance)

        // Update current topic if we detected one
        if let topic = topic, topic != "unknown", topic != "followUp" {
            currentTopic = topic
        }

        // Trim history
        if history.count > maxHistory {
            history.removeFirst()
        }

        print("📝 [\(speaker.rawValue)] \(text.prefix(50))... | Topic: \(topic ?? "none")")
    }

    /// Get recent context for LLM
    func getContextForLLM() -> String {
        guard !history.isEmpty else { return "No previous conversation." }

        let recent = history.suffix(5)
        return recent.map { utterance in
            let topicStr = utterance.topic != nil ? " [topic: \(utterance.topic!)]" : ""
            return "[\(utterance.speaker.rawValue)]: \(utterance.text)\(topicStr)"
        }.joined(separator: "\n")
    }

    /// Get the last topic discussed (for follow-ups)
    var lastTopic: String? {
        return currentTopic
    }

    func clear() {
        history.removeAll()
        currentTopic = nil
    }
}

// MARK: - Keyword Matcher (simplified)

enum InterviewTopic: String, CaseIterable {
    // JavaScript/Frontend
    case closure, hoisting, eventLoop, promises, asyncAwait, prototypes, scope, callbacks, modules, dom, eventDelegation, debounce, throttle
    // React
    case reactHooks, useState, useEffect, useContext, useReducer, useMemo, useCallback, virtualDOM, jsx, props, state, lifecycle, contextApi, redux, ssr, hydration
    // TypeScript
    case typescript, generics, interfaces, types, enums, decorators, typeGuards
    // Java/OOP
    case jvm, jdk, jre, garbageCollection, heap, stack, oop, inheritance, polymorphism, encapsulation, abstraction, abstractClass, interface_, overloading, overriding, constructor, staticKeyword, finalKeyword, immutability, string, stringBuilder, stringBuffer
    // Java Collections
    case collections, arrayList, linkedList, hashMap, hashSet, treeSet, treeMap, queue, iterator, comparable, comparator
    // Java Concurrency
    case threads, process, synchronized, volatile, deadlock, raceCondition, threadPool, executors, locks, semaphore, atomicVariables
    // Java 8+
    case lambda, streamApi, optional, functionalInterface, methodReference, defaultMethods, completableFuture
    // Java Exceptions
    case exceptions, checkedExceptions, uncheckedExceptions, trycatch
    // Data Structures
    case array, trees, binaryTree, bst, avl, graphs, trie, deque, priorityQueue
    // Algorithms
    case bigO, timeComplexity, spaceComplexity, sorting, quickSort, mergeSort, heapSort, binarySearch, recursion, dynamicProgramming, greedy, backtracking, bfs, dfs, dijkstra, slidingWindow, twoPointers
    // System Design
    case systemDesign, caching, redis, loadBalancing, cdn, database, sql, nosql, sharding, replication, cap, messageQueue, kafka, microservices, api, rest, graphql, websockets, oauth, jwt, rateLimit
    // Design Patterns
    case singleton, factory, builder, adapter, decorator, facade, proxy, observer, strategy, command, dependencyInjection, ioc, solid
    // Testing
    case testing, unitTest, integrationTest, tdd, mocking, junit, mockito
    // DevOps
    case docker, kubernetes, ci, cd, git, aws

    var displayName: String {
        switch self {
        // JavaScript
        case .closure: return "Closures"
        case .hoisting: return "Hoisting"
        case .eventLoop: return "Event Loop"
        case .promises: return "Promises"
        case .asyncAwait: return "Async/Await"
        case .prototypes: return "Prototypes"
        case .scope: return "Scope"
        case .callbacks: return "Callbacks"
        case .modules: return "Modules"
        case .dom: return "DOM"
        case .eventDelegation: return "Event Delegation"
        case .debounce: return "Debounce"
        case .throttle: return "Throttle"
        // React
        case .reactHooks: return "React Hooks"
        case .useState: return "useState"
        case .useEffect: return "useEffect"
        case .useContext: return "useContext"
        case .useReducer: return "useReducer"
        case .useMemo: return "useMemo"
        case .useCallback: return "useCallback"
        case .virtualDOM: return "Virtual DOM"
        case .jsx: return "JSX"
        case .props: return "Props"
        case .state: return "State"
        case .lifecycle: return "Lifecycle"
        case .contextApi: return "Context API"
        case .redux: return "Redux"
        case .ssr: return "SSR"
        case .hydration: return "Hydration"
        // TypeScript
        case .typescript: return "TypeScript"
        case .generics: return "Generics"
        case .interfaces: return "Interfaces"
        case .types: return "Types"
        case .enums: return "Enums"
        case .decorators: return "Decorators"
        case .typeGuards: return "Type Guards"
        // Java/OOP
        case .jvm: return "JVM"
        case .jdk: return "JDK"
        case .jre: return "JRE"
        case .garbageCollection: return "Garbage Collection"
        case .heap: return "Heap Memory"
        case .stack: return "Stack Memory"
        case .oop: return "OOP"
        case .inheritance: return "Inheritance"
        case .polymorphism: return "Polymorphism"
        case .encapsulation: return "Encapsulation"
        case .abstraction: return "Abstraction"
        case .abstractClass: return "Abstract Class"
        case .interface_: return "Interface"
        case .overloading: return "Overloading"
        case .overriding: return "Overriding"
        case .constructor: return "Constructor"
        case .staticKeyword: return "Static Keyword"
        case .finalKeyword: return "Final Keyword"
        case .immutability: return "Immutability"
        case .string: return "String"
        case .stringBuilder: return "StringBuilder"
        case .stringBuffer: return "StringBuffer"
        // Java Collections
        case .collections: return "Collections"
        case .arrayList: return "ArrayList"
        case .linkedList: return "LinkedList"
        case .hashMap: return "HashMap"
        case .hashSet: return "HashSet"
        case .treeSet: return "TreeSet"
        case .treeMap: return "TreeMap"
        case .queue: return "Queue"
        case .iterator: return "Iterator"
        case .comparable: return "Comparable"
        case .comparator: return "Comparator"
        // Java Concurrency
        case .threads: return "Threads"
        case .process: return "Process"
        case .synchronized: return "Synchronized"
        case .volatile: return "Volatile"
        case .deadlock: return "Deadlock"
        case .raceCondition: return "Race Condition"
        case .threadPool: return "Thread Pool"
        case .executors: return "Executors"
        case .locks: return "Locks"
        case .semaphore: return "Semaphore"
        case .atomicVariables: return "Atomic Variables"
        // Java 8+
        case .lambda: return "Lambda"
        case .streamApi: return "Stream API"
        case .optional: return "Optional"
        case .functionalInterface: return "Functional Interface"
        case .methodReference: return "Method Reference"
        case .defaultMethods: return "Default Methods"
        case .completableFuture: return "CompletableFuture"
        // Java Exceptions
        case .exceptions: return "Exceptions"
        case .checkedExceptions: return "Checked Exceptions"
        case .uncheckedExceptions: return "Unchecked Exceptions"
        case .trycatch: return "Try-Catch"
        // Data Structures
        case .array: return "Array"
        case .trees: return "Trees"
        case .binaryTree: return "Binary Tree"
        case .bst: return "BST"
        case .avl: return "AVL Tree"
        case .graphs: return "Graphs"
        case .trie: return "Trie"
        case .deque: return "Deque"
        case .priorityQueue: return "Priority Queue"
        // Algorithms
        case .bigO: return "Big O"
        case .timeComplexity: return "Time Complexity"
        case .spaceComplexity: return "Space Complexity"
        case .sorting: return "Sorting"
        case .quickSort: return "Quick Sort"
        case .mergeSort: return "Merge Sort"
        case .heapSort: return "Heap Sort"
        case .binarySearch: return "Binary Search"
        case .recursion: return "Recursion"
        case .dynamicProgramming: return "Dynamic Programming"
        case .greedy: return "Greedy"
        case .backtracking: return "Backtracking"
        case .bfs: return "BFS"
        case .dfs: return "DFS"
        case .dijkstra: return "Dijkstra"
        case .slidingWindow: return "Sliding Window"
        case .twoPointers: return "Two Pointers"
        // System Design
        case .systemDesign: return "System Design"
        case .caching: return "Caching"
        case .redis: return "Redis"
        case .loadBalancing: return "Load Balancing"
        case .cdn: return "CDN"
        case .database: return "Database"
        case .sql: return "SQL"
        case .nosql: return "NoSQL"
        case .sharding: return "Sharding"
        case .replication: return "Replication"
        case .cap: return "CAP Theorem"
        case .messageQueue: return "Message Queue"
        case .kafka: return "Kafka"
        case .microservices: return "Microservices"
        case .api: return "API"
        case .rest: return "REST"
        case .graphql: return "GraphQL"
        case .websockets: return "WebSockets"
        case .oauth: return "OAuth"
        case .jwt: return "JWT"
        case .rateLimit: return "Rate Limiting"
        // Design Patterns
        case .singleton: return "Singleton"
        case .factory: return "Factory"
        case .builder: return "Builder"
        case .adapter: return "Adapter"
        case .decorator: return "Decorator"
        case .facade: return "Facade"
        case .proxy: return "Proxy"
        case .observer: return "Observer"
        case .strategy: return "Strategy"
        case .command: return "Command"
        case .dependencyInjection: return "Dependency Injection"
        case .ioc: return "IoC"
        case .solid: return "SOLID"
        // Testing
        case .testing: return "Testing"
        case .unitTest: return "Unit Testing"
        case .integrationTest: return "Integration Testing"
        case .tdd: return "TDD"
        case .mocking: return "Mocking"
        case .junit: return "JUnit"
        case .mockito: return "Mockito"
        // DevOps
        case .docker: return "Docker"
        case .kubernetes: return "Kubernetes"
        case .ci: return "CI"
        case .cd: return "CD"
        case .git: return "Git"
        case .aws: return "AWS"
        }
    }

    var quickAnswer: String {
        switch self {
        case .closure:
            return """
            CLOSURE: Function that retains access to its outer scope.

            function outer() {
              let x = 10;
              return function inner() { return x; }
            }
            const fn = outer();
            fn(); // 10
            """
        case .hoisting:
            return """
            HOISTING: Declarations moved to top of scope.

            • var: hoisted, initialized to undefined
            • let/const: hoisted but TDZ (Temporal Dead Zone)
            • functions: fully hoisted
            """
        case .eventLoop:
            return """
            EVENT LOOP: Handles async operations.

            1. Call Stack (sync)
            2. Microtasks (Promises) - run first
            3. Macrotasks (setTimeout) - run after
            """
        case .promises:
            return """
            PROMISE: Async operation result.

            States: pending → fulfilled/rejected
            Methods: .then(), .catch(), .finally()
            Static: Promise.all(), Promise.race()
            """
        case .asyncAwait:
            return """
            ASYNC/AWAIT: Promise syntax sugar.

            async function fn() {
              const result = await promise;
              return result;
            }
            """
        default:
            return "Topic: \(displayName)"
        }
    }
}

class KeywordMatcher {
    func findMatch(in text: String) -> InterviewTopic? {
        let normalized = text.lowercased()
        // Try to match by rawValue (topic name)
        for topic in InterviewTopic.allCases {
            if normalized.contains(topic.rawValue.lowercased()) {
                return topic
            }
        }
        return nil
    }
}

// MARK: - Voice Activity Detection Audio Recorder (using AVAudioRecorder)

class VADAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var vadTimer: Timer?
    private var tempFileURL: URL?
    private var isListening = false

    // VAD parameters (calibrated for typical mic: silence ~-80dB, speech ~-30dB)
    private let speechThreshold: Float = -40.0   // dB - speech is louder than this
    private let silenceThreshold: Float = -55.0  // dB - below this is silence
    private let minSpeechDuration: TimeInterval = 0.5
    private let silenceTimeout: TimeInterval = 1.3

    // State tracking
    private var isSpeaking = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?

    // Callbacks
    var onLevelUpdate: ((Float, Bool) -> Void)?
    var onSpeechSegment: ((Data) -> Void)?
    var onStatusChange: ((String) -> Void)?

    func startListening() throws {
        try startNewRecording()

        // Timer to check audio levels and detect speech
        vadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkVAD()
        }

        isListening = true
        onStatusChange?("🎤 Listening... (speak naturally)")
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
        // Clean up previous
        audioRecorder?.stop()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("vad_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: tempFileURL!, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
    }

    private func checkVAD() {
        guard isListening, let recorder = audioRecorder else { return }

        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let now = Date()

        // Update UI
        DispatchQueue.main.async {
            self.onLevelUpdate?(db, self.isSpeaking)
        }

        let currentlySpeaking = db > speechThreshold

        if currentlySpeaking {
            lastSpeechTime = now

            if !isSpeaking {
                // Speech just started
                isSpeaking = true
                speechStartTime = now
                print("🟢 Speech STARTED at \(db) dB")
                scenarioLogger.log("speech_start", ["db": db])
                DispatchQueue.main.async {
                    self.onStatusChange?("🗣 Speech detected...")
                }
            }
        } else if isSpeaking && db < silenceThreshold {
            // Currently in speech but now silent
            if let lastSpeech = lastSpeechTime,
               now.timeIntervalSince(lastSpeech) > silenceTimeout {

                let speechDuration = speechStartTime.map { Int(now.timeIntervalSince($0) * 1000) } ?? 0
                print("🔴 Speech ENDED after \(silenceTimeout)s silence")
                scenarioLogger.log("speech_end", ["duration_ms": speechDuration, "db": db])

                // Check if speech was long enough
                if let startTime = speechStartTime,
                   now.timeIntervalSince(startTime) > minSpeechDuration {

                    print("✅ Processing \(now.timeIntervalSince(startTime))s of speech...")
                    scenarioLogger.log("vad_triggered", ["speech_duration_ms": speechDuration])

                    // Stop recording and get the audio
                    recorder.stop()

                    if let url = tempFileURL, let data = try? Data(contentsOf: url) {
                        DispatchQueue.main.async {
                            self.onStatusChange?("⏳ Processing...")
                            self.onSpeechSegment?(data)
                        }
                    }

                    // Start a new recording
                    try? startNewRecording()
                }

                // Reset state
                isSpeaking = false
                speechStartTime = nil
                scenarioLogger.log("silence_start")

                DispatchQueue.main.async {
                    self.onStatusChange?("🎤 Listening...")
                }
            }
        }
    }
}

// MARK: - Main App

class KeywordSpotterVADApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var levelIndicator: NSLevelIndicator!
    var levelLabel: NSTextField!
    var resultLabel: NSTextField!
    var latencyLabel: NSTextField!
    var toggleButton: NSButton!
    var calibrateButton: NSButton!
    var voiceStatusLabel: NSTextField!

    let groqClient: GroqClient
    let matcher = KeywordMatcher()
    let recorder = VADAudioRecorder()
    let context = ConversationContext()
    let voiceAnalyzer = VoiceAnalyzer()
    var voiceProfile: VoiceProfile?
    var isActive = false
    var isCalibrating = false
    var calibrationSamples: Int = 0
    let calibrationTarget: Int = 5  // Number of speech segments needed
    var calibrationStartTime: Date?
    var calibrationTimer: Timer?
    var calibrationSegmentsReceived: Int = 0  // Track audio segments received (even if analysis fails)
    var calibrationQueue: [Data] = []  // Queue audio segments to process one at a time
    var isProcessingCalibration = false

    // Utterance buffer for combining split speech
    var utteranceBuffer: String = ""
    var bufferTimestamp: Date?
    let bufferTimeout: TimeInterval = 10.0  // Clear buffer after 10s of no activity

    // Answer cooldown - after showing help, wait before generating more
    var lastAnswerTime: Date?
    let answerCooldown: TimeInterval = 12.0  // seconds

    init(apiKey: String) {
        self.groqClient = GroqClient(apiKey: apiKey)
        self.voiceProfile = VoiceProfile.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupCallbacks()
    }

    func setupCallbacks() {
        recorder.onLevelUpdate = { [weak self] level, isSpeaking in
            // Convert dB to 0-100 scale (-60dB to 0dB)
            let normalized = max(0, min(100, (level + 60) * 1.67))
            self?.levelIndicator.doubleValue = Double(normalized)
            self?.levelLabel.stringValue = String(format: "%.0f dB", level)

            if isSpeaking {
                self?.levelIndicator.fillColor = .systemGreen
            } else {
                self?.levelIndicator.fillColor = .systemBlue
            }
        }

        recorder.onStatusChange = { [weak self] status in
            self?.statusLabel.stringValue = status
        }

        recorder.onSpeechSegment = { [weak self] audioData in
            Task {
                await self?.processAudio(audioData)
            }
        }
    }

    func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyword Spotter (VAD)"
        window.center()

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Title
        let titleLabel = NSTextField(labelWithString: "🎤 Interview Keyword Spotter (VAD)")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.frame = NSRect(x: 20, y: 545, width: 560, height: 35)
        contentView.addSubview(titleLabel)

        // Instructions
        let instructions = NSTextField(labelWithString: "Just speak naturally - it detects when you start and stop talking")
        instructions.font = .systemFont(ofSize: 13)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 20, y: 515, width: 560, height: 20)
        contentView.addSubview(instructions)

        // Voice calibration section
        let voiceLabel = NSTextField(labelWithString: "Voice ID:")
        voiceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        voiceLabel.frame = NSRect(x: 20, y: 480, width: 60, height: 20)
        // Voice calibration removed - using cooldown + question detection instead
        voiceLabel.isHidden = true

        voiceStatusLabel = NSTextField(labelWithString: "Ready")
        voiceStatusLabel.font = .systemFont(ofSize: 12)
        voiceStatusLabel.textColor = .systemGreen
        voiceStatusLabel.frame = NSRect(x: 85, y: 480, width: 200, height: 20)
        voiceStatusLabel.isHidden = true

        // Calibrate button removed - no longer needed
        calibrateButton = NSButton(title: "", target: self, action: nil)
        calibrateButton.isHidden = true

        // Toggle button (now primary control)
        toggleButton = NSButton(title: "▶ Start Listening", target: self, action: #selector(toggleListening))
        toggleButton.bezelStyle = .rounded
        toggleButton.font = .systemFont(ofSize: 16, weight: .medium)
        toggleButton.frame = NSRect(x: 200, y: 430, width: 200, height: 40)
        contentView.addSubview(toggleButton)

        // Level indicator
        levelIndicator = NSLevelIndicator(frame: NSRect(x: 80, y: 395, width: 380, height: 20))
        levelIndicator.levelIndicatorStyle = .continuousCapacity
        levelIndicator.minValue = 0
        levelIndicator.maxValue = 100
        levelIndicator.warningValue = 70
        levelIndicator.criticalValue = 90
        contentView.addSubview(levelIndicator)

        levelLabel = NSTextField(labelWithString: "-- dB")
        levelLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        levelLabel.textColor = .secondaryLabelColor
        levelLabel.frame = NSRect(x: 470, y: 393, width: 80, height: 20)
        contentView.addSubview(levelLabel)

        // Status
        statusLabel = NSTextField(labelWithString: "Click Start to begin")
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 20, y: 360, width: 560, height: 25)
        contentView.addSubview(statusLabel)

        // Latency
        latencyLabel = NSTextField(labelWithString: "")
        latencyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        latencyLabel.textColor = .systemGreen
        latencyLabel.alignment = .center
        latencyLabel.frame = NSRect(x: 20, y: 335, width: 560, height: 20)
        contentView.addSubview(latencyLabel)

        // Result box
        let resultBox = NSBox(frame: NSRect(x: 20, y: 20, width: 560, height: 305))
        resultBox.title = "Detected Topic"
        resultBox.titleFont = .systemFont(ofSize: 13, weight: .semibold)

        let scrollView = NSScrollView(frame: NSRect(x: 10, y: 10, width: 540, height: 270))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        resultLabel = NSTextField(wrappingLabelWithString: "Waiting for speech...")
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.frame = NSRect(x: 0, y: 0, width: 520, height: 270)
        resultLabel.maximumNumberOfLines = 0

        scrollView.documentView = resultLabel
        resultBox.addSubview(scrollView)
        contentView.addSubview(resultBox)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        // Request speech recognition authorization
        VoiceAnalyzer.requestAuthorization { authorized in
            if !authorized {
                print("⚠️ Speech recognition not authorized")
            }
        }
    }

    @objc func startCalibration() {
        if isCalibrating {
            // Cancel calibration
            isCalibrating = false
            calibrationSamples = 0
            calibrationTimer?.invalidate()
            calibrationTimer = nil
            calibrateButton.title = voiceProfile != nil ? "🔄 Re-calibrate" : "🎙 Calibrate Voice"
            voiceStatusLabel.stringValue = voiceProfile != nil ? "✓ Calibrated" : "Cancelled"
            voiceStatusLabel.textColor = voiceProfile != nil ? .systemGreen : .secondaryLabelColor
            recorder.stopListening()
            isActive = false
            toggleButton.title = "▶ Start Listening"
            toggleButton.isEnabled = true
            return
        }

        // Start calibration
        isCalibrating = true
        calibrationSamples = 0
        calibrationSegmentsReceived = 0
        calibrationQueue = []
        isProcessingCalibration = false
        calibrationStartTime = Date()
        voiceProfile = VoiceProfile()  // Fresh profile

        calibrateButton.title = "✗ Cancel"
        voiceStatusLabel.stringValue = "🎤 Speak naturally (0/\(calibrationTarget))..."
        voiceStatusLabel.textColor = .systemBlue
        toggleButton.isEnabled = false

        updateCalibrationUI(elapsedSeconds: 0)

        // Start timer to update elapsed time
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.calibrationStartTime else { return }
            let elapsed = Int(Date().timeIntervalSince(startTime))
            self.updateCalibrationUI(elapsedSeconds: elapsed)
        }

        do {
            try recorder.startListening()
            isActive = true
        } catch {
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
            isCalibrating = false
            calibrationTimer?.invalidate()
        }
    }

    func updateCalibrationUI(elapsedSeconds: Int) {
        let progressBar = String(repeating: "█", count: calibrationSamples * 2) + String(repeating: "░", count: (calibrationTarget - calibrationSamples) * 2)

        resultLabel.stringValue = """
        🎙 VOICE CALIBRATION — Read aloud at normal pace:
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "The quick brown fox jumps over the lazy dog.
        A hash map stores key value pairs with constant time lookups.
        Polymorphism allows objects to take many forms.
        One two three four five six seven eight nine ten.
        Testing testing one two three four five."
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ⏱️ Time: \(elapsedSeconds)s | Segments: \(calibrationSegmentsReceived) | ⏳ \(progressBar) \(calibrationSamples)/\(calibrationTarget)

        \(calibrationSamples < calibrationTarget ? "Keep reading..." : "Processing...")
        """
    }

    func processCalibrationAudio(_ audioData: Data) async {
        // Add to queue
        await MainActor.run {
            calibrationSegmentsReceived += 1
            calibrationQueue.append(audioData)
            statusLabel.stringValue = "📥 Queued segment \(calibrationSegmentsReceived) (queue: \(calibrationQueue.count))"
        }

        print("📥 Calibration: Queued audio segment \(calibrationSegmentsReceived), size: \(audioData.count) bytes, queue: \(calibrationQueue.count)")

        // Process queue if not already processing
        await processCalibrationQueue()
    }

    func processCalibrationQueue() async {
        // Check if already processing or queue empty
        let shouldProcess = await MainActor.run { () -> Bool in
            if isProcessingCalibration || calibrationQueue.isEmpty {
                return false
            }
            isProcessingCalibration = true
            return true
        }

        guard shouldProcess else { return }

        // Get next item from queue
        let audioData = await MainActor.run { () -> Data in
            return calibrationQueue.removeFirst()
        }

        let segmentNum = calibrationSegmentsReceived - calibrationQueue.count
        await MainActor.run {
            statusLabel.stringValue = "🔄 Analyzing segment \(segmentNum)..."
        }

        print("🔄 Processing segment \(segmentNum) from queue...")

        // Save audio to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempAudioURL = tempDir.appendingPathComponent("calibration_\(UUID().uuidString).m4a")

        do {
            try audioData.write(to: tempAudioURL)
            print("📁 Saved to: \(tempAudioURL.path)")
        } catch {
            print("❌ Failed to save audio: \(error)")
            await MainActor.run {
                statusLabel.stringValue = "Error saving audio: \(error.localizedDescription)"
            }
            return
        }

        // Analyze audio for voice features
        print("🔍 Starting voice analysis...")
        voiceAnalyzer.analyzeAudio(url: tempAudioURL) { [weak self] result in
            guard let self = self else { return }

            defer { try? FileManager.default.removeItem(at: tempAudioURL) }

            switch result {
            case .success(let analytics):
                print("✅ Analysis success - pitch samples: \(analytics.pitch.count), text: \"\(analytics.text)\"")

                guard !analytics.pitch.isEmpty else {
                    print("⚠️ No pitch data in voice analytics")
                    DispatchQueue.main.async {
                        self.statusLabel.stringValue = "⚠️ No voice features detected"
                        self.isProcessingCalibration = false
                        // Continue with queue
                        Task { await self.processCalibrationQueue() }
                    }
                    return
                }

                // Add sample to profile
                self.voiceProfile?.addSample(
                    pitch: analytics.pitch,
                    jitter: analytics.jitter,
                    shimmer: analytics.shimmer
                )
                self.calibrationSamples += 1
                print("✅ Sample \(self.calibrationSamples) added to profile")

                DispatchQueue.main.async {
                    self.isProcessingCalibration = false
                    self.voiceStatusLabel.stringValue = "🎤 Speaking (\(self.calibrationSamples)/\(self.calibrationTarget))..."

                    let profileDesc = self.voiceProfile?.description ?? "none"
                    let elapsed = self.calibrationStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    let progressBar = String(repeating: "█", count: self.calibrationSamples * 2) + String(repeating: "░", count: (self.calibrationTarget - self.calibrationSamples) * 2)

                    self.resultLabel.stringValue = """
                    🎙 VOICE CALIBRATION

                    ✅ Sample \(self.calibrationSamples) captured!

                    Heard: "\(analytics.text)"

                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    ⏱️  Time: \(elapsed)s | Segments: \(self.calibrationSegmentsReceived) | Queue: \(self.calibrationQueue.count)

                    ⏳ Progress: \(progressBar) \(self.calibrationSamples)/\(self.calibrationTarget)

                    Profile: \(profileDesc)

                    \(self.calibrationSamples < self.calibrationTarget ? "Keep speaking..." : "Processing...")
                    """

                    self.statusLabel.stringValue = "✅ Sample \(self.calibrationSamples) captured!"
                    self.statusLabel.textColor = .systemGreen

                    // Check if calibration is complete
                    if self.calibrationSamples >= self.calibrationTarget {
                        self.finishCalibration()
                    } else {
                        // Continue with queue
                        Task { await self.processCalibrationQueue() }
                    }
                }

            case .failure(let error):
                print("❌ Voice analysis failed: \(error)")
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "⚠️ Analysis failed: \(error.localizedDescription)"
                    self.isProcessingCalibration = false
                    // Continue with queue
                    Task { await self.processCalibrationQueue() }
                }
            }
        }
    }

    func finishCalibration() {
        isCalibrating = false
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        recorder.stopListening()
        isActive = false

        let totalTime = calibrationStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
        print("🏁 Calibration complete in \(totalTime)s, \(calibrationSamples) samples from \(calibrationSegmentsReceived) segments")

        // Save profile
        do {
            try voiceProfile?.save()

            voiceStatusLabel.stringValue = "✓ Calibrated"
            voiceStatusLabel.textColor = .systemGreen
            calibrateButton.title = "🔄 Re-calibrate"
            toggleButton.isEnabled = true
            toggleButton.title = "▶ Start Listening"

            let profileDesc = voiceProfile?.description ?? "none"
            resultLabel.stringValue = """
            ✅ VOICE CALIBRATION COMPLETE

            Your voice profile has been saved.

            Profile: \(profileDesc)

            The system will now identify your voice and skip generating
            answers when YOU are speaking (answering interview questions).

            Click "Start Listening" to begin the interview assistant.
            """

            statusLabel.stringValue = "Voice calibration complete!"
            statusLabel.textColor = .systemGreen

        } catch {
            voiceStatusLabel.stringValue = "⚠️ Save failed"
            voiceStatusLabel.textColor = .systemOrange
            resultLabel.stringValue = "Error saving profile: \(error.localizedDescription)"
        }
    }

    @objc func toggleListening() {
        if isActive {
            recorder.stopListening()
            isActive = false
            toggleButton.title = "▶ Start Listening"
            statusLabel.stringValue = "Stopped"
            levelIndicator.doubleValue = 0

            // Save scenario log
            if let savedURL = scenarioLogger.save() {
                resultLabel.stringValue = "📁 Scenario saved:\n\(savedURL.path)"
            }
        } else {
            do {
                // Start new scenario with timestamp
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                scenarioLogger.startScenario("interview_\(timestamp.replacingOccurrences(of: ":", with: "-"))")

                try recorder.startListening()
                isActive = true
                toggleButton.title = "⏹ Stop Listening"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    /// Quick heuristic check before calling LLM
    /// Returns: "complete", "incomplete", "filler", or "check" (needs LLM)
    func quickCompletenessCheck(_ text: String) -> String {
        let lower = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)

        // Obvious fillers - instant reject
        let fillers = ["hmm", "um", "uh", "okay", "ok", "right", "so", "yeah", "ah", "oh", "mhm", "uh huh", "i see", "got it"]
        if fillers.contains(lower) {
            return "filler"
        }

        // Starts with question/command word = likely complete
        let questionStarts = [
            "what ", "what's ", "whats ",
            "why ", "why's ",
            "how ", "how's ", "hows ",
            "when ", "where ", "which ",
            "explain ", "describe ", "define ",
            "tell me ", "can you ", "could you ",
            "give me ", "show me ",
            "is ", "are ", "do ", "does ", "did ",
            "have you ", "has "
        ]
        for prefix in questionStarts {
            if lower.hasPrefix(prefix) {
                return "complete"
            }
        }

        // Single technical term (likely topic mention, complete)
        let technicalTerms = [
            "hashmap", "hash map", "arraylist", "linkedlist", "treeset", "hashset",
            "closure", "closures", "promise", "promises", "async await",
            "polymorphism", "inheritance", "encapsulation", "abstraction",
            "singleton", "factory", "observer", "decorator",
            "deadlock", "race condition", "thread", "threads",
            "garbage collection", "jvm", "jdk", "jre",
            "lambda", "stream api", "optional",
            "synchronized", "volatile"
        ]
        for term in technicalTerms {
            if lower == term || lower == term + "s" || lower == "the " + term {
                return "complete"
            }
        }

        // Starts with fragment/connector = incomplete
        let fragmentStarts = [
            "between ", "and ", "or ", "the ", "a ", "an ",
            "about ", "for ", "with ", "to ", "of ",
            "like ", "also ", "but "
        ]
        for prefix in fragmentStarts {
            if lower.hasPrefix(prefix) {
                return "incomplete"
            }
        }

        // Let LLM decide
        return "check"
    }

    func processAudio(_ audioData: Data) async {
        // Handle calibration mode separately
        if isCalibrating {
            await processCalibrationAudio(audioData)
            return
        }

        let totalStart = Date()
        scenarioLogger.log("processing_start", ["audio_size_bytes": audioData.count])

        // === LOGGING (use fputs for immediate output) ===
        func log(_ msg: String) {
            fputs(msg + "\n", stderr)
        }

        do {
            scenarioLogger.log("stt_start")
            let (rawText, whisperLatency) = try await groqClient.transcribe(audioData: audioData, filename: "audio.m4a")
            scenarioLogger.log("stt_end", ["latency_ms": whisperLatency, "text": rawText])

            // Skip empty or very short transcriptions
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count < 3 {
                scenarioLogger.log("stt_skipped", ["reason": "empty_or_short"])
                await MainActor.run {
                    statusLabel.stringValue = "🎤 Listening..."
                }
                return
            }

            log("\n" + String(repeating: "═", count: 60))
            log("🎙️  WHISPER HEARD: \"\(trimmed)\"")
            log("⏱️  STT Latency: \(String(format: "%.0f", whisperLatency))ms")
            log("📦 BUFFER: \"\(utteranceBuffer)\"")

            // Get conversation context for LLM
            let conversationContext = context.getContextForLLM()

            // Check if buffer is stale (>10s old) and clear it
            if let timestamp = bufferTimestamp, Date().timeIntervalSince(timestamp) > bufferTimeout {
                log("🗑️  Buffer expired, clearing")
                utteranceBuffer = ""
                bufferTimestamp = nil
            }

            // === QUICK PRE-FILTER (no LLM) ===
            let quickResult = quickCompletenessCheck(trimmed)
            log("⚡ QUICK CHECK: \(quickResult)")

            var completeness: String
            var completenessLatency: Double = 0

            if quickResult != "check" {
                // Quick filter gave definitive answer
                completeness = quickResult
                scenarioLogger.log("completeness_quick", ["status": quickResult, "text": trimmed])
            } else {
                // Ambiguous - use LLM
                scenarioLogger.log("completeness_start", ["buffer": utteranceBuffer, "new_text": trimmed])
                let result = try await groqClient.checkCompleteness(trimmed, buffer: utteranceBuffer, context: conversationContext)
                completeness = result.status
                completenessLatency = result.latencyMs
                scenarioLogger.log("completeness_end", ["latency_ms": completenessLatency, "status": completeness])
            }

            log("🔍 COMPLETENESS: \(completeness) (\(String(format: "%.0f", completenessLatency))ms)")

            if completeness == "filler" {
                log("🚫 Filler detected, ignoring")
                scenarioLogger.log("filler_ignored", ["text": trimmed])
                await MainActor.run {
                    statusLabel.stringValue = "🎤 Listening... (filler ignored)"
                }
                return
            }

            if completeness == "incomplete" {
                // Add to buffer and wait for more
                if utteranceBuffer.isEmpty {
                    utteranceBuffer = trimmed
                } else {
                    utteranceBuffer += " " + trimmed
                }
                bufferTimestamp = Date()
                log("📥 Added to buffer: \"\(utteranceBuffer)\"")
                scenarioLogger.log("buffered", ["buffer": utteranceBuffer])
                await MainActor.run {
                    statusLabel.stringValue = "🎤 Listening... (buffering)"
                }
                return
            }

            // === COMPLETE - Process the full utterance ===
            var fullText = trimmed
            if !utteranceBuffer.isEmpty {
                fullText = utteranceBuffer + " " + trimmed
                log("📤 Combined with buffer: \"\(fullText)\"")
                scenarioLogger.log("buffer_combined", ["full_text": fullText])
            }

            // Clear buffer
            utteranceBuffer = ""
            bufferTimestamp = nil

            log("\n📜 CONTEXT:")
            log(conversationContext)
            log("\n🔍 Last Topic: \(context.lastTopic ?? "none")")

            // Step 1: Detect topic with context-aware LLM
            scenarioLogger.log("topic_start", ["last_topic": context.lastTopic ?? "none"])
            let (detectedIntent, detectLatency) = try await groqClient.detectTopic(fullText, context: conversationContext, lastTopic: context.lastTopic)
            scenarioLogger.log("topic_end", ["latency_ms": detectLatency, "detected": detectedIntent])

            // Classify speaker
            let speaker = context.classifySpeaker(text: fullText)
            scenarioLogger.log("speaker_classified", ["speaker": speaker.rawValue])

            log("\n🤖 LLM DETECTED: \"\(detectedIntent)\"")
            log("👤 Speaker: \(speaker.rawValue)")
            log("⏱️  Detect Latency: \(String(format: "%.0f", detectLatency))ms")

            var answer = ""
            var answerLatency: Double = 0
            var displayTopic: String? = nil
            var isFollowUp = false

            // === CHECK COOLDOWN - Skip unless clear question detected ===
            var inCooldown = false
            var isClearQuestion = false

            // Check if this is clearly a question
            let lowerText = fullText.lowercased()
            let questionMarkers = [
                "?",  // Has question mark
                "what is", "what are", "what's", "whats",
                "how do", "how does", "how is", "how would", "how can",
                "why do", "why does", "why is", "why would",
                "can you explain", "could you explain", "can you tell", "could you tell",
                "tell me about", "tell me more",
                "explain ", "describe ",
                "what about", "how about",
                "difference between", "differences between",
                "when do", "when does", "when would", "when should",
                "where do", "where does", "where is",
                "which ", "who ", "whose "
            ]

            for marker in questionMarkers {
                if lowerText.contains(marker) {
                    isClearQuestion = true
                    break
                }
            }

            if let lastAnswer = lastAnswerTime {
                let elapsed = Date().timeIntervalSince(lastAnswer)
                if elapsed < answerCooldown {
                    let remaining = Int(answerCooldown - elapsed)
                    if isClearQuestion {
                        log("\n⏸️  COOLDOWN BUT CLEAR QUESTION DETECTED - proceeding")
                        scenarioLogger.log("cooldown_override", ["elapsed": elapsed, "reason": "clear_question"])
                    } else {
                        inCooldown = true
                        log("\n⏸️  COOLDOWN ACTIVE - \(remaining)s remaining, no clear question detected")
                        scenarioLogger.log("cooldown_skipped", ["elapsed": elapsed, "remaining": remaining])
                    }
                }
            }

            if inCooldown {
                // Still add to context but don't generate help
            } else if detectedIntent == "followup" || detectedIntent == "followUp" {
                log("\n📎 FOLLOW-UP DETECTED - Using last topic: \(context.lastTopic ?? "none")")
                // Handle follow-up - use last topic
                if let lastTopic = context.lastTopic {
                    isFollowUp = true
                    displayTopic = lastTopic
                    scenarioLogger.log("answer_start", ["type": "followup", "topic": lastTopic])
                    let (followUpAnswer, genLatency) = try await groqClient.generateFollowUpAnswer(
                        for: lastTopic,
                        transcription: fullText,
                        context: conversationContext
                    )
                    answer = followUpAnswer
                    answerLatency = genLatency
                    scenarioLogger.log("answer_end", ["latency_ms": genLatency, "type": "followup"])
                }
            } else if detectedIntent == "answer" {
                // Interviewee is answering - just log, don't generate help
                log("\n💬 INTERVIEWEE ANSWERING - No help needed")
                scenarioLogger.log("interviewee_answering")
            } else if detectedIntent != "unknown" {
                log("\n✅ NEW TOPIC: \(detectedIntent)")
                // New topic detected
                displayTopic = detectedIntent

                // Try to match to enum for display name
                if let topic = InterviewTopic(rawValue: detectedIntent) {
                    displayTopic = topic.displayName
                }

                scenarioLogger.log("answer_start", ["type": "new_topic", "topic": detectedIntent])
                let (generatedAnswer, genLatency) = try await groqClient.generateAnswer(for: detectedIntent, transcription: fullText)
                answer = generatedAnswer
                answerLatency = genLatency
                scenarioLogger.log("answer_end", ["latency_ms": genLatency, "type": "new_topic"])
            } else {
                scenarioLogger.log("topic_unknown")
            }

            // Add to conversation history
            context.addUtterance(text: fullText, topic: detectedIntent != "unknown" && detectedIntent != "answer" ? detectedIntent : nil)

            let totalLatency = Date().timeIntervalSince(totalStart) * 1000
            scenarioLogger.log("processing_end", [
                "total_latency_ms": totalLatency,
                "stt_ms": whisperLatency,
                "completeness_ms": completenessLatency,
                "topic_ms": detectLatency,
                "answer_ms": answerLatency,
                "answer_generated": !answer.isEmpty
            ])

            // Final summary log
            log("\n📊 SUMMARY:")
            log("   Total Latency: \(String(format: "%.0f", totalLatency))ms")
            log("   Answer Generated: \(!answer.isEmpty)")
            log("   Display Topic: \(displayTopic ?? "none")")
            log(String(repeating: "═", count: 60) + "\n")

            await MainActor.run {
                let speakerEmoji = speaker == .interviewer ? "🎤" : (speaker == .interviewee ? "💬" : "❓")

                if inCooldown {
                    // In cooldown - show what was heard but no answer
                    let remaining = Int(answerCooldown - Date().timeIntervalSince(lastAnswerTime!))
                    latencyLabel.stringValue = String(format: "⚡ STT: %.0fms | ⏸️ Cooldown: %ds", whisperLatency, remaining)
                    statusLabel.stringValue = "⏸️ Cooldown (you're answering...)"
                    statusLabel.textColor = .systemOrange

                    let currentTopicStr = context.lastTopic != nil ? "Topic: \(context.lastTopic!)" : ""
                    resultLabel.stringValue = """
                    💬 Heard: "\(fullText)"

                    \(currentTopicStr)
                    (Waiting \(remaining)s before generating new answers...)
                    """
                } else if !answer.isEmpty {
                    // Answer generated - set cooldown timer
                    lastAnswerTime = Date()

                    latencyLabel.stringValue = String(format: "⚡ STT: %.0fms | Check: %.0fms | Topic: %.0fms | Answer: %.0fms", whisperLatency, completenessLatency, detectLatency, answerLatency)

                    let prefix = isFollowUp ? "📎 Follow-up on" : "✅"
                    statusLabel.stringValue = "\(prefix) \(displayTopic ?? detectedIntent)"
                    statusLabel.textColor = .systemGreen

                    resultLabel.stringValue = """
                    \(speakerEmoji) \(speaker.rawValue.capitalized): "\(fullText)"

                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    \(answer)
                    """
                } else if detectedIntent == "answer" {
                    // Interviewee answering - just show what was heard
                    latencyLabel.stringValue = String(format: "⚡ STT: %.0fms | Check: %.0fms | Topic: %.0fms", whisperLatency, completenessLatency, detectLatency)
                    statusLabel.stringValue = "💬 (You're answering...)"
                    statusLabel.textColor = .systemBlue

                    let currentTopicStr = context.lastTopic != nil ? "Current topic: \(context.lastTopic!)" : ""
                    resultLabel.stringValue = """
                    \(speakerEmoji) \(speaker.rawValue.capitalized): "\(fullText)"

                    \(currentTopicStr)
                    (Listening for interviewer questions...)
                    """
                } else {
                    latencyLabel.stringValue = String(format: "⚡ STT: %.0fms | Check: %.0fms | Topic: %.0fms", whisperLatency, completenessLatency, detectLatency)
                    statusLabel.stringValue = "🎤 Listening..."
                    statusLabel.textColor = .labelColor

                    let currentTopicStr = context.lastTopic != nil ? "\nCurrent topic: \(context.lastTopic!)" : ""
                    resultLabel.stringValue = """
                    \(speakerEmoji) Heard: "\(fullText)"

                    Not recognized as an interview topic.\(currentTopicStr)
                    Try: closures, promises, hash maps, big O, etc.
                    Or say "tell me more" / "dig deeper" for follow-up.
                    """
                }

                // Resume listening status after a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    if self?.isActive == true {
                        self?.statusLabel.stringValue = "🎤 Listening..."
                        self?.statusLabel.textColor = .labelColor
                    }
                }
            }
        } catch {
            log("❌ ERROR: \(error.localizedDescription)")
            await MainActor.run {
                statusLabel.stringValue = "❌ Error: \(error.localizedDescription)"
                statusLabel.textColor = .systemRed
            }
        }
    }
}

// MARK: - Entry Point

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift keyword_spotter_vad.swift <GROQ_API_KEY>")
    exit(1)
}

let apiKey = CommandLine.arguments[1]
let app = NSApplication.shared
let delegate = KeywordSpotterVADApp(apiKey: apiKey)
app.delegate = delegate
app.run()
