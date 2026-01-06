import Cocoa

/// Presentation: Markdown Renderer
/// Applies markdown styling to NSTextStorage
class MarkdownRenderer {

    enum Style {
        case notes      // Larger headers for notes view
        case analysis   // Smaller headers for analysis view

        var headerFontSize: CGFloat {
            switch self {
            case .notes: return 22
            case .analysis: return 18
            }
        }

        var subHeaderFontSize: CGFloat {
            switch self {
            case .notes: return 18
            case .analysis: return 16
            }
        }

        var bodyFontSize: CGFloat {
            switch self {
            case .notes: return 14
            case .analysis: return 13
            }
        }

        var codeFontSize: CGFloat {
            switch self {
            case .notes: return 13
            case .analysis: return 12
            }
        }
    }

    private let style: Style
    private let syntaxHighlighter: SyntaxHighlighter
    private let yellowColor = NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
    private let headerColor = NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
    private let codeColor = NSColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1.0)
    private let codeBackgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
    private let inlineCodeColor = NSColor(red: 0.98, green: 0.72, blue: 0.60, alpha: 1.0)
    private let inlineCodeBgColor = NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 0.8)
    private let linkColor = NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
    private let markerColor = NSColor(white: 0.5, alpha: 0.6)

    init(style: Style = .notes) {
        self.style = style
        self.syntaxHighlighter = SyntaxHighlighter(fontSize: style.codeFontSize)
    }

    /// Render markdown in the given text storage
    func render(in storage: NSTextStorage) {
        let text = storage.string

        storage.beginEditing()

        // Reset formatting - clean white text with monospace font
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: style.bodyFontSize, weight: .regular),
            .foregroundColor: NSColor(white: 0.95, alpha: 1.0)
        ]
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))

        // Apply markdown styles in correct order (most specific first)
        let codeBlockRanges = renderCodeBlocks(in: storage, text: text)
        renderHeaders(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderBold(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderItalic(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderInlineCode(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderLists(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderDividers(in: storage, text: text, excludingRanges: codeBlockRanges)
        renderLinks(in: storage, text: text, excludingRanges: codeBlockRanges)

        storage.endEditing()
    }

    // MARK: - Private Rendering Methods

    private func isRangeExcluded(_ range: NSRange, from excludedRanges: [NSRange]) -> Bool {
        excludedRanges.contains { excludedRange in
            NSIntersectionRange(range, excludedRange).length > 0
        }
    }

    private func renderHeaders(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // H1: # Header
        let h1Pattern = "^#\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: h1Pattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }

                // Style the # marker
                let hashRange = NSRange(location: match.range.location, length: 1)
                storage.addAttributes([
                    .foregroundColor: markerColor,
                    .font: NSFont.monospacedSystemFont(ofSize: style.bodyFontSize, weight: .regular)
                ], range: hashRange)

                // Style the header content
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: style.headerFontSize, weight: .bold),
                        .foregroundColor: headerColor
                    ], range: contentRange)
                }
            }
        }

        // H2+: ## Header, ### Header, etc.
        let h2Pattern = "^(#{2,6})\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: h2Pattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }

                // Style the ## markers
                if match.numberOfRanges >= 2 {
                    let hashRange = match.range(at: 1)
                    storage.addAttributes([
                        .foregroundColor: markerColor,
                        .font: NSFont.monospacedSystemFont(ofSize: style.bodyFontSize, weight: .regular)
                    ], range: hashRange)
                }

                // Style the header content
                if match.numberOfRanges >= 3 {
                    let contentRange = match.range(at: 2)
                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: style.subHeaderFontSize, weight: .semibold),
                        .foregroundColor: headerColor
                    ], range: contentRange)
                }
            }
        }
    }

    private func renderBold(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // Match **text** but not ***text***
        let boldPattern = "(?<!\\*)\\*\\*(?!\\*)(.+?)(?<!\\*)\\*\\*(?!\\*)"
        guard let regex = try? NSRegularExpression(pattern: boldPattern, options: []) else { return }

        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }

            let contentRange = match.range(at: 1)

            // Style the content as bold
            let boldColor = style == .analysis ? yellowColor : NSColor(white: 1.0, alpha: 1.0)
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: style.bodyFontSize, weight: .bold),
                .foregroundColor: boldColor
            ], range: contentRange)

            // Dim the ** markers
            let openRange = NSRange(location: match.range.location, length: 2)
            let closeRange = NSRange(location: contentRange.upperBound, length: 2)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openRange)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeRange)
        }
    }

    private func renderItalic(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // Match *text* but not **text** (single asterisk only)
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        guard let regex = try? NSRegularExpression(pattern: italicPattern, options: []) else { return }

        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }

            let contentRange = match.range(at: 1)

            // Apply italic style
            if let existingFont = storage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
                let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italicFont, range: contentRange)
            }

            // Dim the * markers
            let openRange = NSRange(location: match.range.location, length: 1)
            let closeRange = NSRange(location: contentRange.upperBound, length: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openRange)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeRange)
        }
    }

    private func renderCodeBlocks(in storage: NSTextStorage, text: String) -> [NSRange] {
        let codeBlockPattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else { return [] }

        var codeBlockRanges: [NSRange] = []
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            codeBlockRanges.append(match.range)

            // Extract language and code content
            let nsString = text as NSString
            let language = match.numberOfRanges >= 2 ? nsString.substring(with: match.range(at: 1)) : ""
            let codeContent = match.numberOfRanges >= 3 ? nsString.substring(with: match.range(at: 2)) : ""

            // Apply background to entire block first
            storage.addAttribute(.backgroundColor, value: codeBackgroundColor, range: match.range)

            // Dim the opening ``` + language line
            if match.numberOfRanges >= 2 {
                let langRange = match.range(at: 1)
                let openingEnd = langRange.upperBound + 1
                let openingRange = NSRange(location: match.range.location, length: min(openingEnd - match.range.location, match.range.length))
                storage.addAttributes([
                    .foregroundColor: markerColor,
                    .font: NSFont.monospacedSystemFont(ofSize: style.codeFontSize, weight: .regular)
                ], range: openingRange)
            }

            // Apply syntax highlighting to code content
            if match.numberOfRanges >= 3 {
                let codeRange = match.range(at: 2)
                let highlighted = syntaxHighlighter.highlight(codeContent, language: language.isEmpty ? nil : language)

                // Apply highlighted attributes to the code range
                let offset = codeRange.location
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
                    let targetRange = NSRange(location: offset + range.location, length: range.length)
                    if targetRange.upperBound <= storage.length {
                        storage.addAttributes(attrs, range: targetRange)
                        // Ensure background color is applied
                        storage.addAttribute(.backgroundColor, value: codeBackgroundColor, range: targetRange)
                    }
                }
            }

            // Dim the closing ```
            let closingStart = match.range.upperBound - 3
            if closingStart >= match.range.location {
                let closingRange = NSRange(location: closingStart, length: 3)
                storage.addAttributes([
                    .foregroundColor: markerColor,
                    .font: NSFont.monospacedSystemFont(ofSize: style.codeFontSize, weight: .regular)
                ], range: closingRange)
            }
        }

        return codeBlockRanges
    }

    private func renderInlineCode(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        let codePattern = "`([^`\\n]+)`"
        guard let regex = try? NSRegularExpression(pattern: codePattern, options: []) else { return }

        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }

            // Style the entire match (including backticks)
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: style.codeFontSize, weight: .medium),
                .foregroundColor: inlineCodeColor,
                .backgroundColor: inlineCodeBgColor
            ], range: match.range)

            // Dim the backticks
            let openRange = NSRange(location: match.range.location, length: 1)
            let closeRange = NSRange(location: match.range.upperBound - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openRange)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeRange)
        }
    }

    private func renderLists(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // Match bullet lists (- item) and numbered lists (1. item)
        let listPattern = "^([ \\t]*)([-*+]|\\d+\\.)\\s"
        guard let regex = try? NSRegularExpression(pattern: listPattern, options: .anchorsMatchLines) else { return }

        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }

            // Style the bullet/number marker in yellow
            if match.numberOfRanges >= 3 {
                let markerRange = match.range(at: 2)
                storage.addAttributes([
                    .foregroundColor: yellowColor,
                    .font: NSFont.systemFont(ofSize: style.bodyFontSize, weight: .semibold)
                ], range: markerRange)
            }
        }
    }

    private func renderDividers(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // Match horizontal rules: ---, ***, ___ (with optional spaces)
        let dividerPattern = "^[ \\t]*[-*_]{3,}[ \\t]*$"
        guard let regex = try? NSRegularExpression(pattern: dividerPattern, options: .anchorsMatchLines) else { return }

        // Process matches in reverse to avoid range shifting when replacing
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard !isRangeExcluded(match.range, from: excludingRanges) else { continue }

            // Replace with a long horizontal line
            let dividerLine = "────────────────────────────────────────────────"
            let attributedDivider = NSAttributedString(string: dividerLine, attributes: [
                .foregroundColor: yellowColor.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: style.bodyFontSize, weight: .light)
            ])
            storage.replaceCharacters(in: match.range, with: attributedDivider)
        }
    }

    private func renderLinks(in storage: NSTextStorage, text: String, excludingRanges: [NSRange]) {
        // Match [text](url) links
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else { return }

        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match = match, !isRangeExcluded(match.range, from: excludingRanges) else { return }
            guard match.numberOfRanges >= 3 else { return }

            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)

            // Style the link text
            storage.addAttributes([
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)

            // Dim the brackets and URL
            let openBracket = NSRange(location: match.range.location, length: 1)
            let closeBracket = NSRange(location: textRange.upperBound, length: 1)
            let openParen = NSRange(location: urlRange.location - 1, length: 1)
            let closeParen = NSRange(location: urlRange.upperBound, length: 1)

            storage.addAttribute(.foregroundColor, value: markerColor, range: openBracket)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeBracket)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openParen)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeParen)
            storage.addAttribute(.foregroundColor, value: markerColor.withAlphaComponent(0.4), range: urlRange)
        }
    }
}
