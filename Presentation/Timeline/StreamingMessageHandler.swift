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

        // Layout: A badge indented 20px, card after badge
        let badgeWidth: CGFloat = 22
        let badgeGap: CGFloat = 8
        let answerIndent: CGFloat = 20
        let badgeX: CGFloat = answerIndent
        let cardX: CGFloat = badgeX + badgeWidth + badgeGap
        let cardWidth = timelineContainer.frame.width - 40 - cardX
        let initialHeight: CGFloat = 80

        // Outer container for badge + card
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: timelineContainer.frame.width - 40, height: initialHeight))
        outerContainer.identifier = NSUserInterfaceItemIdentifier("streamingOuter")

        // A Badge
        let badge = NSView(frame: NSRect(x: badgeX, y: initialHeight - 26, width: badgeWidth, height: badgeWidth))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.appleGreen.withAlphaComponent(0.15).cgColor
        badge.layer?.cornerRadius = badgeWidth / 2
        badge.identifier = NSUserInterfaceItemIdentifier("streamingBadge")

        let badgeLabel = NSTextField(labelWithString: "A")
        badgeLabel.frame = NSRect(x: 0, y: 3, width: badgeWidth, height: 16)
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = NSColor.appleGreen
        badgeLabel.alignment = .center
        badge.addSubview(badgeLabel)
        outerContainer.addSubview(badge)

        // Card container
        let container = NSView(frame: NSRect(x: cardX, y: 0, width: cardWidth, height: initialHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        // No background - clean look
        container.identifier = NSUserInterfaceItemIdentifier("streamingContainer")

        // Green accent bar on left
        let lineView = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: initialHeight))
        lineView.wantsLayer = true
        lineView.layer?.backgroundColor = NSColor.appleGreen.cgColor
        lineView.layer?.cornerRadius = 1.5
        lineView.identifier = NSUserInterfaceItemIdentifier("streamingLine")
        container.addSubview(lineView)

        // SF Symbol icon
        if let symbolImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
            let iconView = NSImageView(frame: NSRect(x: 12, y: initialHeight - 22, width: 16, height: 16))
            iconView.image = symbolImage
            iconView.contentTintColor = NSColor.appleGreen
            iconView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(iconView)
        }

        // Latency label (if available)
        if let latencyDisplay = message.displayLatency {
            let latencyLabel = NSTextField(labelWithString: "⚡\(latencyDisplay)")
            latencyLabel.frame = NSRect(x: cardWidth - 145, y: initialHeight - 22, width: 55, height: 16)
            latencyLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            latencyLabel.textColor = NSColor.systemCyan.withAlphaComponent(0.8)
            latencyLabel.alignment = .right
            latencyLabel.identifier = NSUserInterfaceItemIdentifier("streamingLatencyLabel")
            container.addSubview(latencyLabel)
        }

        // Time label
        let timeLabel = NSTextField(labelWithString: message.displayTime)
        timeLabel.frame = NSRect(x: cardWidth - 80, y: initialHeight - 22, width: 70, height: 16)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        // Topic badge
        if let topic = topic, topic != "followUp" && topic != "answer" && topic != "unknown" {
            let topicPill = NSView(frame: NSRect(x: 32, y: initialHeight - 22, width: 0, height: 18))
            topicPill.wantsLayer = true
            topicPill.layer?.backgroundColor = NSColor.appleGreen.withAlphaComponent(0.15).cgColor
            topicPill.layer?.cornerRadius = 9
            topicPill.identifier = NSUserInterfaceItemIdentifier("streamingTopicPill")

            let topicLabel = NSTextField(labelWithString: topic.lowercased())
            topicLabel.font = .systemFont(ofSize: 10, weight: .medium)
            topicLabel.textColor = NSColor.appleGreen
            topicLabel.sizeToFit()

            topicPill.frame.size.width = topicLabel.frame.width + 16
            topicLabel.frame.origin = NSPoint(x: 8, y: 2)
            topicPill.addSubview(topicLabel)
            container.addSubview(topicPill)
        }

        // Loading spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: 15, y: initialHeight / 2 - 20, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.identifier = NSUserInterfaceItemIdentifier("streamingSpinner")
        container.addSubview(spinner)

        // Loading label next to spinner
        let loadingLabel = NSTextField(labelWithString: "Generating answer...")
        loadingLabel.frame = NSRect(x: 42, y: initialHeight / 2 - 18, width: 150, height: 16)
        loadingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        loadingLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        loadingLabel.identifier = NSUserInterfaceItemIdentifier("streamingLoadingLabel")
        container.addSubview(loadingLabel)

        // Streaming text view (hidden initially)
        let textView = NSTextView(frame: NSRect(x: 12, y: 10, width: cardWidth - 24, height: initialHeight - 40))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .white
        textView.string = ""
        textView.isHidden = true
        textView.identifier = NSUserInterfaceItemIdentifier("streamingText")
        container.addSubview(textView)

        outerContainer.addSubview(container)

        currentTextView = textView
        currentContainer = container

        // Streaming answers appear below the question (which is at top)
        var topMessageMaxY: CGFloat = 10
        for subview in timelineContainer.subviews {
            if subview.frame.origin.y < 20 {  // Find question at top
                topMessageMaxY = subview.frame.maxY + 15
                break
            }
        }

        // Push messages below the answer position
        let newMessageHeight = outerContainer.frame.height + 15
        for subview in timelineContainer.subviews {
            if subview.frame.origin.y >= topMessageMaxY {
                subview.frame.origin.y += newMessageHeight
            }
        }

        outerContainer.frame.origin.y = topMessageMaxY
        timelineContainer.addSubview(outerContainer)

        // Update container height
        updateTimelineHeight()

        // Scroll to top to show newest
        scrollView?.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// Update the streaming message with new content (with live formatting)
    func updateStreamingMessage(_ content: String) {
        guard let textView = currentTextView,
              let container = currentContainer,
              let timelineContainer = timelineContainer else { return }

        // Hide spinner and loading label, show text view when content starts
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

        // Apply formatting in real-time
        let formattedContent = messageViewFactory.formatMessageContent(content, isQuestion: false)
        let mutableContent = NSMutableAttributedString(attributedString: formattedContent)

        // Add blinking cursor
        let cursorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.appleGreen
        ]
        mutableContent.append(NSAttributedString(string: " ▌", attributes: cursorAttrs))

        textView.textStorage?.setAttributedString(mutableContent)

        // Dynamically resize container as content grows
        let width = container.frame.width - 30
        let newTextHeight = max(40, messageViewFactory.estimateTextHeight(content, width: width))
        let newContainerHeight = newTextHeight + 40

        if newContainerHeight > container.frame.height {
            let heightDiff = newContainerHeight - container.frame.height

            // Update container and text view
            container.frame.size.height = newContainerHeight
            textView.frame.size.height = newTextHeight

            // Update outer container if exists
            if let outerContainer = container.superview, outerContainer.identifier?.rawValue == "streamingOuter" {
                outerContainer.frame.size.height = newContainerHeight

                // Update badge position
                if let badge = outerContainer.subviews.first(where: { $0.identifier?.rawValue == "streamingBadge" }) {
                    badge.frame.origin.y = newContainerHeight - 26
                }
            }

            // Update line height
            if let lineView = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLine" }) {
                lineView.frame.size.height = newContainerHeight
            }

            // Update icon, labels, and topic pill position
            for subview in container.subviews {
                let isHeaderElement = subview is NSTextField || subview is NSImageView ||
                                      subview.identifier?.rawValue == "streamingTopicPill"
                if isHeaderElement {
                    if subview.identifier?.rawValue != "streamingText" &&
                       subview.identifier?.rawValue != "streamingSpinner" &&
                       subview.identifier?.rawValue != "streamingLoadingLabel" {
                        subview.frame.origin.y = newContainerHeight - 22
                    }
                }
            }

            // Push only messages BELOW the answer - skip the question at top (y < 30)
            let outerContainer = container.superview ?? container
            for subview in timelineContainer.subviews where subview != outerContainer {
                // Don't push the question (which sits at y ≈ 10)
                if subview.frame.origin.y > 30 {
                    subview.frame.origin.y += heightDiff
                }
            }

            // Update total container height
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

        // Apply formatted text
        let attributedContent = messageViewFactory.formatMessageContent(content, isQuestion: false)
        textView.textStorage?.setAttributedString(attributedContent)

        // Recalculate height
        let width = container.frame.width - 30
        let newTextHeight = messageViewFactory.estimateTextHeight(content, width: width)
        let newContainerHeight = newTextHeight + 40

        // Calculate height difference
        let heightDiff = newContainerHeight - container.frame.height

        // Update container and children
        container.frame.size.height = newContainerHeight
        textView.frame.size.height = newTextHeight

        // Update line height
        if let lineView = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLine" }) {
            lineView.frame.size.height = newContainerHeight
        }

        // Update time label position
        for subview in container.subviews {
            if subview is NSTextField && subview != textView {
                subview.frame.origin.y = newContainerHeight - 20
            }
        }

        // Push only messages BELOW the answer if height changed - skip question at top
        if heightDiff > 0 {
            let outerContainer = container.superview ?? container
            for subview in timelineContainer.subviews where subview != outerContainer && subview != container {
                // Don't push the question (which sits at y ≈ 10)
                if subview.frame.origin.y > 30 {
                    subview.frame.origin.y += heightDiff
                }
            }
        }

        // Update container height
        updateTimelineHeight()

        // Update the last message in voiceMessages with final content
        if var messages = delegate?.voiceMessages, !messages.isEmpty {
            let lastIndex = messages.count - 1
            let lastMessage = messages[lastIndex]
            messages[lastIndex] = ConversationMessage(type: lastMessage.type, content: content, topic: lastMessage.topic)
            delegate?.voiceMessages = messages

            // Update floating window Q&A
            delegate?.updateFloatingQA()
        }

        // Clear streaming state
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
