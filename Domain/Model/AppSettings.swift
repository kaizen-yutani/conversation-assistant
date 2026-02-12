import Foundation

/// Supported tech stacks for vocabulary hints
enum TechStack: String, CaseIterable {
    case java = "java"
    case python = "python"
    case javascript = "javascript"
    case typescript = "typescript"
    case go = "go"
    case csharp = "csharp"
    case cpp = "cpp"
    case rust = "rust"
    case general = "general"

    var displayName: String {
        switch self {
        case .java: return "Java/Spring"
        case .python: return "Python/Django"
        case .javascript: return "JavaScript/Node"
        case .typescript: return "TypeScript/React"
        case .go: return "Go/Golang"
        case .csharp: return "C#/.NET"
        case .cpp: return "C++"
        case .rust: return "Rust"
        case .general: return "General/Mixed"
        }
    }

    /// Vocabulary hints for Whisper based on tech stack
    var whisperVocabulary: String {
        let common = "API, REST, GraphQL, SQL, NoSQL, MongoDB, Redis, Kafka, Docker, Kubernetes, microservices, CI/CD, Git, AWS, Azure, GCP, Big O notation, binary search, recursion, dynamic programming, linked list, hash map, tree, graph, queue, stack, heap"

        switch self {
        case .java:
            return "Java, JVM, JDK, JRE, Array, ArrayList, LinkedList, HashMap, HashSet, HashTable, TreeMap, TreeSet, garbage collection, polymorphism, inheritance, encapsulation, abstraction, interface, abstract class, synchronized, volatile, deadlock, ThreadPool, ExecutorService, Lambda, Stream API, Optional, Spring Boot, Spring Framework, Hibernate, JPA, Maven, Gradle, JUnit, Mockito, \(common)"

        case .python:
            return "Python, Django, Flask, FastAPI, NumPy, Pandas, list comprehension, dictionary, tuple, set, generator, decorator, async await, asyncio, pip, virtualenv, pytest, unittest, type hints, Pydantic, SQLAlchemy, Celery, \(common)"

        case .javascript:
            return "JavaScript, Node.js, Express, React, Vue, Angular, closure, hoisting, event loop, Promise, async await, callback, prototype, this keyword, arrow function, destructuring, spread operator, npm, yarn, Jest, Mocha, webpack, Babel, \(common)"

        case .typescript:
            return "TypeScript, JavaScript, React, Angular, Vue, Next.js, interface, type, enum, generic, decorator, union type, intersection type, type guard, utility types, strict mode, TSConfig, ESLint, Jest, \(common)"

        case .go:
            return "Go, Golang, goroutine, channel, defer, panic, recover, interface, struct, pointer, slice, map, mutex, WaitGroup, context, gin, echo, GORM, go mod, go test, \(common)"

        case .csharp:
            return "C#, .NET, ASP.NET, Entity Framework, LINQ, async await, Task, delegate, event, interface, abstract class, generic, dependency injection, NuGet, xUnit, NUnit, Moq, Azure Functions, \(common)"

        case .cpp:
            return "C++, STL, vector, map, set, unordered_map, pointer, reference, smart pointer, unique_ptr, shared_ptr, RAII, template, virtual function, polymorphism, inheritance, constructor, destructor, memory management, CMake, \(common)"

        case .rust:
            return "Rust, ownership, borrowing, lifetime, trait, struct, enum, Option, Result, match, async await, tokio, cargo, crate, unsafe, mutex, Arc, Rc, \(common)"

        case .general:
            return "Array, ArrayList, LinkedList, HashMap, HashSet, list, dictionary, map, set, polymorphism, inheritance, encapsulation, abstraction, interface, class, function, method, async, await, Promise, thread, process, \(common)"
        }
    }
}

/// Supported languages for the interview assistant
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case bulgarian = "bg"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .bulgarian: return "Bulgarian"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }

    var llmInstruction: String {
        if self == .english {
            return ""
        }
        return "\n\nIMPORTANT: Respond in \(displayName) language."
    }
}

/// Global app settings with UserDefaults persistence
class AppSettings {
    static let shared = AppSettings()

    private let languageKey = "ConversationAssistant.Language"
    private let techStackKey = "ConversationAssistant.TechStack"
    private let useStreamingSTTKey = "ConversationAssistant.UseStreamingSTT"

    private init() {}

    /// Enable Deepgram streaming STT (requires DEEPGRAM_API_KEY)
    var useStreamingSTT: Bool {
        get {
            // Default to true if Deepgram key is available
            if !UserDefaults.standard.bool(forKey: useStreamingSTTKey + ".set") {
                return ApiKeyManager.shared.hasKey(.deepgram)
            }
            return UserDefaults.standard.bool(forKey: useStreamingSTTKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useStreamingSTTKey)
            UserDefaults.standard.set(true, forKey: useStreamingSTTKey + ".set")
        }
    }

    var language: AppLanguage {
        get {
            guard let code = UserDefaults.standard.string(forKey: languageKey),
                  let lang = AppLanguage(rawValue: code) else {
                return .english
            }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
        }
    }

    var techStack: TechStack {
        get {
            guard let code = UserDefaults.standard.string(forKey: techStackKey),
                  let stack = TechStack(rawValue: code) else {
                return .java  // Default to Java
            }
            return stack
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: techStackKey)
        }
    }

    var languageCode: String {
        return language.rawValue
    }

    var llmLanguageInstruction: String {
        return language.llmInstruction
    }

    var whisperVocabulary: String {
        return techStack.whisperVocabulary
    }
}
