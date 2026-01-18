import Cocoa

/// Factory for creating timeline message views
/// Extracts view creation logic from the main delegate
class MessageViewFactory {
    private let syntaxHighlighter: SyntaxHighlighter
    private var containerWidth: CGFloat

    init(syntaxHighlighter: SyntaxHighlighter, containerWidth: CGFloat) {
        self.syntaxHighlighter = syntaxHighlighter
        self.containerWidth = containerWidth
    }

    /// Update container width (e.g., on resize)
    func updateContainerWidth(_ width: CGFloat) {
        self.containerWidth = width
    }

    // MARK: - Message View Creation

    func createMessageView(for message: ConversationMessage) -> NSView {
        // Determine styling based on message type
        let isQuestion = message.type == .question
        let isStatus = message.type == .status
        let isScreenshot = message.type == .screenshot
        let isAnswer = message.type == .answer || message.type == .followUp

        // Layout: badge on left, card after badge, answers indented 20px
        let badgeWidth: CGFloat = 22
        let badgeGap: CGFloat = 8
        let answerIndent: CGFloat = 20

        // Badge position: questions at 0, answers indented
        let badgeX: CGFloat = isAnswer ? answerIndent : 0
        // Card starts after badge
        let cardX: CGFloat = badgeX + badgeWidth + badgeGap
        let cardWidth = containerWidth - 40 - cardX

        // Layout constants
        let headerHeight: CGFloat = 28
        let contentPadding: CGFloat = 12
        let textWidth = cardWidth - 52  // Account for icon and padding

        // Create content view first to measure actual height
        let contentView = NSTextView(frame: NSRect(x: 12, y: 0, width: textWidth + 28, height: 1000))
        contentView.isEditable = false
        contentView.isSelectable = true
        contentView.drawsBackground = false
        contentView.backgroundColor = .clear
        contentView.textContainerInset = .zero
        contentView.textContainer?.lineFragmentPadding = 0
        contentView.textContainer?.containerSize = NSSize(width: textWidth + 28, height: CGFloat.greatestFiniteMagnitude)

        // Apply formatting
        let attributedContent = formatMessageContent(message.content, isQuestion: isQuestion)
        contentView.textStorage?.setAttributedString(attributedContent)

        // Get actual text height from layout manager
        contentView.layoutManager?.ensureLayout(for: contentView.textContainer!)
        let actualTextHeight = contentView.layoutManager?.usedRect(for: contentView.textContainer!).height ?? 30
        let viewHeight = max(actualTextHeight + headerHeight + contentPadding * 2, 60)

        // Now set correct frame for content view
        contentView.frame = NSRect(x: 12, y: contentPadding, width: textWidth + 28, height: actualTextHeight)

        // Outer container to hold badge + card
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: containerWidth - 40, height: viewHeight))

        // Q/A Badge - small monochrome pill on the left
        if isQuestion || isAnswer {
            let badgeText = isQuestion ? "Q" : "A"
            let badgeColor = isQuestion ? NSColor.appleGold : NSColor.appleGreen

            let badge = NSView(frame: NSRect(x: badgeX, y: viewHeight - 26, width: badgeWidth, height: badgeWidth))
            badge.wantsLayer = true
            badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
            badge.layer?.cornerRadius = badgeWidth / 2

            let badgeLabel = NSTextField(labelWithString: badgeText)
            badgeLabel.frame = NSRect(x: 0, y: 3, width: badgeWidth, height: 16)
            badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
            badgeLabel.textColor = badgeColor
            badgeLabel.alignment = .center
            badge.addSubview(badgeLabel)
            outerContainer.addSubview(badge)
        }

        // Main card container with subtle background
        let container = NSView(frame: NSRect(x: cardX, y: 0, width: cardWidth, height: viewHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let accentColor: NSColor
        let symbolName: String

        if isQuestion {
            accentColor = NSColor.appleGold
            symbolName = "mic.fill"
        } else if isStatus {
            accentColor = NSColor.white.withAlphaComponent(0.5)
            symbolName = "info.circle.fill"
        } else if isScreenshot {
            accentColor = NSColor.applePurple
            symbolName = "camera.fill"
        } else {
            // Answer, followUp, userResponse all treated as AI response
            accentColor = NSColor.appleGreen
            symbolName = "sparkles"
        }

        // No card background - clean look

        // Left accent bar - thinner and more subtle
        let accentBar = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: viewHeight))
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = accentColor.cgColor
        accentBar.layer?.cornerRadius = 1.5
        accentBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        container.addSubview(accentBar)

        // SF Symbol icon
        let iconSize: CGFloat = 16
        if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let iconView = NSImageView(frame: NSRect(x: 12, y: viewHeight - headerHeight + 2, width: iconSize, height: iconSize))
            iconView.image = symbolImage
            iconView.contentTintColor = accentColor
            iconView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(iconView)
        }

        // Header label only for status/screenshot (Q/A have badges instead)
        if isStatus || isScreenshot {
            let headerText = isStatus ? "Status" : "Screenshot"
            let headerLabel = NSTextField(labelWithString: headerText)
            headerLabel.frame = NSRect(x: 32, y: viewHeight - headerHeight + 2, width: 80, height: 18)
            headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            headerLabel.textColor = accentColor
            container.addSubview(headerLabel)
        }

        // Topic badge if present - modern pill style
        let topicX: CGFloat = (isStatus || isScreenshot) ? 110 : 32
        if let topic = message.topic, topic != "followUp" && topic != "answer" && topic != "unknown" {
            let topicPill = NSView(frame: NSRect(x: topicX, y: viewHeight - headerHeight + 2, width: 0, height: 18))
            topicPill.wantsLayer = true
            topicPill.layer?.backgroundColor = accentColor.withAlphaComponent(0.15).cgColor
            topicPill.layer?.cornerRadius = 9

            let topicLabel = NSTextField(labelWithString: topic.lowercased())
            topicLabel.font = .systemFont(ofSize: 10, weight: .medium)
            topicLabel.textColor = accentColor
            topicLabel.sizeToFit()

            let pillWidth = topicLabel.frame.width + 16
            topicPill.frame.size.width = pillWidth
            topicLabel.frame.origin = NSPoint(x: 8, y: 2)
            topicPill.addSubview(topicLabel)
            container.addSubview(topicPill)
        }

        // Latency label (if available)
        if let latencyDisplay = message.displayLatency {
            let latencyLabel = NSTextField(labelWithString: "⚡\(latencyDisplay)")
            latencyLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            latencyLabel.textColor = NSColor.appleGreen.withAlphaComponent(0.7)
            latencyLabel.sizeToFit()
            let latencyWidth = latencyLabel.frame.width + 8
            latencyLabel.frame = NSRect(x: cardWidth - 80 - latencyWidth, y: viewHeight - headerHeight + 2, width: latencyLabel.frame.width, height: 18)
            container.addSubview(latencyLabel)
        }

        // Time label - right aligned, subtle
        let timeLabel = NSTextField(labelWithString: message.displayTime)
        timeLabel.frame = NSRect(x: cardWidth - 80, y: viewHeight - headerHeight + 2, width: 70, height: 18)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        // Add the pre-measured content view
        container.addSubview(contentView)

        // Add card to outer container
        outerContainer.addSubview(container)

        return outerContainer
    }

    // MARK: - Text Formatting

    func formatMessageContent(_ text: String, isQuestion: Bool) -> NSAttributedString {
        let baseFont = isQuestion ? NSFont.systemFont(ofSize: 18, weight: .medium) : NSFont.systemFont(ofSize: 17, weight: .regular)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let labelFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let codeBgColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.5)

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLanguage = ""

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block - apply syntax highlighting
                    if !codeBlockContent.isEmpty {
                        let highlighted = syntaxHighlighter.highlight(codeBlockContent, language: codeBlockLanguage.isEmpty ? nil : codeBlockLanguage)
                        let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
                        // Apply background to entire code block
                        mutableHighlighted.addAttribute(NSAttributedString.Key.backgroundColor, value: codeBgColor, range: NSRange(location: 0, length: mutableHighlighted.length))
                        result.append(mutableHighlighted)
                    }
                    codeBlockContent = ""
                    codeBlockLanguage = ""
                    inCodeBlock = false
                } else {
                    // Start code block - extract language
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeBlockContent += (codeBlockContent.isEmpty ? "" : "\n") + line
            } else {
                // Format line based on content type
                let formattedLine = formatAnswerLine(line, baseFont: baseFont, codeFont: codeFont, labelFont: labelFont)
                result.append(formattedLine)
                if index < lines.count - 1 {
                    let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: NSColor.white]
                    result.append(NSAttributedString(string: "\n", attributes: attrs))
                }
            }
        }

        return result
    }

    private func formatAnswerLine(_ line: String, baseFont: NSFont, codeFont: NSFont, labelFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseAttrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: NSColor.white]
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Check for comparison format: "X: value | Y: value"
        if trimmedLine.contains(" | ") && trimmedLine.contains(":") {
            let parts = trimmedLine.components(separatedBy: " | ")
            for (idx, part) in parts.enumerated() {
                if let colonIndex = part.firstIndex(of: ":") {
                    let label = String(part[..<colonIndex])
                    let value = String(part[part.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                    // Colored label
                    let labelColor = idx == 0 ? NSColor.systemCyan : NSColor.systemPink
                    let labelAttrs: [NSAttributedString.Key: Any] = [
                        .font: labelFont,
                        .foregroundColor: labelColor
                    ]
                    result.append(NSAttributedString(string: label, attributes: labelAttrs))
                    result.append(NSAttributedString(string: ": ", attributes: baseAttrs))

                    // Value with inline code support
                    let valueFormatted = formatInlineCode(value, baseAttrs: baseAttrs, codeFont: codeFont)
                    result.append(valueFormatted)
                } else {
                    result.append(formatInlineCode(part, baseAttrs: baseAttrs, codeFont: codeFont))
                }

                if idx < parts.count - 1 {
                    let separatorAttrs: [NSAttributedString.Key: Any] = [
                        .font: baseFont,
                        .foregroundColor: NSColor.gray
                    ]
                    result.append(NSAttributedString(string: "  │  ", attributes: separatorAttrs))
                }
            }
            return result
        }

        // Check for bullet point
        let bulletPrefixes = ["• ", "- ", "* ", "· ", "▸ "]
        for prefix in bulletPrefixes {
            if trimmedLine.hasPrefix(prefix) {
                let content = String(trimmedLine.dropFirst(prefix.count))
                let bulletAttrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.appleGold
                ]
                result.append(NSAttributedString(string: "▸ ", attributes: bulletAttrs))

                // Check if bullet content has comparison format
                if content.contains(" | ") && content.contains(":") {
                    let innerFormatted = formatAnswerLine(content, baseFont: baseFont, codeFont: codeFont, labelFont: labelFont)
                    result.append(innerFormatted)
                } else {
                    result.append(formatInlineCode(content, baseAttrs: baseAttrs, codeFont: codeFont))
                }
                return result
            }
        }

        // Check for "When to use:" or similar headers
        let headerPrefixes = ["When to use:", "Use case:", "Tip:", "Note:", "Gotcha:", "Senior tip:"]
        for prefix in headerPrefixes {
            if trimmedLine.lowercased().hasPrefix(prefix.lowercased()) {
                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: NSColor.systemOrange
                ]
                result.append(NSAttributedString(string: prefix, attributes: headerAttrs))
                let rest = String(trimmedLine.dropFirst(prefix.count))
                result.append(formatInlineCode(rest, baseAttrs: baseAttrs, codeFont: codeFont))
                return result
            }
        }

        // Regular line with inline code support
        return formatInlineCode(line, baseAttrs: baseAttrs, codeFont: codeFont)
    }

    private func formatInlineCode(_ text: String, baseAttrs: [NSAttributedString.Key: Any], codeFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Combined pattern for **bold** and `code`
        let pattern = "\\*\\*([^*]+)\\*\\*|`([^`]+)`"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return NSAttributedString(string: text, attributes: baseAttrs)
        }

        var lastEnd = text.startIndex
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            // Add text before match
            if lastEnd < matchRange.lowerBound {
                let beforeText = String(text[lastEnd..<matchRange.lowerBound])
                result.append(NSAttributedString(string: beforeText, attributes: baseAttrs))
            }

            // Check which group matched: group 1 = bold, group 2 = code
            if let boldRange = Range(match.range(at: 1), in: text) {
                // **bold** text - yellow and bold
                let boldText = String(text[boldRange])
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                    .foregroundColor: NSColor.appleGold
                ]
                result.append(NSAttributedString(string: boldText, attributes: boldAttrs))
            } else if let codeRange = Range(match.range(at: 2), in: text) {
                // `code` text - orange monospace
                let codeText = String(text[codeRange])
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.black.withAlphaComponent(0.2)
                ]
                result.append(NSAttributedString(string: codeText, attributes: codeAttrs))
            }

            lastEnd = matchRange.upperBound
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            let remainingText = String(text[lastEnd...])
            result.append(NSAttributedString(string: remainingText, attributes: baseAttrs))
        }

        return result
    }

    func estimateTextHeight(_ text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 17)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(30, ceil(boundingRect.height))
    }
}
