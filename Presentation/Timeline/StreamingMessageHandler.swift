import Cocoa

/// Protocol for streaming message handler callbacks
protocol StreamingMessageHandlerDelegate: AnyObject {
    var voiceMessages: [ConversationMessage] { get set }
    func updateFloatingQA()
}

/// Handles creation and updates of streaming answer messages in the timeline
class StreamingMessageHandler {
    private weak var timelineContainer: NSView?
    private weak var scrollView: NSScrollView?
    private let messageViewFactory: MessageViewFactory
    private weak var delegate: StreamingMessageHandlerDelegate?

    // Current streaming state
    private(set) var currentTextView: NSTextView?
    private(set) var currentContainer: NSView?

    init(timelineContainer: NSView, scrollView: NSScrollView, messageViewFactory: MessageViewFactory, delegate: StreamingMessageHandlerDelegate) {
        self.timelineContainer = timelineContainer
        self.scrollView = scrollView
        self.messageViewFactory = messageViewFactory
        self.delegate = delegate
    }

    /// Add an empty streaming message that will be updated
    func addStreamingMessage(type: ConversationMessage.MessageType, topic: String?, latencyMs: Int? = nil) {
        guard let timelineContainer = timelineContainer else { return }

        let message = ConversationMessage(type: type, content: "▌", topic: topic, responseLatencyMs: latencyMs)
        delegate?.voiceMessages.append(message)

        // Layout
        let badgeSize: CGFloat = 28
        let badgeGap: CGFloat = 10
        let answerIndent: CGFloat = 20
        let badgeX: CGFloat = answerIndent
        let cardX: CGFloat = badgeX + badgeSize + badgeGap
        let cardWidth = timelineContainer.frame.width - 40 - cardX
        let initialHeight: CGFloat = 80

        // Outer container
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: timelineContainer.frame.width - 40, height: initialHeight))
        outerContainer.identifier = NSUserInterfaceItemIdentifier("streamingOuter")

        // A Badge — Dynamic Island style
        let badge = NSView(frame: NSRect(x: badgeX, y: initialHeight - 30, width: badgeSize, height: badgeSize))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.messageAnswer.withAlphaComponent(0.18).cgColor
        badge.layer?.cornerRadius = badgeSize / 2
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.messageAnswer.withAlphaComponent(0.40).cgColor
        badge.identifier = NSUserInterfaceItemIdentifier("streamingBadge")

        let badgeLabel = NSTextField(labelWithString: "A")
        badgeLabel.frame = NSRect(x: 0, y: 5, width: badgeSize, height: 18)
        badgeLabel.font = .systemFont(ofSize: 13, weight: .bold)
        badgeLabel.textColor = NSColor.messageAnswer
        badgeLabel.alignment = .center
        badge.addSubview(badgeLabel)
        outerContainer.addSubview(badge)

        // Card container
        let container = NSView(frame: NSRect(x: cardX, y: 0, width: cardWidth, height: initialHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16

        // Card background — subtle tinted surface
        container.layer?.backgroundColor = NSColor.messageAnswer.withAlphaComponent(0.05).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.identifier = NSUserInterfaceItemIdentifier("streamingContainer")

        // Accent bar
        let lineView = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: initialHeight))
        lineView.wantsLayer = true
        lineView.layer?.backgroundColor = NSColor.messageAnswer.cgColor
        lineView.layer?.cornerRadius = 1.5
        lineView.identifier = NSUserInterfaceItemIdentifier("streamingLine")
        container.addSubview(lineView)

        // Animated border pulse during streaming (no gradient)
        let borderPulse = CABasicAnimation(keyPath: "borderColor")
        borderPulse.fromValue = NSColor.messageAnswer.withAlphaComponent(0.20).cgColor
        borderPulse.toValue = NSColor.messageAnswer.withAlphaComponent(0.50).cgColor
        borderPulse.duration = 2.0
        borderPulse.autoreverses = true
        borderPulse.repeatCount = .infinity
        borderPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.layer?.add(borderPulse, forKey: "streamingBorderPulse")

        // Accent bar opacity pulse
        let accentPulse = CABasicAnimation(keyPath: "opacity")
        accentPulse.fromValue = 0.5
        accentPulse.toValue = 1.0
        accentPulse.duration = 1.5
        accentPulse.autoreverses = true
        accentPulse.repeatCount = .infinity
        accentPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        lineView.layer?.add(accentPulse, forKey: "streamingPulse")

        // Badge scale pulse
        let badgePulse = CABasicAnimation(keyPath: "transform.scale")
        badgePulse.fromValue = 1.0
        badgePulse.toValue = 1.08
        badgePulse.duration = 1.5
        badgePulse.autoreverses = true
        badgePulse.repeatCount = .infinity
        badgePulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        badge.layer?.add(badgePulse, forKey: "streamingBadgePulse")

        // SF Symbol icon
        if let symbolImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
            let iconView = NSImageView(frame: NSRect(x: 16, y: initialHeight - 24, width: 16, height: 16))
            iconView.image = symbolImage
            iconView.contentTintColor = NSColor.messageAnswer
            iconView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(iconView)
        }

        // Latency label
        if let latencyDisplay = message.displayLatency {
            let latencyLabel = NSTextField(labelWithString: "\(latencyDisplay)")
            latencyLabel.frame = NSRect(x: cardWidth - 145, y: initialHeight - 24, width: 55, height: 16)
            latencyLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            latencyLabel.textColor = NSColor.accentPrimary.withAlphaComponent(0.7)
            latencyLabel.alignment = .right
            latencyLabel.identifier = NSUserInterfaceItemIdentifier("streamingLatencyLabel")
            container.addSubview(latencyLabel)
        }

        // Time label
        let timeLabel = NSTextField(labelWithString: message.displayTime)
        timeLabel.frame = NSRect(x: cardWidth - 80, y: initialHeight - 24, width: 70, height: 16)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = NSColor.textTertiary
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        // Topic badge
        if let topic = topic, topic != "followUp" && topic != "answer" && topic != "unknown" {
            let topicPill = NSView(frame: NSRect(x: 36, y: initialHeight - 24, width: 0, height: 20))
            topicPill.wantsLayer = true
            topicPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            topicPill.layer?.cornerRadius = 10
            topicPill.layer?.borderWidth = 1
            topicPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            topicPill.identifier = NSUserInterfaceItemIdentifier("streamingTopicPill")

            let topicLabel = NSTextField(labelWithString: topic.lowercased())
            topicLabel.font = .systemFont(ofSize: 10, weight: .medium)
            topicLabel.textColor = NSColor.textSecondary
            topicLabel.sizeToFit()

            topicPill.frame.size.width = topicLabel.frame.width + 16
            topicLabel.frame.origin = NSPoint(x: 8, y: 3)
            topicPill.addSubview(topicLabel)
            container.addSubview(topicPill)
        }

        // Loading spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: initialHeight / 2 - 20, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.identifier = NSUserInterfaceItemIdentifier("streamingSpinner")
        container.addSubview(spinner)

        // Loading label
        let loadingLabel = NSTextField(labelWithString: "Generating answer...")
        loadingLabel.frame = NSRect(x: 45, y: initialHeight / 2 - 18, width: 150, height: 16)
        loadingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        loadingLabel.textColor = NSColor.textSecondary
        loadingLabel.identifier = NSUserInterfaceItemIdentifier("streamingLoadingLabel")
        container.addSubview(loadingLabel)

        // Streaming text view (hidden initially)
        let textView = NSTextView(frame: NSRect(x: 16, y: 10, width: cardWidth - 32, height: initialHeight - 40))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .textPrimary
        textView.string = ""
        textView.isHidden = true
        textView.identifier = NSUserInterfaceItemIdentifier("streamingText")
        container.addSubview(textView)

        outerContainer.addSubview(container)

        // Subtle teal glow during streaming
        container.layer?.shadowColor = NSColor.messageAnswer.cgColor
        container.layer?.shadowRadius = 10
        container.layer?.shadowOffset = .zero
        container.layer?.shadowOpacity = 0.0

        let glowIn = CABasicAnimation(keyPath: "shadowOpacity")
        glowIn.fromValue = 0.0
        glowIn.toValue = 0.12
        glowIn.duration = 0.5
        glowIn.fillMode = .forwards
        glowIn.isRemovedOnCompletion = false
        container.layer?.add(glowIn, forKey: "streamingGlowIn")

        currentTextView = textView
        currentContainer = container

        // Position below question
        var topMessageMaxY: CGFloat = 10
        for subview in timelineContainer.subviews {
            if subview.frame.origin.y < 20 {
                topMessageMaxY = subview.frame.maxY + 16
                break
            }
        }

        let newMessageHeight = outerContainer.frame.height + 16
        for subview in timelineContainer.subviews {
            if subview.frame.origin.y >= topMessageMaxY {
                subview.frame.origin.y += newMessageHeight
            }
        }

        outerContainer.frame.origin.y = topMessageMaxY
        timelineContainer.addSubview(outerContainer)

        updateTimelineHeight()
        scrollView?.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// Update the streaming message with new content (with live formatting)
    func updateStreamingMessage(_ content: String) {
        guard let textView = currentTextView,
              let container = currentContainer,
              let timelineContainer = timelineContainer else { return }

        if !content.isEmpty && textView.isHidden {
            if let spinner = container.subviews.first(where: { $0.identifier?.rawValue == "streamingSpinner" }) as? NSProgressIndicator {
                spinner.stopAnimation(nil)
                spinner.isHidden = true
            }
            if let loadingLabel = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLoadingLabel" }) {
                loadingLabel.isHidden = true
            }
            textView.isHidden = false
        }

        let formattedContent = messageViewFactory.formatMessageContent(content, isQuestion: false)
        let mutableContent = NSMutableAttributedString(attributedString: formattedContent)

        // Teal blinking cursor
        let cursorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.messageAnswer
        ]
        mutableContent.append(NSAttributedString(string: " ▌", attributes: cursorAttrs))

        textView.textStorage?.setAttributedString(mutableContent)

        let width = container.frame.width - 40
        let newTextHeight = max(40, messageViewFactory.estimateTextHeight(content, width: width))
        let newContainerHeight = newTextHeight + 44

        if newContainerHeight > container.frame.height {
            let heightDiff = newContainerHeight - container.frame.height

            container.frame.size.height = newContainerHeight
            textView.frame.size.height = newTextHeight

            if let outerContainer = container.superview, outerContainer.identifier?.rawValue == "streamingOuter" {
                outerContainer.frame.size.height = newContainerHeight

                if let badge = outerContainer.subviews.first(where: { $0.identifier?.rawValue == "streamingBadge" }) {
                    badge.frame.origin.y = newContainerHeight - 30
                }
            }

            if let lineView = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLine" }) {
                lineView.frame.size.height = newContainerHeight
            }

            for subview in container.subviews {
                let isHeaderElement = subview is NSTextField || subview is NSImageView ||
                                      subview.identifier?.rawValue == "streamingTopicPill"
                if isHeaderElement {
                    if subview.identifier?.rawValue != "streamingText" &&
                       subview.identifier?.rawValue != "streamingSpinner" &&
                       subview.identifier?.rawValue != "streamingLoadingLabel" {
                        subview.frame.origin.y = newContainerHeight - 24
                    }
                }
            }

            let outerContainer = container.superview ?? container
            for subview in timelineContainer.subviews where subview != outerContainer {
                if subview.frame.origin.y > 30 {
                    subview.frame.origin.y += heightDiff
                }
            }

            updateTimelineHeight()
        }
    }

    /// Update the status label while searching/processing
    func updateStreamingStatus(_ status: String) {
        guard let container = currentContainer else { return }

        if let loadingLabel = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLoadingLabel" }) as? NSTextField {
            loadingLabel.stringValue = status
        }
    }

    /// Finalize streaming message with proper formatting
    func finalizeStreamingMessage(_ content: String) {
        guard let textView = currentTextView,
              let container = currentContainer,
              let timelineContainer = timelineContainer else { return }

        // Remove streaming animations
        container.layer?.removeAnimation(forKey: "streamingBorderPulse")

        // Fade out glow
        let glowOut = CABasicAnimation(keyPath: "shadowOpacity")
        glowOut.fromValue = 0.12
        glowOut.toValue = 0.0
        glowOut.duration = 0.3
        glowOut.fillMode = .forwards
        glowOut.isRemovedOnCompletion = false
        container.layer?.add(glowOut, forKey: "streamingGlowOut")

        // Settle border to static
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        // Stop accent bar pulse and badge pulse
        for subview in container.subviews {
            subview.layer?.removeAnimation(forKey: "streamingPulse")
        }
        if let outerContainer = container.superview {
            for subview in outerContainer.subviews {
                subview.layer?.removeAnimation(forKey: "streamingBadgePulse")
            }
        }

        // Apply formatted text
        let attributedContent = messageViewFactory.formatMessageContent(content, isQuestion: false)
        textView.textStorage?.setAttributedString(attributedContent)

        let width = container.frame.width - 40
        let newTextHeight = messageViewFactory.estimateTextHeight(content, width: width)
        let newContainerHeight = newTextHeight + 44

        let heightDiff = newContainerHeight - container.frame.height

        container.frame.size.height = newContainerHeight
        textView.frame.size.height = newTextHeight

        if let lineView = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLine" }) {
            lineView.frame.size.height = newContainerHeight
        }

        for subview in container.subviews {
            if subview is NSTextField && subview != textView {
                subview.frame.origin.y = newContainerHeight - 22
            }
        }

        if heightDiff > 0 {
            let outerContainer = container.superview ?? container
            for subview in timelineContainer.subviews where subview != outerContainer && subview != container {
                if subview.frame.origin.y > 30 {
                    subview.frame.origin.y += heightDiff
                }
            }
        }

        updateTimelineHeight()

        if var messages = delegate?.voiceMessages, !messages.isEmpty {
            let lastIndex = messages.count - 1
            let lastMessage = messages[lastIndex]
            messages[lastIndex] = ConversationMessage(type: lastMessage.type, content: content, topic: lastMessage.topic)
            delegate?.voiceMessages = messages
            delegate?.updateFloatingQA()
        }

        currentTextView = nil
        currentContainer = nil
    }

    /// Clear the current streaming state without finalizing
    func clearStreamingState() {
        currentTextView = nil
        currentContainer = nil
    }

    // MARK: - Private Helpers

    private func updateTimelineHeight() {
        guard let timelineContainer = timelineContainer else { return }

        var maxY: CGFloat = 0
        for subview in timelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        timelineContainer.frame.size.height = max(scrollView?.frame.height ?? 0, maxY + 20)
    }
}
