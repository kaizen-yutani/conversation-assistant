import Foundation

/// Domain entity representing AI analysis of a coding task
class Analysis {
    let content: String
    let codeBlocks: [CodeBlock]
    let createdAt: Date

    init(content: String, codeBlocks: [CodeBlock] = [], createdAt: Date = Date()) {
        self.content = content
        self.codeBlocks = codeBlocks
        self.createdAt = createdAt
    }

    /// Extract code blocks from markdown content
    /// - Parameter markdownContent: Content with markdown code blocks
    /// - Returns: Analysis with extracted code blocks
    static func fromMarkdown(_ markdownContent: String) -> Analysis {
        var codeBlocks: [CodeBlock] = []

        // Regex pattern for markdown code blocks: ```language\ncode\n```
        let pattern = "```(\\w+)?\\n([\\s\\S]*?)```"

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = markdownContent as NSString
            let matches = regex.matches(in: markdownContent, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                let languageRange = match.range(at: 1)
                let codeRange = match.range(at: 2)

                let language = languageRange.location != NSNotFound
                    ? nsString.substring(with: languageRange)
                    : "text"

                let code = nsString.substring(with: codeRange)

                codeBlocks.append(CodeBlock(language: language, code: code))
            }
        }

        return Analysis(content: markdownContent, codeBlocks: codeBlocks)
    }

    /// Get plain text without code blocks
    var textOnly: String {
        var text = content

        // Remove code blocks
        let pattern = "```(\\w+)?\\n[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.count),
                withTemplate: ""
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if analysis has any code
    var hasCode: Bool {
        return !codeBlocks.isEmpty
    }
}
