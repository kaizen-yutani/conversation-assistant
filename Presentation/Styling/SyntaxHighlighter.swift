import Cocoa

/// Syntax highlighter for code blocks using One Dark theme colors
class SyntaxHighlighter {

    // MARK: - One Dark Theme

    private let keyword = NSColor(red: 0.78, green: 0.47, blue: 0.80, alpha: 1.0)    // Purple
    private let type = NSColor(red: 0.90, green: 0.73, blue: 0.46, alpha: 1.0)       // Yellow
    private let string = NSColor(red: 0.59, green: 0.78, blue: 0.50, alpha: 1.0)     // Green
    private let number = NSColor(red: 0.82, green: 0.58, blue: 0.46, alpha: 1.0)     // Orange
    private let comment = NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0)    // Gray
    private let function = NSColor(red: 0.38, green: 0.71, blue: 0.93, alpha: 1.0)   // Blue
    private let plain = NSColor(red: 0.87, green: 0.89, blue: 0.91, alpha: 1.0)      // Off-white
    private let decorator = NSColor(red: 0.90, green: 0.73, blue: 0.46, alpha: 1.0)  // Yellow

    private let codeFont: NSFont
    private let codeBgColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)

    // Language keywords
    private let keywords: [String: Set<String>] = [
        "python": Set(["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from",
                       "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass",
                       "break", "continue", "and", "or", "not", "in", "is", "async", "await", "None",
                       "True", "False", "global", "nonlocal", "assert", "del"]),
        "java": Set(["public", "private", "protected", "class", "interface", "extends", "implements",
                     "static", "final", "void", "int", "long", "double", "float", "boolean", "char",
                     "byte", "short", "new", "return", "if", "else", "for", "while", "do", "switch",
                     "case", "default", "break", "continue", "try", "catch", "finally", "throw",
                     "throws", "import", "package", "this", "super", "null", "true", "false",
                     "abstract", "synchronized", "volatile", "instanceof", "enum", "var", "record"]),
        "javascript": Set(["function", "const", "let", "var", "if", "else", "for", "while", "do",
                           "switch", "case", "default", "break", "continue", "return", "try", "catch",
                           "finally", "throw", "class", "extends", "new", "this", "super", "import",
                           "export", "from", "as", "async", "await", "yield", "of", "in", "typeof",
                           "instanceof", "delete", "void", "null", "undefined", "true", "false", "NaN"]),
        "sql": Set(["SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND",
                    "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "GROUP", "BY", "ORDER", "ASC",
                    "DESC", "LIMIT", "OFFSET", "HAVING", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
                    "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "DISTINCT", "AS",
                    "CASE", "WHEN", "THEN", "ELSE", "END", "UNION", "ALL", "EXISTS", "COUNT", "SUM",
                    "AVG", "MAX", "MIN", "COALESCE", "CAST", "select", "from", "where", "join", "and",
                    "or", "not", "in", "is", "null", "like", "order", "by", "group", "having", "as"]),
        "swift": Set(["func", "class", "struct", "enum", "protocol", "extension", "var", "let", "if",
                      "else", "guard", "for", "while", "repeat", "switch", "case", "default", "break",
                      "continue", "return", "try", "catch", "throw", "throws", "defer", "import",
                      "self", "Self", "super", "nil", "true", "false", "public", "private", "internal",
                      "static", "final", "override", "mutating", "lazy", "weak", "async", "await"]),
        "go": Set(["func", "package", "import", "type", "struct", "interface", "var", "const", "if",
                   "else", "for", "range", "switch", "case", "default", "break", "continue", "return",
                   "go", "select", "chan", "map", "make", "new", "defer", "panic", "recover", "nil",
                   "true", "false", "iota"])
    ]

    private let builtinTypes = Set(["String", "Int", "Integer", "Long", "Double", "Float", "Boolean",
                                     "Bool", "List", "Array", "Dict", "Dictionary", "Map", "Set",
                                     "HashMap", "HashSet", "ArrayList", "Optional", "Result", "Void",
                                     "Object", "Number", "Date", "Error", "Exception", "Promise"])

    init(fontSize: CGFloat = 12) {
        self.codeFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Highlight code with optional language hint
    func highlight(_ code: String, language: String? = nil) -> NSAttributedString {
        // Handle empty code
        guard !code.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttrs())
        }

        let lang = (language ?? detectLanguage(code)).lowercased()
        let langKeywords = keywords[lang] ?? keywords["python"]!.union(keywords["java"]!).union(keywords["javascript"]!)

        let result = NSMutableAttributedString()
        let lines = code.components(separatedBy: "\n")
        var inMultiLineComment = false

        for (i, line) in lines.enumerated() {
            let (highlighted, stillInComment) = highlightLine(line, keywords: langKeywords, lang: lang, inComment: inMultiLineComment)
            inMultiLineComment = stillInComment
            result.append(highlighted)
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttrs()))
            }
        }

        return result
    }

    /// Get background color for code blocks
    var backgroundColor: NSColor { codeBgColor }

    // MARK: - Private

    private func baseAttrs() -> [NSAttributedString.Key: Any] {
        [.font: codeFont, .foregroundColor: plain]
    }

    private func detectLanguage(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.contains("def ") && lower.contains(":") { return "python" }
        if lower.contains("public class") || lower.contains("public static void") { return "java" }
        if lower.contains("function") || lower.contains("const ") || lower.contains("=>") { return "javascript" }
        if lower.contains("select") && lower.contains("from") { return "sql" }
        if lower.contains("func ") && lower.contains("->") { return "swift" }
        if lower.contains("package ") && lower.contains("func ") { return "go" }
        return "generic"
    }

    private func highlightLine(_ line: String, keywords: Set<String>, lang: String, inComment: Bool) -> (NSAttributedString, Bool) {
        let result = NSMutableAttributedString()
        let stillInComment = inComment

        // Handle empty line
        guard !line.isEmpty else {
            return (result, stillInComment)
        }

        // Handle ongoing multi-line comment
        if stillInComment {
            if let endIdx = line.range(of: "*/") {
                let commentPart = String(line[..<endIdx.upperBound])
                result.append(NSAttributedString(string: commentPart, attributes: [.font: codeFont, .foregroundColor: comment]))
                let rest = String(line[endIdx.upperBound...])
                let (restHighlighted, _) = highlightLine(rest, keywords: keywords, lang: lang, inComment: false)
                result.append(restHighlighted)
                return (result, false)
            } else {
                result.append(NSAttributedString(string: line, attributes: [.font: codeFont, .foregroundColor: comment]))
                return (result, true)
            }
        }

        // Find single-line comment start
        let commentStart = findSingleLineComment(line, lang: lang)

        // Find multi-line comment start
        if let multiStart = line.range(of: "/*") {
            if commentStart == nil || multiStart.lowerBound < commentStart! {
                let before = String(line[..<multiStart.lowerBound])
                result.append(highlightTokens(before, keywords: keywords))
                let after = String(line[multiStart.lowerBound...])
                // Safe range check - need at least 3 chars to search for */ after /*
                if after.count > 2 {
                    let searchStart = after.index(after.startIndex, offsetBy: 2)
                    if let endIdx = after.range(of: "*/", range: searchStart..<after.endIndex) {
                        let commentText = String(after[..<endIdx.upperBound])
                        result.append(NSAttributedString(string: commentText, attributes: [.font: codeFont, .foregroundColor: comment]))
                        let remaining = String(after[endIdx.upperBound...])
                        result.append(highlightTokens(remaining, keywords: keywords))
                        return (result, false)
                    }
                }
                // No closing */ found on this line
                result.append(NSAttributedString(string: after, attributes: [.font: codeFont, .foregroundColor: comment]))
                return (result, true)
            }
        }

        // Handle single-line comment
        if let commentIdx = commentStart {
            let code = String(line[..<commentIdx])
            let commentText = String(line[commentIdx...])
            result.append(highlightTokens(code, keywords: keywords))
            result.append(NSAttributedString(string: commentText, attributes: [.font: codeFont, .foregroundColor: comment]))
            return (result, false)
        }

        // No comments - highlight tokens
        result.append(highlightTokens(line, keywords: keywords))
        return (result, false)
    }

    private func findSingleLineComment(_ line: String, lang: String) -> String.Index? {
        var inString = false
        var stringChar: Character = "\""
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            if !inString && (char == "\"" || char == "'") {
                inString = true
                stringChar = char
            } else if inString && char == stringChar {
                if i > line.startIndex && line[line.index(before: i)] != "\\" {
                    inString = false
                }
            }

            if !inString {
                if char == "/" && line.index(after: i) < line.endIndex && line[line.index(after: i)] == "/" {
                    return i
                }
                if char == "#" && lang == "python" { return i }
                if char == "-" && lang == "sql" && line.index(after: i) < line.endIndex && line[line.index(after: i)] == "-" {
                    return i
                }
            }
            i = line.index(after: i)
        }
        return nil
    }

    private func highlightTokens(_ text: String, keywords: Set<String>) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Handle empty text
        guard !text.isEmpty else { return result }

        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]

            // Strings
            if char == "\"" || char == "'" {
                let (str, end) = extractString(text, from: i, quote: char)
                result.append(NSAttributedString(string: str, attributes: [.font: codeFont, .foregroundColor: string]))
                i = end
                continue
            }

            // Decorators
            if char == "@" {
                let (word, end) = extractWord(text, from: i, includePrefix: true)
                result.append(NSAttributedString(string: word, attributes: [.font: codeFont, .foregroundColor: decorator]))
                i = end
                continue
            }

            // Numbers
            let nextIndex = text.index(after: i)
            let hasNextChar = nextIndex < text.endIndex
            if char.isNumber || (char == "." && hasNextChar && text[nextIndex].isNumber) {
                let (num, end) = extractNumber(text, from: i)
                result.append(NSAttributedString(string: num, attributes: [.font: codeFont, .foregroundColor: number]))
                i = end
                continue
            }

            // Words
            if char.isLetter || char == "_" {
                let (word, end) = extractWord(text, from: i)
                let color: NSColor
                if keywords.contains(word) {
                    color = keyword
                } else if builtinTypes.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                    color = type
                } else if end < text.endIndex && text[end] == "(" {
                    color = function
                } else {
                    color = plain
                }
                result.append(NSAttributedString(string: word, attributes: [.font: codeFont, .foregroundColor: color]))
                i = end
                continue
            }

            // Default character
            result.append(NSAttributedString(string: String(char), attributes: baseAttrs()))
            i = text.index(after: i)
        }

        return result
    }

    private func extractString(_ text: String, from start: String.Index, quote: Character) -> (String, String.Index) {
        var result = String(quote)
        var i = text.index(after: start)
        while i < text.endIndex {
            let char = text[i]
            result.append(char)
            if char == quote && (i == text.index(after: start) || text[text.index(before: i)] != "\\") {
                return (result, text.index(after: i))
            }
            i = text.index(after: i)
        }
        return (result, text.endIndex)
    }

    private func extractWord(_ text: String, from start: String.Index, includePrefix: Bool = false) -> (String, String.Index) {
        var result = ""
        var i = start
        if includePrefix && i < text.endIndex && text[i] == "@" {
            result.append("@")
            i = text.index(after: i)
        }
        while i < text.endIndex && (text[i].isLetter || text[i].isNumber || text[i] == "_") {
            result.append(text[i])
            i = text.index(after: i)
        }
        return (result, i)
    }

    private func extractNumber(_ text: String, from start: String.Index) -> (String, String.Index) {
        var result = ""
        var i = start
        var hasDecimal = false
        while i < text.endIndex {
            let char = text[i]
            if char.isNumber || char.isHexDigit {
                result.append(char)
            } else if char == "." && !hasDecimal {
                hasDecimal = true
                result.append(char)
            } else if (char == "x" || char == "X") && result == "0" {
                result.append(char)
            } else {
                break
            }
            i = text.index(after: i)
        }
        return (result, i)
    }
}
