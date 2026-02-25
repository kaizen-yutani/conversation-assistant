import Foundation

/// Value object representing a code block with language and content
struct CodeBlock {
    let language: String
    let code: String

    init(language: String, code: String) {
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = code
    }

    /// Check if code block is empty
    var isEmpty: Bool {
        return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Get language display name
    var displayLanguage: String {
        switch language.lowercased() {
        case "python", "py":
            return "Python"
        case "javascript", "js":
            return "JavaScript"
        case "typescript", "ts":
            return "TypeScript"
        case "java":
            return "Java"
        case "cpp", "c++":
            return "C++"
        case "swift":
            return "Swift"
        case "go":
            return "Go"
        case "rust", "rs":
            return "Rust"
        default:
            return language.capitalized
        }
    }
}

// Make it Equatable
extension CodeBlock: Equatable {
    static func == (lhs: CodeBlock, rhs: CodeBlock) -> Bool {
        return lhs.language == rhs.language && lhs.code == rhs.code
    }
}

// Make it Hashable
extension CodeBlock: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(language)
        hasher.combine(code)
    }
}

// Make it Codable
extension CodeBlock: Codable {}
