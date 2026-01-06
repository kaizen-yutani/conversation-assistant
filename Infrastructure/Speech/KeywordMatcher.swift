import Foundation

/// Matches transcribed text against known interview keywords/topics
/// Returns the best matching topic with associated content
class KeywordMatcher {

    struct Match {
        let keyword: String
        let topic: InterviewTopic
        let confidence: Double // 0.0 - 1.0
    }

    /// Find the best matching interview topic from transcribed text
    func findMatch(in text: String) -> Match? {
        let normalizedText = text.lowercased()
        let words = Set(normalizedText.components(separatedBy: .whitespacesAndNewlines))

        var bestMatch: Match?
        var bestScore: Double = 0

        for topic in InterviewTopic.allCases {
            for keyword in topic.keywords {
                let score = calculateMatchScore(keyword: keyword, text: normalizedText, words: words)
                if score > bestScore && score >= 0.5 {
                    bestScore = score
                    bestMatch = Match(keyword: keyword, topic: topic, confidence: score)
                }
            }
        }

        return bestMatch
    }

    /// Find all matching topics (for ambiguous queries)
    func findAllMatches(in text: String, minConfidence: Double = 0.5) -> [Match] {
        let normalizedText = text.lowercased()
        let words = Set(normalizedText.components(separatedBy: .whitespacesAndNewlines))

        var matches: [Match] = []
        var seenTopics: Set<InterviewTopic> = []

        for topic in InterviewTopic.allCases {
            for keyword in topic.keywords {
                let score = calculateMatchScore(keyword: keyword, text: normalizedText, words: words)
                if score >= minConfidence && !seenTopics.contains(topic) {
                    matches.append(Match(keyword: keyword, topic: topic, confidence: score))
                    seenTopics.insert(topic)
                }
            }
        }

        return matches.sorted { $0.confidence > $1.confidence }
    }

    private func calculateMatchScore(keyword: String, text: String, words: Set<String>) -> Double {
        let keywordLower = keyword.lowercased()

        // Exact phrase match (highest confidence)
        if text.contains(keywordLower) {
            return 1.0
        }

        // Word-by-word match for multi-word keywords
        let keywordWords = keywordLower.components(separatedBy: .whitespaces)
        if keywordWords.count > 1 {
            let matchedWords = keywordWords.filter { words.contains($0) }
            let ratio = Double(matchedWords.count) / Double(keywordWords.count)
            if ratio >= 0.5 {
                return ratio * 0.8 // Partial match is lower confidence
            }
        }

        // Single word exact match
        if words.contains(keywordLower) {
            return 0.9
        }

        // Fuzzy match (for speech recognition errors)
        for word in words {
            if levenshteinDistance(word, keywordLower) <= 2 && keywordLower.count > 4 {
                return 0.6
            }
        }

        return 0
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)

        for i in 0...s1Array.count { dist[i][0] = i }
        for j in 0...s2Array.count { dist[0][j] = j }

        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                dist[i][j] = min(
                    dist[i-1][j] + 1,
                    dist[i][j-1] + 1,
                    dist[i-1][j-1] + cost
                )
            }
        }
        return dist[s1Array.count][s2Array.count]
    }
}

// MARK: - Interview Topics

enum InterviewTopic: String, CaseIterable {
    // JavaScript fundamentals
    case closure
    case hoisting
    case eventLoop
    case promises
    case asyncAwait
    case prototypes
    case thisKeyword

    // React
    case reactHooks
    case useState
    case useEffect
    case virtualDOM
    case reactLifecycle

    // TypeScript
    case typescript
    case generics
    case interfaces

    // Data Structures
    case arrays
    case linkedList
    case hashMap
    case trees
    case graphs
    case stack
    case queue

    // Algorithms
    case bigO
    case sorting
    case searching
    case recursion
    case dynamicProgramming

    // System Design
    case systemDesign
    case scalability
    case caching
    case loadBalancing
    case database
    case microservices
    case api

    // General
    case solid
    case designPatterns
    case testing

    var keywords: [String] {
        switch self {
        case .closure:
            return ["closure", "closures", "lexical scope", "lexical scoping"]
        case .hoisting:
            return ["hoisting", "variable hoisting", "function hoisting", "hoist"]
        case .eventLoop:
            return ["event loop", "event-loop", "call stack", "callback queue", "microtask"]
        case .promises:
            return ["promise", "promises", "then catch", "promise chain"]
        case .asyncAwait:
            return ["async await", "async/await", "asynchronous"]
        case .prototypes:
            return ["prototype", "prototypes", "prototypal inheritance", "prototype chain", "__proto__"]
        case .thisKeyword:
            return ["this keyword", "this binding", "call apply bind"]

        case .reactHooks:
            return ["react hooks", "hooks", "custom hook", "custom hooks"]
        case .useState:
            return ["usestate", "use state", "state hook"]
        case .useEffect:
            return ["useeffect", "use effect", "effect hook", "side effects"]
        case .virtualDOM:
            return ["virtual dom", "virtual DOM", "reconciliation", "diffing"]
        case .reactLifecycle:
            return ["lifecycle", "component lifecycle", "mount unmount", "componentdidmount"]

        case .typescript:
            return ["typescript", "type script", "ts", "type system"]
        case .generics:
            return ["generics", "generic types", "generic type"]
        case .interfaces:
            return ["interface", "interfaces", "type vs interface"]

        case .arrays:
            return ["array", "arrays", "array methods"]
        case .linkedList:
            return ["linked list", "linkedlist", "singly linked", "doubly linked"]
        case .hashMap:
            return ["hash map", "hashmap", "hash table", "hashtable", "dictionary"]
        case .trees:
            return ["tree", "trees", "binary tree", "bst", "binary search tree"]
        case .graphs:
            return ["graph", "graphs", "dfs", "bfs", "depth first", "breadth first"]
        case .stack:
            return ["stack", "stacks", "lifo", "last in first out"]
        case .queue:
            return ["queue", "queues", "fifo", "first in first out"]

        case .bigO:
            return ["big o", "big-o", "time complexity", "space complexity", "complexity"]
        case .sorting:
            return ["sorting", "sort", "quicksort", "mergesort", "bubble sort"]
        case .searching:
            return ["searching", "search", "binary search", "linear search"]
        case .recursion:
            return ["recursion", "recursive", "base case"]
        case .dynamicProgramming:
            return ["dynamic programming", "dp", "memoization", "tabulation"]

        case .systemDesign:
            return ["system design", "design system", "architecture"]
        case .scalability:
            return ["scalability", "scaling", "horizontal scaling", "vertical scaling"]
        case .caching:
            return ["caching", "cache", "redis", "memcached"]
        case .loadBalancing:
            return ["load balancing", "load balancer", "round robin"]
        case .database:
            return ["database", "sql", "nosql", "postgresql", "mongodb"]
        case .microservices:
            return ["microservices", "micro services", "monolith"]
        case .api:
            return ["api", "rest", "restful", "graphql", "api design"]

        case .solid:
            return ["solid", "solid principles", "single responsibility", "open closed"]
        case .designPatterns:
            return ["design patterns", "design pattern", "singleton", "factory", "observer"]
        case .testing:
            return ["testing", "unit test", "unit testing", "tdd", "test driven"]
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
        case .thisKeyword: return "The 'this' Keyword"
        case .reactHooks: return "React Hooks"
        case .useState: return "useState Hook"
        case .useEffect: return "useEffect Hook"
        case .virtualDOM: return "Virtual DOM"
        case .reactLifecycle: return "React Lifecycle"
        case .typescript: return "TypeScript"
        case .generics: return "Generics"
        case .interfaces: return "Interfaces"
        case .arrays: return "Arrays"
        case .linkedList: return "Linked Lists"
        case .hashMap: return "Hash Maps"
        case .trees: return "Trees"
        case .graphs: return "Graphs"
        case .stack: return "Stacks"
        case .queue: return "Queues"
        case .bigO: return "Big O Notation"
        case .sorting: return "Sorting Algorithms"
        case .searching: return "Searching Algorithms"
        case .recursion: return "Recursion"
        case .dynamicProgramming: return "Dynamic Programming"
        case .systemDesign: return "System Design"
        case .scalability: return "Scalability"
        case .caching: return "Caching"
        case .loadBalancing: return "Load Balancing"
        case .database: return "Databases"
        case .microservices: return "Microservices"
        case .api: return "API Design"
        case .solid: return "SOLID Principles"
        case .designPatterns: return "Design Patterns"
        case .testing: return "Testing"
        }
    }

    /// Brief explanation to show when topic is detected
    var quickSummary: String {
        switch self {
        case .closure:
            return """
            A closure is a function that has access to variables from its outer (enclosing) scope, even after that outer function has returned.

            ```javascript
            function outer() {
              let count = 0;
              return function inner() {
                count++;
                return count;
              }
            }
            const counter = outer();
            counter(); // 1
            counter(); // 2
            ```
            """
        case .hoisting:
            return """
            Hoisting moves declarations to the top of their scope during compilation.
            - `var` declarations are hoisted and initialized to `undefined`
            - `let`/`const` are hoisted but NOT initialized (Temporal Dead Zone)
            - Function declarations are fully hoisted

            ```javascript
            console.log(x); // undefined (var hoisted)
            console.log(y); // ReferenceError (TDZ)
            var x = 1;
            let y = 2;
            ```
            """
        case .eventLoop:
            return """
            The event loop handles async operations:
            1. Call Stack - executes sync code
            2. Web APIs - handle async operations
            3. Callback Queue (macrotasks) - setTimeout, setInterval
            4. Microtask Queue - Promises, queueMicrotask

            Microtasks always run before macrotasks!
            """
        case .promises:
            return """
            A Promise represents an eventual completion (or failure) of an async operation.

            States: pending → fulfilled OR rejected

            ```javascript
            new Promise((resolve, reject) => {
              // async work
              resolve(value); // or reject(error)
            })
            .then(result => { })
            .catch(error => { })
            .finally(() => { });
            ```
            """
        case .asyncAwait:
            return """
            Syntactic sugar over Promises for cleaner async code.

            ```javascript
            async function fetchData() {
              try {
                const response = await fetch(url);
                const data = await response.json();
                return data;
              } catch (error) {
                console.error(error);
              }
            }
            ```

            - `async` function always returns a Promise
            - `await` pauses execution until Promise resolves
            """
        default:
            return "Topic: \(displayName)"
        }
    }
}
