#!/usr/bin/env swift

import Foundation

// Test cases: (input, expectedStatus, expectedTopic, description)
// Note: for incomplete/filler/answer, topic can be "none", "unknown", or actual topic - we accept any
let testCases: [(String, String, String, String)] = [
    // Basic questions - should detect specific topics
    ("What is the difference between array and arraylist?", "question", "array", "Array vs ArrayList comparison"),
    ("What is ArrayList?", "question", "arraylist", "ArrayList definition"),
    ("What is a LinkedList?", "question", "linkedlist", "LinkedList definition"),
    ("What is HashMap?", "question", "hashmap", "HashMap definition"),
    ("How does garbage collection work?", "question", "garbagecollection", "GC question"),
    ("What is the difference between JDK and JVM?", "question", "jdk|jvm", "JDK vs JVM"),

    // Linux questions
    ("How do I list processes in Linux?", "question", "linux", "Linux processes"),
    ("What is the ps command?", "question", "linux", "ps command"),
    ("How do I find a file in Linux?", "question", "linux|bash", "Linux find"),

    // Topic switching - should NOT stick to previous topic
    ("What is polymorphism?", "question", "polymorphism", "OOP concept"),
    ("What is a closure in JavaScript?", "question", "closure", "JS closure"),
    ("Explain the event loop", "question", "eventloop", "JS event loop"),

    // Incomplete sentences - should detect incomplete
    ("What is the", "incomplete", "*", "Cut off mid-sentence"),
    ("Can you explain", "incomplete", "*", "Missing object"),
    ("Tell me about", "incomplete", "*", "Incomplete request"),

    // Fillers - should detect filler
    ("Hmm", "filler", "*", "Thinking sound"),
    ("Um", "filler", "*", "Filler word"),
    ("Okay", "filler", "*", "Acknowledgment"),

    // User answering - should detect answer (topic optional)
    ("Well I think HashMap uses hashing to store key value pairs in buckets and when there is a collision it uses linked list or tree structure to handle it", "answer", "*", "User explaining HashMap"),
    ("So basically polymorphism means that the same method can behave differently based on the object that calls it and there are two types compile time and runtime polymorphism", "answer", "*", "User explaining polymorphism"),

    // Follow-ups - should detect followUp when vague
    ("Tell me more", "question", "followup", "Vague follow-up"),
    ("Can you elaborate?", "question", "followup", "Elaborate request"),
    ("What else?", "question", "followup", "What else"),

    // Edge cases - questions that look like statements
    ("The four pillars of OOP", "question", "oop", "Statement as question"),
    ("Singleton pattern", "question", "singleton", "Topic mention"),
    ("HashMap vs HashSet", "question", "hashmap|hashset", "Comparison without question mark"),

    // Multi-language hints (should still work)
    ("What is dependency injection?", "question", "dependencyinjection", "DI question"),
    ("Explain SOLID principles", "question", "solid", "SOLID question"),
    ("What is Docker?", "question", "docker", "Docker question"),

    // Tricky cases
    ("Okay, now tell me about threads", "question", "threads", "Acknowledgment + new topic"),
    ("Right, what about deadlock?", "question", "deadlock", "Agreement + new topic"),
]

// Groq API call
func classifyUtterance(_ text: String, lastTopic: String?) async throws -> (status: String, topic: String) {
    // Try environment variable first, then ~/.interview-master-keys
    var apiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
    if apiKey.isEmpty {
        // Try reading from ~/.interview-master-keys (same as main app)
        let keysPath = NSString("~/.interview-master-keys").expandingTildeInPath
        if let contents = try? String(contentsOfFile: keysPath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("GROQ_API_KEY=") {
                    apiKey = String(trimmed.dropFirst("GROQ_API_KEY=".count))
                    break
                }
            }
        }
    }
    guard !apiKey.isEmpty else {
        fatalError("GROQ_API_KEY not found. Set it in ~/.interview-master-keys as GROQ_API_KEY=your_key")
    }

    let lastTopicNote = lastTopic != nil ? "Last topic: \(lastTopic!)" : ""

    let prompt = """
    Classify this utterance. Return: STATUS,TOPIC

    Text: "\(text)"
    \(lastTopicNote)

    STATUS (pick one):
    - question = asking about something OR mentioning a topic (wants info)
    - incomplete = cut off mid-sentence ("What is the", "Can you")
    - answer = user explaining (20+ words, detailed explanation)
    - filler = ONLY "um", "okay", "hmm", "right" (1-2 meaningless words)

    IMPORTANT: Short topic mentions like "polymorphism", "singleton pattern", "the four pillars" = question (user wants info)

    TOPIC - return the SPECIFIC topic name, not the category:
    array, arrayList, linkedList, hashMap, hashSet, treeMap, queue, collections
    threads, process, synchronized, volatile, deadlock, locks
    jvm, jdk, jre, garbageCollection, heap, stack
    oop, inheritance, polymorphism, encapsulation, abstraction, abstractClass, interface
    lambda, streamApi, optional, functionalInterface
    exceptions, checkedExceptions, uncheckedExceptions
    closure, hoisting, eventLoop, promises, asyncAwait, this, scope
    reactHooks, useState, useEffect, useContext, virtualDOM, redux
    typescript, generics, interfaces, types
    bigO, sorting, binarySearch, recursion, dynamicProgramming, bfs, dfs
    systemDesign, caching, redis, loadBalancing, database, sql, nosql, microservices, rest
    singleton, factory, builder, observer, strategy, dependencyInjection, solid
    testing, unitTest, tdd, mocking
    docker, kubernetes, ci, cd, git, aws
    linux, bash, ssh, networking
    background, experience, tellMeAboutYourself, projects
    followUp (for "tell me more" with no new topic)
    unknown (if no match)

    IMPORTANT MAPPINGS:
    - "array vs arraylist", "difference array arraylist", "list vs arraylist" → array
    - "ArrayList" alone → arrayList
    - "LinkedList" → linkedList
    - "hash map", "hashmap" → hashMap
    - "garbage collection" → garbageCollection
    - "list processes", "find processes", "ps command" → linux
    - "tell me about yourself" → tellMeAboutYourself

    EXAMPLES:
    "What is the difference between array and arraylist?" → question,array
    "What is ArrayList?" → question,arrayList
    "How do I list processes in Linux?" → question,linux
    "What is the" → incomplete,none
    "Hmm" → filler,none
    "Tell me more" → question,followUp

    Return ONLY: STATUS,TOPIC (e.g., "question,array")
    """

    let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
        "model": "llama-3.3-70b-versatile",
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": 20,
        "temperature": 0
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    // Check for rate limiting
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
        // Wait and retry once
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        let (retryData, _) = try await URLSession.shared.data(for: request)
        return try parseResponse(retryData)
    }

    return try parseResponse(data)
}

func parseResponse(_ data: Data) throws -> (status: String, topic: String) {
    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable { let content: String }
            let message: Message
        }
        let choices: [Choice]?
        let error: ErrorResponse?

        struct ErrorResponse: Codable {
            let message: String
        }
    }

    let response = try JSONDecoder().decode(ChatResponse.self, from: data)

    // Check for error
    if let error = response.error {
        throw NSError(domain: "Groq", code: 429, userInfo: [NSLocalizedDescriptionKey: error.message])
    }

    let raw = response.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "question,unknown"

    // Handle different separators: "status,topic" or "status:topic" or "status, topic"
    let cleaned = raw.replacingOccurrences(of: ":", with: ",").replacingOccurrences(of: " ", with: "")
    let parts = cleaned.split(separator: ",").map { String($0) }
    let status = parts.first ?? "question"
    let topic = parts.count > 1 ? parts[1] : "unknown"

    return (status, topic == "none" ? "none" : topic)
}

// Run tests
func runTests() async {
    print("🧪 Testing Classification API\n")
    print(String(repeating: "=", count: 100))

    var passed = 0
    var failed = 0
    var results: [(String, Bool, String)] = []

    for (input, expectedStatus, expectedTopic, description) in testCases {
        do {
            let (status, topic) = try await classifyUtterance(input, lastTopic: nil)

            let statusMatch = status == expectedStatus

            // Handle wildcard "*" for topic (accept anything)
            // Handle "a|b" for multiple acceptable topics
            let topicMatch: Bool
            if expectedTopic == "*" {
                topicMatch = true
            } else if expectedTopic.contains("|") {
                let acceptableTopics = expectedTopic.split(separator: "|").map { String($0) }
                topicMatch = acceptableTopics.contains(topic)
            } else {
                topicMatch = topic == expectedTopic
            }

            let success = statusMatch && topicMatch

            if success {
                passed += 1
                results.append((description, true, ""))
            } else {
                failed += 1
                let detail = "Expected: \(expectedStatus),\(expectedTopic) | Got: \(status),\(topic)"
                results.append((description, false, detail))
            }

            // Rate limiting - 500ms between requests to avoid Groq limits
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        } catch {
            failed += 1
            results.append((description, false, "Error: \(error)"))
        }
    }

    // Print results
    print("\n📊 RESULTS\n")

    for (desc, success, detail) in results {
        let icon = success ? "✅" : "❌"
        print("\(icon) \(desc)")
        if !detail.isEmpty {
            print("   └─ \(detail)")
        }
    }

    print("\n" + String(repeating: "=", count: 100))
    print("📈 Summary: \(passed)/\(testCases.count) passed (\(Int(Double(passed)/Double(testCases.count)*100))%)")

    if failed > 0 {
        print("❌ \(failed) tests failed")
    } else {
        print("🎉 All tests passed!")
    }
}

// Main
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runTests()
    semaphore.signal()
}
semaphore.wait()
