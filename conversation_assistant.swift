import Cocoa
import Carbon
import ScreenCaptureKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Apple HIG Colors
extension NSColor {
    /// Apple HIG Green (52, 199, 89)
    static let appleGreen = NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0)
    /// Apple HIG Red (255, 59, 48)
    static let appleRed = NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    /// Apple HIG Purple (175, 82, 222)
    static let applePurple = NSColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1.0)
    /// Apple Gold (255, 214, 0) - matches our active tab color
    static let appleGold = NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)

    /// Claude brand colors - warm coral/terracotta gradient
    static let claudeCoral = NSColor(red: 0.85, green: 0.467, blue: 0.341, alpha: 1.0)      // #D97757
    static let claudeOrange = NSColor(red: 0.914, green: 0.545, blue: 0.396, alpha: 1.0)    // #E98B65
    static let claudePeach = NSColor(red: 0.957, green: 0.643, blue: 0.525, alpha: 1.0)     // #F4A486
    static let claudeSand = NSColor(red: 0.878, green: 0.698, blue: 0.565, alpha: 1.0)      // #E0B290
}

// MARK: - NSBezierPath CGPath Extension
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}

// MARK: - Design Helpers
extension NSView {
    /// Add subtle drop shadow to view
    func addDropShadow(opacity: Float = 0.3, radius: CGFloat = 8, offset: CGSize = CGSize(width: 0, height: -2)) {
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = opacity
        layer?.shadowRadius = radius
        layer?.shadowOffset = offset
        layer?.masksToBounds = false
    }

    /// Add glassmorphism effect (frosted glass)
    func addGlassEffect() {
        wantsLayer = true
        if let visualEffectView = self as? NSVisualEffectView {
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
        }
    }
}

extension NSButton {
    /// Add hover effect tracking
    func addHoverEffect() {
        wantsLayer = true
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: ["hoverButton": true]
        )
        addTrackingArea(trackingArea)
    }
}

/// Claude Code ASCII logo using block characters
class ClaudeLogoView: NSView {
    private var label: NSTextField!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLogo()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLogo()
    }

    private func setupLogo() {
        wantsLayer = true

        // Claude Code logo using Unicode block characters
        let logoText = "▐▛███▜▌\n▝▜█████▛▘\n ▘▘ ▝▝"

        label = NSTextField(labelWithString: logoText)
        label.font = NSFont.monospacedSystemFont(ofSize: 6, weight: .regular)
        label.textColor = NSColor.claudeCoral
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byClipping
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    func setColor(_ color: NSColor) {
        label.textColor = color
    }

    func setAlpha(_ alpha: CGFloat) {
        label.alphaValue = alpha
    }
}

/// Custom view that captures scroll events for its child scroll view
class ScrollCaptureView: NSView {
    var scrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to the embedded scroll view
        if let scrollView = scrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Ensure this view blocks events from passing through to views behind it
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        // Check subviews first (including scroll view)
        if let hit = super.hitTest(point) {
            return hit
        }
        // If no subview handles it, this view handles it (blocks pass-through)
        return self
    }
}

// MARK: - Hover Button

/// Custom button with hover and press state animations
@available(macOS 14.0, *)
class HoverButton: NSButton {
    var normalBackgroundColor: NSColor = .clear
    var hoverBackgroundColor: NSColor = .clear
    var pressBackgroundColor: NSColor = .clear
    var normalBorderColor: NSColor = .clear
    var hoverBorderColor: NSColor = .clear

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        animateToHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        animateToNormalState()
    }

    override func mouseDown(with event: NSEvent) {
        animateToPressState()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isHovered {
            animateToHoverState()
        } else {
            animateToNormalState()
        }
        super.mouseUp(with: event)
    }

    private func animateToHoverState() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().layer?.backgroundColor = hoverBackgroundColor.cgColor
            self.animator().layer?.borderColor = hoverBorderColor.cgColor
            self.animator().layer?.transform = CATransform3DMakeScale(1.02, 1.02, 1.0)
        }
    }

    private func animateToNormalState() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().layer?.backgroundColor = normalBackgroundColor.cgColor
            self.animator().layer?.borderColor = normalBorderColor.cgColor
            self.animator().layer?.transform = CATransform3DIdentity
        }
    }

    private func animateToPressState() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().layer?.backgroundColor = pressBackgroundColor.cgColor
            self.animator().layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1.0)
        }
    }

    func configureHoverColors(accent: NSColor) {
        normalBackgroundColor = accent.withAlphaComponent(0.15)
        hoverBackgroundColor = accent.withAlphaComponent(0.25)
        pressBackgroundColor = accent.withAlphaComponent(0.35)
        normalBorderColor = accent.withAlphaComponent(0.3)
        hoverBorderColor = accent.withAlphaComponent(0.5)

        layer?.backgroundColor = normalBackgroundColor.cgColor
        layer?.borderColor = normalBorderColor.cgColor
    }
}

// MARK: - Connection Button

/// Stylized button for OAuth connection indicators (Confluence, Jira, GitHub)
@available(macOS 14.0, *)
class ConnectionButton: NSButton {
    var isConnected = false {
        didSet { updateVisualState() }
    }

    var accentColor: NSColor = .systemBlue
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    // Subviews
    private let iconView = NSImageView()
    private let statusDot = NSView()
    private let labelView = NSTextField(labelWithString: "")
    private let gradientLayer = CAGradientLayer()

    // Colors
    private let connectedColor = NSColor(red: 0.2, green: 0.84, blue: 0.45, alpha: 1.0) // Green
    private let disconnectedColor = NSColor.white.withAlphaComponent(0.35) // Grey

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        title = ""
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true

        // Glass morphism effect
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.0
        layer?.masksToBounds = false

        // Subtle shadow for depth
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        layer?.shadowRadius = 3

        // Gradient background layer
        gradientLayer.cornerRadius = 12
        gradientLayer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.insertSublayer(gradientLayer, at: 0)

        // Icon
        iconView.frame = NSRect(x: 10, y: 6, width: 14, height: 14)
        iconView.contentTintColor = .white.withAlphaComponent(0.9)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        addSubview(iconView)

        // Status dot
        statusDot.frame = NSRect(x: 26, y: 10, width: 6, height: 6)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        addSubview(statusDot)

        // Label
        labelView.frame = NSRect(x: 36, y: 5, width: 60, height: 16)
        labelView.font = .systemFont(ofSize: 11, weight: .semibold)
        labelView.textColor = .white.withAlphaComponent(0.95)
        addSubview(labelView)

        updateVisualState()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    func configure(icon: String, label: String, accent: NSColor) {
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        labelView.stringValue = label
        accentColor = accent

        // Auto-size based on label width
        labelView.sizeToFit()
        let labelWidth = labelView.frame.width
        let newWidth = 10 + 14 + 4 + 6 + 4 + labelWidth + 12  // icon padding + icon + gap + dot + gap + label + end padding
        frame.size.width = newWidth
        labelView.frame = NSRect(x: 36, y: 5, width: labelWidth, height: 16)

        updateVisualState()
    }

    private func updateVisualState() {
        gradientLayer.frame = bounds

        if isConnected {
            // Connected state - green
            let baseColor = connectedColor

            if isHovered {
                gradientLayer.colors = [
                    baseColor.withAlphaComponent(0.3).cgColor,
                    baseColor.withAlphaComponent(0.15).cgColor
                ]
            } else {
                gradientLayer.colors = [
                    baseColor.withAlphaComponent(0.15).cgColor,
                    baseColor.withAlphaComponent(0.08).cgColor
                ]
            }

            layer?.borderColor = baseColor.withAlphaComponent(isHovered ? 0.5 : 0.3).cgColor
            statusDot.layer?.backgroundColor = baseColor.cgColor
            iconView.contentTintColor = baseColor.blended(withFraction: 0.3, of: .white)
            labelView.textColor = .white
        } else {
            // Disconnected state - red dot
            if isHovered {
                gradientLayer.colors = [
                    accentColor.withAlphaComponent(0.2).cgColor,
                    accentColor.withAlphaComponent(0.1).cgColor
                ]
                layer?.borderColor = accentColor.withAlphaComponent(0.4).cgColor
                iconView.contentTintColor = accentColor.blended(withFraction: 0.5, of: .white)
            } else {
                gradientLayer.colors = [
                    NSColor.white.withAlphaComponent(0.08).cgColor,
                    NSColor.white.withAlphaComponent(0.04).cgColor
                ]
                layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
                iconView.contentTintColor = .white.withAlphaComponent(0.7)
            }

            statusDot.layer?.backgroundColor = disconnectedColor.cgColor
            labelView.textColor = .white.withAlphaComponent(isHovered ? 1.0 : 0.8)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // Use .activeAlways to ensure tracking works even when window isn't key
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().layer?.transform = CATransform3DMakeScale(1.03, 1.03, 1.0)
        }
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().layer?.transform = CATransform3DIdentity
        }
        updateVisualState()
    }

    override func mouseDown(with event: NSEvent) {
        print("[ConnectionButton] mouseDown on '\(labelView.stringValue)'")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            self.animator().layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1.0)
            self.animator().alphaValue = 0.8
        }
    }

    override func mouseUp(with event: NSEvent) {
        print("[ConnectionButton] mouseUp on '\(labelView.stringValue)'")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().layer?.transform = isHovered ? CATransform3DMakeScale(1.03, 1.03, 1.0) : CATransform3DIdentity
            self.animator().alphaValue = 1.0
        }

        // Use hit testing as reliable check (works even if tracking area didn't fire)
        let locationInView = convert(event.locationInWindow, from: nil)
        let isMouseInBounds = bounds.contains(locationInView)

        print("[ConnectionButton] isHovered=\(isHovered), isMouseInBounds=\(isMouseInBounds), target=\(target != nil), action=\(action != nil)")

        // Send action if mouse is still over the button (use hit test OR isHovered)
        if (isMouseInBounds || isHovered), let target = target, let action = action {
            print("[ConnectionButton] Sending action for '\(labelView.stringValue)'")
            _ = target.perform(action, with: self)
        } else {
            print("[ConnectionButton] NOT sending action - conditions not met")
        }
    }
}

@available(macOS 14.0, *)
class ConversationAssistantDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var textView: NSTextView!
    var statusLabel: NSTextField!
    var floatingButton: NSButton!
    var autoHideButton: NSButton!
    var isFloating = true
    var autoHideEnabled = false
    var eventMonitor: Any?
    var visualEffectView: NSVisualEffectView!

    // Tab system
    var currentTab: Tab = .voice
    var notesTabButton: NSButton!
    var codingTabButton: NSButton!
    var voiceTabButton: NSButton!
    var tabContainer: NSVisualEffectView!
    var tabSelectionPill: NSView!  // iOS-style morphing selection pill
    
    // Recording indicator (Dynamic Island style)
    var recordingPill: NSView!
    var recordingDot: NSView!
    var recordingTimeLabel: NSTextField!
    var recordingStartTime: Date?
    var recordingTimer: Timer?
    
    // Bottom status bar
    var statusBar: NSView!
    var anthropicStatusDot: NSView!
    var groqStatusDot: NSView!
    var confluenceStatusDot: NSView!
    var jiraStatusDot: NSView!
    var githubStatusDot: NSView!
    var toolsContainer: NSStackView!  // Container for tool indicators

    // Clickable indicator buttons for data sources (OAuth connections)
    var confluenceButton: ConnectionButton!
    var jiraButton: ConnectionButton!
    var githubButton: ConnectionButton!
    var notesContentView: NSView!
    var codingContentView: NSView!
    var voiceContentView: NSView!

    // Voice tab - Conversation assistant
    var voiceTimelineScrollView: NSScrollView!
    var voiceTimelineContainer: NSView!
    var voiceStatusLabel: NSTextField!
    var systemWaveformBars: [NSView] = []   // Gold waveform - system audio (speaker)
    var systemIndicatorLabel: NSTextField!
    var voiceToggleButton: HoverButton!
    var languageDropdown: NSPopUpButton!
    var techStackDropdown: NSPopUpButton!
    var voiceMessages: [ConversationMessage] = []
    var typingDotsView: NSView!
    var typingDots: [CALayer] = []

    // Pill-style button
    var nestButtonContainer: NSView!
    var nestButtonInner: CALayer!
    var nestIconView: NSImageView!

    // Voice Bar - expandable pill with waveform (matching reference design)
    var voiceBarContainer: NSView!
    var voiceBarInner: CALayer!
    var voiceBarMicButton: NSView!           // Left: mic for push-to-talk
    var voiceBarMicIcon: NSImageView!
    var voiceBarMicClickArea: HoverButton!
    var voiceBarSendButton: NSView!          // Right: stop button
    var voiceBarSendIcon: NSImageView!
    var voiceBarSendClickArea: HoverButton!
    var voiceBarWaveformBars: [NSView] = []  // Center: 25 waveform bars
    var voiceBarLabel: NSTextField!
    var isVoiceBarExpanded = false
    let voiceBarCollapsedWidth: CGFloat = 120
    let voiceBarExpandedWidth: CGFloat = 320

    // Prompt input field (pill-styled text input at bottom)
    var promptInputContainer: NSView!
    var promptInputField: NSTextField!
    var promptSendButton: HoverButton!
    var promptSendIcon: NSImageView!
    var isPromptProcessing = false

    // Direct question mic button (Ask button)
    var askButtonContainer: NSView!
    var askButtonInner: CALayer!
    var askIconView: NSImageView!
    var askButton: HoverButton!
    var isAskingDirectQuestion = false
    var directQuestionRecorder: VADAudioRecorder?

    // Pinned coding task solution
    var pinnedSolutionContainer: ScrollCaptureView!
    var pinnedSolutionTextView: NSTextView!
    var pinnedSolutionScrollView: NSScrollView!
    var currentPinnedSolution: String?

    // Floating solution window (when main app is hidden)
    var floatingSolutionWindow: NSWindow?
    var floatingSolutionTextView: NSTextView?
    var floatingSolutionScrollView: NSScrollView?
    var floatingQAContainer: NSView?
    var floatingLoadingView: NSView?
    var floatingEventMonitor: Any?

    var vadRecorder: VADAudioRecorder?
    var systemAudioCapture: SystemAudioCapture?
    var groqClient: GroqSpeechClient?
    var conversationContext = ConversationContext()
    var chatHistory = ChatHistory(maxMessages: 20)  // Multi-turn conversation history
    var isSessionActive = false
    var groqApiKey: String? {
        return ApiKeyManager.shared.getKey(.groq)
    }

    // Voice processing state
    var utteranceBuffer: String = ""
    var bufferTimestamp: Date?
    let bufferTimeout: TimeInterval = 10.0
    var lastAnswerTime: Date?
    let answerCooldown: TimeInterval = 12.0

    // Deduplication - prevent same audio from being processed twice
    // (mic picking up speaker audio = room echo)
    var recentTranscriptions: [(text: String, timestamp: Date, source: AudioSource)] = []
    let dedupeWindow: TimeInterval = 5.0  // Wider window for room echo
    let similarityThreshold: Double = 0.5  // Lower threshold to catch more duplicates

    // Search
    var searchField: NSTextField!
    var searchContainer: NSVisualEffectView!
    var searchResultsLabel: NSTextField!
    var isSearchVisible = false

    // Formatting toolbar
    var formattingToolbar: NSVisualEffectView!
    var isFormattingToolbarVisible = false

    // Rendering debounce
    var renderTimer: Timer?
    var lastTextLength: Int = 0

    // Coding tab - Screenshot thumbnails
    var screenshotThumbnails: [NSButton] = []
    var screenshotThumbnailsContainer: NSView!
    var screenshots: [Screenshot] = []

    // Coding tab - Analysis
    var analysisTextView: NSTextView!
    var analyzeButton: HoverButton!
    var clearButton: HoverButton!

    // Analysis mode (smart - auto-detects content type)
    var analysisMode: AnalysisMode = .smart

    // API Key storage - managed by ApiKeyManager
    var apiKey: String? {
        return ApiKeyManager.shared.getKey(.anthropic)
    }
    var openAIApiKey: String?

    // Infrastructure services
    var screenCaptureService: ScreenCaptureService
    var anthropicClient: AnthropicClient?
    var openAIClient: OpenAIClient?

    // Presentation components
    var notesMarkdownRenderer: MarkdownRenderer
    var analysisMarkdownRenderer: MarkdownRenderer
    var syntaxHighlighter: SyntaxHighlighter
    var alertWindowManager: ScreenshotAlertWindow

    // Screenshot alert
    var alertWindow: NSWindow?
    var settingsWindowController: SettingsWindowController?

    // Onboarding windows
    var permissionsOnboardingWindow: PermissionsOnboardingWindow?
    var atlassianOnboardingWindow: AtlassianOnboardingWindow?
    var alertThumbnailsContainer: NSView?
    var screenshotMonitorTimer: Timer?
    var lastScreenshotCount = 0

    // Permissions panel
    var permissionsPanel: NSView?
    var screenRecordingStatusLabel: NSTextField!
    var permissionCheckTimer: Timer?

    // Persistence
    let notesStorageKey = "ConversationAssistant.SavedNotes"
    let dataConsentKey = "ConversationAssistant.DataConsentGiven"

    override init() {
        self.screenCaptureService = ScreenCaptureService()
        self.notesMarkdownRenderer = MarkdownRenderer(style: .notes)
        self.analysisMarkdownRenderer = MarkdownRenderer(style: .analysis)
        self.syntaxHighlighter = SyntaxHighlighter(fontSize: 12)
        self.alertWindowManager = ScreenshotAlertWindow()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupStatusItem()
        setupWindow()
        setupUI()
        setupHotkey()
        startScreenShareMonitoring()
        startScreenshotMonitoring()
        registerURLHandler()

        // Listen for API key updates from Settings
        NotificationCenter.default.addObserver(
            forName: .apiKeysUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApiKeysUpdated()
        }

        // Listen for data source updates (OAuth connections, etc.)
        NotificationCenter.default.addObserver(
            forName: .dataSourcesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarIndicators()
        }

        // Listen for OAuth completion
        NotificationCenter.default.addObserver(
            forName: .oauthCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarIndicators()
        }
    }

    private func registerURLHandler() {
        // Register for URL scheme callbacks (needed for OAuth)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        NSLog("App: Received URL event: \(url)")

        if url.scheme == OAuthConfig.urlScheme {
            OAuthManager.shared.handleCallback(url)

            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func handleApiKeysUpdated() {
        // Show confirmation that keys were updated
        let hasAnthropic = ApiKeyManager.shared.hasKey(.anthropic)
        let hasGroq = ApiKeyManager.shared.hasKey(.groq)
        
        var message = "API keys updated:\n"
        message += "• Anthropic: \(hasAnthropic ? "✓ Configured" : "Not set")\n"
        message += "• Groq: \(hasGroq ? "✓ Configured" : "Not set")"
        
        // Update status label if visible
        if !voiceContentView.isHidden {
            voiceStatusLabel.stringValue = hasGroq ? "✓ Groq API ready" : "⚠️ Groq API key needed"
        }
    }

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        appMenu.addItem(withTitle: "About Conversation Assistant", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = appMenu.addItem(withTitle: "Hide Conversation Assistant", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Conversation Assistant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        fileMenu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n")
        fileMenu.addItem(NSMenuItem.separator())
        let captureItem = fileMenu.addItem(withTitle: "Capture Screenshot", action: #selector(captureScreenshotPlaceholder), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Export Notes...", action: #selector(exportNotes), keyEquivalent: "e")

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let findItem = editMenu.addItem(withTitle: "Find...", action: #selector(toggleSearch), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = [.command]

        // View menu
        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        viewMenu.addItem(withTitle: "Context", action: #selector(switchToNotesTab), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Timeline", action: #selector(switchToVoiceTab), keyEquivalent: "2")
        viewMenu.addItem(NSMenuItem.separator())
        let toggleItem = viewMenu.addItem(withTitle: "Toggle Window", action: #selector(toggleWindowVisibility), keyEquivalent: "b")
        toggleItem.keyEquivalentModifierMask = [.command]
        let hideSolutionItem = viewMenu.addItem(withTitle: "Hide Floating Solution", action: #selector(hideFloatingSolution), keyEquivalent: "\\")
        hideSolutionItem.keyEquivalentModifierMask = [.command]

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        helpMenu.addItem(withTitle: "Conversation Assistant Help", action: #selector(showHelp), keyEquivalent: "?")
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(withTitle: "Keyboard Shortcuts", action: #selector(showKeyboardShortcuts), keyEquivalent: "")
        helpMenu.addItem(withTitle: "Privacy Policy", action: #selector(showPrivacyPolicy), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
        NSApp.windowsMenu = windowMenu
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Use SF Symbol for the icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Conversation Assistant") {
                let symbolImage = image.withSymbolConfiguration(config)
                button.image = symbolImage
            }
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        // Create status item menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Window", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func statusItemClicked() {
        showMainWindow()
    }

    @objc func showMainWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Conversation Assistant"
        alert.informativeText = "Version 1.0.0\n\nAI-powered conversation assistant with knowledge base integration.\n\nCapture coding problems and get instant analysis with Claude AI.\n\n© 2024 Nikolay Prosenikov"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Privacy Policy")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            showPrivacyPolicy()
        }
    }

    @objc func showPrivacyPolicy() {
        // Privacy Policy URL - required for App Store (Guideline 5.1.1)
        if let url = URL(string: "https://github.com/nikolayprosenikov/conversation-assistant/blob/main/PRIVACY.md") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func newNote() {
        switchToNotesTab()
        textView.string = "# New Note\n\n"
        renderMarkdown()
        saveNotes()
    }

    @objc func exportNotes() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .plainText]
        savePanel.nameFieldStringValue = "session-notes.md"
        savePanel.title = "Export Notes"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try textView.string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showAlert(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    @objc func showHelp() {
        if let url = URL(string: "https://github.com/nikolayprosenikov/conversation-assistant") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = """
        Global (work from any app):
        ⌘B          Toggle window visibility
        ⌘S          Capture screenshot
        ⌘↩          Analyze screenshots

        Navigation:
        ⌘1          Context tab
        ⌘2          Timeline tab

        Editing:
        ⌘F          Find in notes
        ⌘G          Clear screenshots
        ⌘,          Settings

        Window:
        ⌘←↑↓→       Move window
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }


    func setupWindow() {
        window = WindowFactory.createMainWindow()

        // Show in dock
        NSApp.setActivationPolicy(.regular)

        // Check if onboarding needed
        if !PermissionChecker.hasCompletedOnboarding() {
            // Show permissions onboarding first
            showPermissionsOnboarding()
        } else if AtlassianOnboardingWindow.shouldShow() {
            // Permissions done, but Atlassian not connected - show that
            showAtlassianOnboarding()
        } else {
            // All onboarding complete - show main window
            showMainWindowAfterOnboarding()
        }
    }

    private func showPermissionsOnboarding() {
        permissionsOnboardingWindow = PermissionsOnboardingWindow { [weak self] in
            // Permissions granted - check if Atlassian onboarding needed
            if AtlassianOnboardingWindow.shouldShow() {
                self?.showAtlassianOnboarding()
            } else {
                self?.showMainWindowAfterOnboarding()
            }
        }
        permissionsOnboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAtlassianOnboarding() {
        atlassianOnboardingWindow = AtlassianOnboardingWindow { [weak self] in
            self?.showMainWindowAfterOnboarding()
        }
        atlassianOnboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindowAfterOnboarding() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupUI() {
        guard let contentView = window.contentView else { return }

        // ⭐ GLASS BACKGROUND (NSVisualEffectView) - visionOS style (balanced)
        visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .menu  // Balanced material - transparent but readable
        visualEffectView.alphaValue = 0.8  // More opaque for blur effect
        contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)

        // Top bar with frosted glass - visionOS style (balanced)
        let topBar = NSVisualEffectView(frame: NSRect(x: 0, y: contentView.frame.height - 35, width: contentView.frame.width, height: 35))
        topBar.autoresizingMask = [.width, .minYMargin]
        topBar.blendingMode = .withinWindow
        topBar.material = .menu  // Balanced - transparent but readable
        topBar.state = .active
        topBar.alphaValue = 0.7  // More opaque for blur effect
        topBar.wantsLayer = true
        topBar.layer?.cornerRadius = 16
        topBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        topBar.layer?.borderWidth = 1.0
        topBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        contentView.addSubview(topBar)

        // Shortcuts display (centered at top) - same style as hint label
        let shortcutsLabel = NSTextField(frame: NSRect(x: 20, y: contentView.frame.height - 28, width: contentView.frame.width - 40, height: 20))
        shortcutsLabel.stringValue = "⌘B Hide  •  ⌘1 Context  •  ⌘2 Timeline  •  ⌘S Screenshot  •  ⌘↩ Analyze"
        shortcutsLabel.isEditable = false
        shortcutsLabel.isBordered = false
        shortcutsLabel.backgroundColor = .clear
        shortcutsLabel.textColor = NSColor(white: 1.0, alpha: 1.0)
        shortcutsLabel.font = .systemFont(ofSize: 13, weight: .semibold)  // Semibold like hint
        shortcutsLabel.alignment = .center
        shortcutsLabel.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(shortcutsLabel)

        // Tab bar
        let tabBar = NSView(frame: NSRect(x: 20, y: contentView.frame.height - 90, width: contentView.frame.width - 40, height: 44))
        tabBar.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(tabBar)

        // Tab switcher container - iOS-style segmented control with morphing pill
        let tabContainerWidth: CGFloat = 240
        tabContainer = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: tabContainerWidth, height: 36))
        tabContainer.blendingMode = .withinWindow
        tabContainer.material = .menu
        tabContainer.state = .active
        tabContainer.wantsLayer = true
        tabContainer.layer?.cornerRadius = 10
        tabContainer.layer?.borderWidth = 1
        tabContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        tabBar.addSubview(tabContainer)

        // Calculate button widths
        let tabPadding: CGFloat = 3
        let tabButtonWidth = (tabContainerWidth - tabPadding * 2) / 2

        // Selection pill (slides behind selected tab) - iOS style, starts on Timeline
        tabSelectionPill = NSView(frame: NSRect(x: tabPadding + tabButtonWidth, y: 3, width: tabButtonWidth, height: 30))
        tabSelectionPill.wantsLayer = true
        tabSelectionPill.layer?.cornerRadius = 8
        tabSelectionPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        // Subtle inner glow
        tabSelectionPill.layer?.shadowColor = NSColor.white.cgColor
        tabSelectionPill.layer?.shadowOpacity = 0.1
        tabSelectionPill.layer?.shadowRadius = 4
        tabSelectionPill.layer?.shadowOffset = .zero
        tabContainer.addSubview(tabSelectionPill)

        // Context tab button - Clean, no background (pill provides it)
        notesTabButton = NSButton(frame: NSRect(x: tabPadding, y: 3, width: tabButtonWidth, height: 30))
        notesTabButton.title = "Context"
        notesTabButton.image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: "Context")
        notesTabButton.imagePosition = .imageLeading
        notesTabButton.imageHugsTitle = true
        notesTabButton.bezelStyle = .rounded
        notesTabButton.isBordered = false
        notesTabButton.font = .systemFont(ofSize: 13, weight: .semibold)
        notesTabButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        notesTabButton.target = self
        notesTabButton.action = #selector(switchToNotesTab)
        notesTabButton.wantsLayer = true
        notesTabButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)  // Dimmed, Timeline is default
        notesTabButton.layer?.backgroundColor = NSColor.clear.cgColor
        tabContainer.addSubview(notesTabButton)

        // Coding tab button - HIDDEN
        codingTabButton = NSButton(frame: .zero)
        codingTabButton.isHidden = true

        // Timeline tab button
        voiceTabButton = NSButton(frame: NSRect(x: tabPadding + tabButtonWidth, y: 3, width: tabButtonWidth, height: 30))
        voiceTabButton.title = "Timeline"
        voiceTabButton.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Timeline")
        voiceTabButton.imagePosition = .imageLeading
        voiceTabButton.imageHugsTitle = true
        voiceTabButton.bezelStyle = .rounded
        voiceTabButton.isBordered = false
        voiceTabButton.font = .systemFont(ofSize: 13, weight: .semibold)
        voiceTabButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        voiceTabButton.target = self
        voiceTabButton.action = #selector(switchToVoiceTab)
        voiceTabButton.wantsLayer = true
        voiceTabButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        voiceTabButton.layer?.backgroundColor = NSColor.clear.cgColor
        tabContainer.addSubview(voiceTabButton)
        
        // Recording pill (Dynamic Island style) - hidden by default
        recordingPill = NSView(frame: NSRect(x: tabContainerWidth + 20, y: 4, width: 28, height: 28))
        recordingPill.wantsLayer = true
        recordingPill.layer?.cornerRadius = 14
        recordingPill.layer?.backgroundColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9).cgColor
        recordingPill.alphaValue = 0
        recordingPill.isHidden = true
        tabBar.addSubview(recordingPill)
        
        // Recording dot inside pill
        recordingDot = NSView(frame: NSRect(x: 10, y: 10, width: 8, height: 8))
        recordingDot.wantsLayer = true
        recordingDot.layer?.cornerRadius = 4
        recordingDot.layer?.backgroundColor = NSColor.white.cgColor
        recordingPill.addSubview(recordingDot)
        
        // Recording time label (shown when pill expands)
        recordingTimeLabel = NSTextField(labelWithString: "00:00")
        recordingTimeLabel.frame = NSRect(x: 24, y: 6, width: 50, height: 16)
        recordingTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        recordingTimeLabel.textColor = .white
        recordingTimeLabel.alphaValue = 0
        recordingPill.addSubview(recordingTimeLabel)

        // Language dropdown - iOS 26 style (in header)
        languageDropdown = NSPopUpButton(frame: NSRect(x: tabBar.frame.width - 240, y: 5, width: 105, height: 28), pullsDown: false)
        languageDropdown.autoresizingMask = [.minXMargin]
        languageDropdown.removeAllItems()
        for lang in AppLanguage.allCases {
            languageDropdown.addItem(withTitle: lang.displayName)
        }
        if let index = AppLanguage.allCases.firstIndex(of: AppSettings.shared.language) {
            languageDropdown.selectItem(at: index)
        }
        languageDropdown.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        languageDropdown.target = self
        languageDropdown.action = #selector(languageChanged(_:))
        languageDropdown.wantsLayer = true
        languageDropdown.layer?.cornerRadius = 8
        languageDropdown.isBordered = false
        languageDropdown.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        (languageDropdown.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        tabBar.addSubview(languageDropdown)

        // Tech Stack dropdown - iOS 26 style (in header)
        techStackDropdown = NSPopUpButton(frame: NSRect(x: tabBar.frame.width - 130, y: 5, width: 125, height: 28), pullsDown: false)
        techStackDropdown.autoresizingMask = [.minXMargin]
        techStackDropdown.removeAllItems()
        for stack in TechStack.allCases {
            techStackDropdown.addItem(withTitle: stack.displayName)
        }
        if let index = TechStack.allCases.firstIndex(of: AppSettings.shared.techStack) {
            techStackDropdown.selectItem(at: index)
        }
        techStackDropdown.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        techStackDropdown.target = self
        techStackDropdown.action = #selector(techStackChanged(_:))
        techStackDropdown.wantsLayer = true
        techStackDropdown.layer?.cornerRadius = 8
        techStackDropdown.isBordered = false
        techStackDropdown.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        (techStackDropdown.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        tabBar.addSubview(techStackDropdown)

        // Main content area with glass - visionOS style (balanced) - BACKGROUND ONLY
        let contentPanel = NSVisualEffectView(frame: NSRect(x: 20, y: 70, width: contentView.frame.width - 40, height: contentView.frame.height - 185))
        contentPanel.autoresizingMask = [.width, .height]
        contentPanel.blendingMode = .withinWindow
        contentPanel.material = .menu  // Balanced - transparent but readable
        contentPanel.state = .active
        contentPanel.alphaValue = 0.65  // More opaque for blur effect
        contentPanel.wantsLayer = true
        contentPanel.layer?.cornerRadius = 16
        contentPanel.layer?.masksToBounds = true
        contentPanel.layer?.borderWidth = 1
        contentPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        contentView.addSubview(contentPanel)

        // Notes content view - ON TOP of glass, not inside!
        notesContentView = NSView(frame: NSRect(x: 20, y: 70, width: contentView.frame.width - 40, height: contentView.frame.height - 185))
        notesContentView.autoresizingMask = [.width, .height]
        notesContentView.isHidden = true  // Start with Timeline tab visible
        contentView.addSubview(notesContentView)  // Add to contentView, NOT contentPanel!

        // Text editor for notes
        let scrollView = NSScrollView(frame: NSRect(x: 15, y: 15, width: notesContentView.frame.width - 30, height: notesContentView.frame.height - 30))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor(white: 1.0, alpha: 1.0)  // Pure white
        textView.insertionPointColor = NSColor(white: 1.0, alpha: 1.0)
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)  // Regular weight
        textView.isRichText = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // Disable automatic text replacements and corrections
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        // Load saved notes or use default text
        if let savedNotes = UserDefaults.standard.string(forKey: notesStorageKey), !savedNotes.isEmpty {
            textView.string = savedNotes
        } else {
            textView.string = """
# Quick Reference

## JavaScript/TypeScript

**Q: What is the difference between `let`, `const`, and `var`?**
A: `var` is function-scoped, `let` and `const` are block-scoped. `const` cannot be reassigned.

**Q: Explain closures**
A: Functions that have access to variables from outer scope even after outer function has returned.

**Q: What is event delegation?**
A: Technique of handling events at parent level using event bubbling instead of adding listeners to each child.

## System Design

**Q: Design a URL shortener**
- Hash function (MD5/Base62)
- Database: key-value store (Redis)
- Cache layer
- Load balancer
- Analytics tracking

**Q: Design Twitter feed**
- Fan-out on write vs read
- Timeline service
- Caching strategy
- Pagination

## React

**Q: useEffect vs useLayoutEffect?**
A: useEffect runs after paint, useLayoutEffect runs synchronously before paint.

**Q: What are React keys?**
A: Unique identifiers to help React identify which items changed/added/removed in lists.

---

## Code Example

Here's a sample Python function:

```python
def two_sum(nums, target):
    # Hash map to store value -> index
    seen = {}
    for i, num in enumerate(nums):
        complement = target - num
        if complement in seen:
            return [seen[complement], i]
        seen[num] = i
    return []
```

The function uses a **hash map** for `O(n)` time complexity.

---

**Add your own notes below...**
"""
        }

        scrollView.documentView = textView
        notesContentView.addSubview(scrollView)

        // Formatting toolbar - visionOS style (floating)
        setupFormattingToolbar(in: notesContentView)

        // Voice search feature removed - not working correctly

        // Coding content view - ON TOP of glass, not inside!
        codingContentView = NSView(frame: NSRect(x: 20, y: 70, width: contentView.frame.width - 40, height: contentView.frame.height - 185))
        codingContentView.autoresizingMask = [.width, .height]
        codingContentView.isHidden = true  // Start with notes tab visible
        contentView.addSubview(codingContentView)  // Add to contentView, NOT contentPanel!

        // Screenshot thumbnails bar (top) - visionOS style
        let thumbnailBar = NSVisualEffectView(frame: NSRect(x: 15, y: codingContentView.frame.height - 65, width: codingContentView.frame.width - 30, height: 50))
        thumbnailBar.autoresizingMask = [.width, .minYMargin]
        thumbnailBar.blendingMode = .withinWindow
        thumbnailBar.material = .menu
        thumbnailBar.state = .active
        thumbnailBar.alphaValue = 1.0
        thumbnailBar.wantsLayer = true
        thumbnailBar.layer?.cornerRadius = 12
        thumbnailBar.layer?.borderWidth = 1.0
        thumbnailBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        codingContentView.addSubview(thumbnailBar)

        // Scroll view for thumbnails - starts after capture button
        let thumbnailScrollView = NSScrollView(frame: NSRect(x: 160, y: 7.5, width: thumbnailBar.frame.width - 175, height: 35))
        thumbnailScrollView.autoresizingMask = [.width]
        thumbnailScrollView.hasHorizontalScroller = true
        thumbnailScrollView.hasVerticalScroller = false
        thumbnailScrollView.borderType = .noBorder
        thumbnailScrollView.drawsBackground = false
        thumbnailScrollView.backgroundColor = .clear

        screenshotThumbnailsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 35))
        thumbnailScrollView.documentView = screenshotThumbnailsContainer
        thumbnailBar.addSubview(thumbnailScrollView)

        // Capture button with SF Symbol - rectangular style matching tab buttons
        let captureBtn = NSButton(frame: NSRect(x: 15, y: 10, width: 130, height: 30))
        captureBtn.title = " Capture ⇧⌘S"
        captureBtn.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Capture")
        captureBtn.imagePosition = .imageLeading
        captureBtn.imageHugsTitle = true
        captureBtn.bezelStyle = .rounded
        captureBtn.isBordered = false
        captureBtn.font = .systemFont(ofSize: 13, weight: .bold)
        captureBtn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        captureBtn.target = self
        captureBtn.action = #selector(captureScreenshotPlaceholder)
        captureBtn.wantsLayer = true
        captureBtn.layer?.cornerRadius = 8
        captureBtn.layer?.backgroundColor = NSColor.applePurple.withAlphaComponent(0.2).cgColor
        captureBtn.layer?.borderWidth = 1.5
        captureBtn.layer?.borderColor = NSColor.applePurple.withAlphaComponent(0.4).cgColor
        captureBtn.contentTintColor = NSColor.applePurple
        thumbnailBar.addSubview(captureBtn)

        // Analysis results area
        let analysisScrollView = NSScrollView(frame: NSRect(x: 15, y: 55, width: codingContentView.frame.width - 30, height: codingContentView.frame.height - 175))
        analysisScrollView.autoresizingMask = [.width, .height]
        analysisScrollView.hasVerticalScroller = true
        analysisScrollView.borderType = .noBorder
        analysisScrollView.drawsBackground = false
        analysisScrollView.backgroundColor = .clear

        analysisTextView = NSTextView(frame: analysisScrollView.bounds)
        analysisTextView.autoresizingMask = [.width, .height]
        analysisTextView.drawsBackground = false
        analysisTextView.backgroundColor = .clear
        analysisTextView.textColor = NSColor(white: 1.0, alpha: 1.0)
        analysisTextView.insertionPointColor = NSColor(white: 1.0, alpha: 1.0)
        analysisTextView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        analysisTextView.isEditable = false
        analysisTextView.textContainerInset = NSSize(width: 15, height: 15)
        analysisTextView.string = "💻 AI Analysis will appear here\n\nCapture screenshots (⌘S) and press Analyze (⌘Enter)"

        analysisScrollView.documentView = analysisTextView
        codingContentView.addSubview(analysisScrollView)

        // Permissions panel (shown when permissions are missing)
        setupPermissionsPanel(in: codingContentView)

        // Action buttons at bottom - equal sizes and spacing
        let buttonY: CGFloat = 15
        let buttonWidth: CGFloat = 140
        let buttonHeight: CGFloat = 30
        let buttonSpacing: CGFloat = 10
        let startX: CGFloat = 15

        // Analyze button with SF Symbol
        analyzeButton = HoverButton(frame: NSRect(x: startX, y: buttonY, width: buttonWidth, height: buttonHeight))
        analyzeButton.title = " Analyze ⌘↩"
        analyzeButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Analyze")
        analyzeButton.imagePosition = .imageLeading
        analyzeButton.imageHugsTitle = true
        analyzeButton.bezelStyle = .rounded
        analyzeButton.isBordered = false
        analyzeButton.font = .systemFont(ofSize: 13, weight: .bold)
        analyzeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        analyzeButton.target = self
        analyzeButton.action = #selector(analyzeScreenshots)
        analyzeButton.wantsLayer = true
        analyzeButton.layer?.cornerRadius = 8
        analyzeButton.layer?.borderWidth = 1.5
        analyzeButton.contentTintColor = .appleGreen
        analyzeButton.configureHoverColors(accent: .appleGreen)
        codingContentView.addSubview(analyzeButton)

        // Clear button with SF Symbol
        clearButton = HoverButton(frame: NSRect(x: startX + buttonWidth + buttonSpacing, y: buttonY, width: buttonWidth, height: buttonHeight))
        clearButton.title = " Clear All ⌘G"
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear All")
        clearButton.imagePosition = .imageLeading
        clearButton.imageHugsTitle = true
        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 13, weight: .bold)
        clearButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        clearButton.target = self
        clearButton.action = #selector(clearAllScreenshots)
        clearButton.keyEquivalent = "g"
        clearButton.keyEquivalentModifierMask = [.command]
        clearButton.wantsLayer = true
        clearButton.layer?.cornerRadius = 8
        clearButton.layer?.borderWidth = 1.5
        clearButton.contentTintColor = .appleRed
        clearButton.configureHoverColors(accent: .appleRed)
        codingContentView.addSubview(clearButton)

        // === VOICE TAB CONTENT ===
        voiceContentView = NSView(frame: NSRect(x: 20, y: 70, width: contentView.frame.width - 40, height: contentView.frame.height - 185))
        voiceContentView.autoresizingMask = [.width, .height]
        voiceContentView.wantsLayer = true
        voiceContentView.layer?.cornerRadius = 16
        voiceContentView.layer?.masksToBounds = true
        voiceContentView.isHidden = false  // Start with Timeline tab visible
        contentView.addSubview(voiceContentView)

        // Voice control bar at top - transparent floating container
        let voiceControlBar = NSView(frame: NSRect(x: 15, y: voiceContentView.frame.height - 70, width: voiceContentView.frame.width - 30, height: 55))
        voiceControlBar.autoresizingMask = [.width, .minYMargin]
        voiceControlBar.wantsLayer = true
        voiceContentView.addSubview(voiceControlBar)

        // === SINGLE EXPANDABLE VOICE BAR (Reference Design) ===
        // Collapsed: Waveform icon + "Start" text
        // Expanded: [Mic button] [Waveform Bars] [Stop button]
        let vbHeight: CGFloat = 44
        let vbY: CGFloat = (55 - vbHeight) / 2
        let vbRadius: CGFloat = vbHeight / 2

        // Main container - will animate width on expand/collapse
        voiceBarContainer = NSView(frame: NSRect(x: 5, y: vbY, width: voiceBarCollapsedWidth, height: vbHeight))
        voiceBarContainer.wantsLayer = true
        voiceControlBar.addSubview(voiceBarContainer)

        // Pill background layer
        voiceBarInner = CALayer()
        voiceBarInner.frame = CGRect(x: 0, y: 0, width: voiceBarCollapsedWidth, height: vbHeight)
        voiceBarInner.cornerRadius = vbRadius
        voiceBarInner.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        voiceBarInner.borderWidth = 1
        voiceBarInner.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        voiceBarContainer.layer?.addSublayer(voiceBarInner)

        // === COLLAPSED STATE: Icon + "Start" label ===
        let collapsedIconSize: CGFloat = 18
        let collapsedIconX: CGFloat = 16
        nestIconView = NSImageView(frame: NSRect(x: collapsedIconX, y: (vbHeight - collapsedIconSize) / 2, width: collapsedIconSize, height: collapsedIconSize))
        nestIconView.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Voice")
        nestIconView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        nestIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        voiceBarContainer.addSubview(nestIconView)

        voiceBarLabel = NSTextField(labelWithString: "Start")
        voiceBarLabel.frame = NSRect(x: collapsedIconX + collapsedIconSize + 8, y: (vbHeight - 18) / 2, width: 60, height: 18)
        voiceBarLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        voiceBarLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        voiceBarLabel.identifier = NSUserInterfaceItemIdentifier("nestStartLabel")
        voiceBarContainer.addSubview(voiceBarLabel)

        // Main click area (covers whole pill in collapsed state)
        voiceToggleButton = HoverButton(frame: NSRect(x: 5, y: vbY, width: voiceBarCollapsedWidth, height: vbHeight))
        voiceToggleButton.title = ""
        voiceToggleButton.isBordered = false
        voiceToggleButton.target = self
        voiceToggleButton.action = #selector(toggleListening)
        voiceToggleButton.wantsLayer = true
        voiceToggleButton.layer?.backgroundColor = NSColor.clear.cgColor
        voiceControlBar.addSubview(voiceToggleButton)

        // === EXPANDED STATE ELEMENTS (hidden initially) ===
        // Left: Mic button for push-to-talk
        let micBtnSize: CGFloat = 32
        let micBtnX: CGFloat = 6
        let micBtnY: CGFloat = (vbHeight - micBtnSize) / 2

        voiceBarMicButton = NSView(frame: NSRect(x: micBtnX, y: micBtnY, width: micBtnSize, height: micBtnSize))
        voiceBarMicButton.wantsLayer = true
        voiceBarMicButton.layer?.cornerRadius = micBtnSize / 2
        voiceBarMicButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        voiceBarMicButton.alphaValue = 0
        voiceBarContainer.addSubview(voiceBarMicButton)

        let micIconSize: CGFloat = 16
        voiceBarMicIcon = NSImageView(frame: NSRect(x: (micBtnSize - micIconSize) / 2, y: (micBtnSize - micIconSize) / 2, width: micIconSize, height: micIconSize))
        voiceBarMicIcon.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Push to talk")
        voiceBarMicIcon.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        voiceBarMicIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        voiceBarMicButton.addSubview(voiceBarMicIcon)

        voiceBarMicClickArea = HoverButton(frame: NSRect(x: micBtnX, y: micBtnY, width: micBtnSize, height: micBtnSize))
        voiceBarMicClickArea.title = ""
        voiceBarMicClickArea.isBordered = false
        voiceBarMicClickArea.target = self
        voiceBarMicClickArea.action = #selector(toggleDirectQuestion)
        voiceBarMicClickArea.wantsLayer = true
        voiceBarMicClickArea.layer?.cornerRadius = micBtnSize / 2
        voiceBarMicClickArea.toolTip = "Push to talk"
        voiceBarMicClickArea.alphaValue = 0
        voiceBarContainer.addSubview(voiceBarMicClickArea)

        // Right: Stop button
        let stopBtnSize: CGFloat = 32
        let stopBtnX: CGFloat = voiceBarExpandedWidth - stopBtnSize - 6
        let stopBtnY: CGFloat = (vbHeight - stopBtnSize) / 2

        voiceBarSendButton = NSView(frame: NSRect(x: stopBtnX, y: stopBtnY, width: stopBtnSize, height: stopBtnSize))
        voiceBarSendButton.wantsLayer = true
        voiceBarSendButton.layer?.cornerRadius = stopBtnSize / 2
        voiceBarSendButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        voiceBarSendButton.alphaValue = 0
        voiceBarContainer.addSubview(voiceBarSendButton)

        let stopIconSize: CGFloat = 12
        voiceBarSendIcon = NSImageView(frame: NSRect(x: (stopBtnSize - stopIconSize) / 2, y: (stopBtnSize - stopIconSize) / 2, width: stopIconSize, height: stopIconSize))
        voiceBarSendIcon.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        voiceBarSendIcon.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        voiceBarSendIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        voiceBarSendButton.addSubview(voiceBarSendIcon)

        voiceBarSendClickArea = HoverButton(frame: NSRect(x: stopBtnX, y: stopBtnY, width: stopBtnSize, height: stopBtnSize))
        voiceBarSendClickArea.title = ""
        voiceBarSendClickArea.isBordered = false
        voiceBarSendClickArea.target = self
        voiceBarSendClickArea.action = #selector(toggleListening)
        voiceBarSendClickArea.wantsLayer = true
        voiceBarSendClickArea.layer?.cornerRadius = stopBtnSize / 2
        voiceBarSendClickArea.toolTip = "Stop"
        voiceBarSendClickArea.alphaValue = 0
        voiceBarContainer.addSubview(voiceBarSendClickArea)

        // === WAVEFORM BARS (centered between mic and stop buttons) ===
        let waveformBarCount = 25
        let waveformBarWidth: CGFloat = 3
        let waveformBarSpacing: CGFloat = 3
        let waveformMaxHeight: CGFloat = 22
        let waveformMinHeight: CGFloat = 4
        // Calculate symmetric spacing: center waveform between mic button and stop button
        let waveformTotalWidth = CGFloat(waveformBarCount) * waveformBarWidth + CGFloat(waveformBarCount - 1) * waveformBarSpacing
        let micButtonEnd = micBtnX + micBtnSize  // 6 + 32 = 38
        let stopButtonStart = stopBtnX          // 282
        let availableSpace = stopButtonStart - micButtonEnd  // Space between buttons
        let symmetricGap = (availableSpace - waveformTotalWidth) / 2
        let waveformStartX: CGFloat = micButtonEnd + symmetricGap
        let waveformCenterY: CGFloat = vbHeight / 2

        voiceBarWaveformBars = []
        for i in 0..<waveformBarCount {
            let normalizedPos = abs(CGFloat(i) - CGFloat(waveformBarCount) / 2) / (CGFloat(waveformBarCount) / 2)
            let initialMultiplier = 0.3 + 0.5 * (1 - normalizedPos)
            let barHeight = waveformMinHeight + (waveformMaxHeight - waveformMinHeight) * initialMultiplier

            let bar = NSView(frame: NSRect(
                x: waveformStartX + CGFloat(i) * (waveformBarWidth + waveformBarSpacing),
                y: waveformCenterY - barHeight / 2,
                width: waveformBarWidth,
                height: barHeight
            ))
            bar.wantsLayer = true
            bar.layer?.cornerRadius = waveformBarWidth / 2
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
            bar.alphaValue = 0
            voiceBarContainer.addSubview(bar)
            voiceBarWaveformBars.append(bar)
        }

        // Legacy compatibility references
        nestButtonContainer = voiceBarContainer
        nestButtonInner = voiceBarInner
        askButtonContainer = voiceBarMicButton
        askButtonInner = voiceBarMicButton.layer!
        askIconView = voiceBarMicIcon
        askButton = voiceBarMicClickArea

        // Export button - pill style matching Start button
        let exportWidth: CGFloat = 95
        let exportHeight: CGFloat = 36
        let exportX = voiceControlBar.frame.width - exportWidth - 10

        let exportContainer = NSView(frame: NSRect(x: exportX, y: (55 - exportHeight) / 2, width: exportWidth, height: exportHeight))
        exportContainer.autoresizingMask = [.minXMargin]
        exportContainer.wantsLayer = true
        exportContainer.layer?.cornerRadius = exportHeight / 2
        exportContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        exportContainer.layer?.borderWidth = 1
        exportContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        voiceControlBar.addSubview(exportContainer)

        // Export icon + text centered
        let expIconSize: CGFloat = 13
        let expGap: CGFloat = 6
        let expTextWidth: CGFloat = 45
        let expContentWidth = expIconSize + expGap + expTextWidth
        let expContentX = (exportWidth - expContentWidth) / 2

        let exportIcon = NSImageView(frame: NSRect(x: expContentX, y: (exportHeight - expIconSize) / 2, width: expIconSize, height: expIconSize))
        exportIcon.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")
        exportIcon.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        exportIcon.imageScaling = .scaleProportionallyUpOrDown
        exportContainer.addSubview(exportIcon)

        let exportLabel = NSTextField(labelWithString: "Export")
        exportLabel.frame = NSRect(x: expContentX + expIconSize + expGap, y: (exportHeight - 16) / 2, width: expTextWidth, height: 16)
        exportLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        exportLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        exportContainer.addSubview(exportLabel)

        // Invisible button for click handling
        let exportButton = HoverButton(frame: NSRect(x: exportX, y: (55 - exportHeight) / 2, width: exportWidth, height: exportHeight))
        exportButton.autoresizingMask = [.minXMargin]
        exportButton.title = ""
        exportButton.isBordered = false
        exportButton.bezelStyle = .regularSquare
        exportButton.target = self
        exportButton.action = #selector(exportSession)
        exportButton.wantsLayer = true
        exportButton.layer?.backgroundColor = NSColor.clear.cgColor
        voiceControlBar.addSubview(exportButton)

        // System waveform bars now integrated into voice bar
        // Use the voice bar waveform bars as the primary audio visualization
        systemWaveformBars = voiceBarWaveformBars

        // Hidden label for compatibility
        systemIndicatorLabel = NSTextField(labelWithString: "")
        systemIndicatorLabel.isHidden = true
        voiceControlBar.addSubview(systemIndicatorLabel)


        // Hidden status label (used for status updates internally)
        voiceStatusLabel = NSTextField(labelWithString: "")
        voiceStatusLabel.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        voiceStatusLabel.isHidden = true
        voiceControlBar.addSubview(voiceStatusLabel)

        // Typing dots - iMessage style loading indicator
        let dotSize: CGFloat = 8
        let dotSpacing: CGFloat = 6
        let totalWidth = dotSize * 3 + dotSpacing * 2
        let dotsX = (voiceControlBar.frame.width - totalWidth) / 2
        typingDotsView = NSView(frame: NSRect(x: dotsX, y: (55 - dotSize) / 2, width: totalWidth, height: dotSize))
        typingDotsView.autoresizingMask = [.minXMargin, .maxXMargin]
        typingDotsView.wantsLayer = true
        typingDotsView.isHidden = true
        voiceControlBar.addSubview(typingDotsView)

        // Create three dots
        typingDots = []
        for i in 0..<3 {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * (dotSize + dotSpacing), y: 0, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = NSColor.appleGreen.cgColor
            typingDotsView.layer?.addSublayer(dot)
            typingDots.append(dot)
        }

        // Pinned solution container (hidden by default, shows at top-right half of screen)
        // NOTE: Added AFTER timeline scroll view so it's on top in z-order
        let halfWidth = voiceContentView.frame.width / 2
        pinnedSolutionContainer = ScrollCaptureView(frame: NSRect(x: halfWidth, y: voiceContentView.frame.height - 65, width: halfWidth - 15, height: 0))
        pinnedSolutionContainer.autoresizingMask = [.minXMargin, .minYMargin]  // Stay anchored to right
        pinnedSolutionContainer.wantsLayer = true
        pinnedSolutionContainer.layer?.cornerRadius = 10
        pinnedSolutionContainer.layer?.masksToBounds = true
        pinnedSolutionContainer.layer?.borderWidth = 1
        pinnedSolutionContainer.layer?.borderColor = NSColor.applePurple.withAlphaComponent(0.5).cgColor
        pinnedSolutionContainer.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1.0).cgColor
        pinnedSolutionContainer.isHidden = true
        // Don't add to superview yet - will add after timeline so it's on top

        // Pinned solution header
        let pinnedHeader = NSTextField(labelWithString: "CODING TASK")
        pinnedHeader.frame = NSRect(x: 10, y: 0, width: 150, height: 20)
        pinnedHeader.font = .systemFont(ofSize: 11, weight: .bold)
        pinnedHeader.textColor = NSColor.applePurple
        pinnedHeader.tag = 100  // Tag to find and reposition later
        pinnedSolutionContainer.addSubview(pinnedHeader)

        // Pinned solution scroll view with text view (using standard scrollable setup)
        pinnedSolutionScrollView = NSTextView.scrollableTextView()
        pinnedSolutionScrollView.frame = NSRect(x: 5, y: 5, width: pinnedSolutionContainer.frame.width - 10, height: 0)
        pinnedSolutionScrollView.autoresizingMask = [.width, .height]
        pinnedSolutionScrollView.hasVerticalScroller = true
        pinnedSolutionScrollView.hasHorizontalScroller = false
        pinnedSolutionScrollView.borderType = .noBorder
        pinnedSolutionScrollView.drawsBackground = false
        pinnedSolutionScrollView.backgroundColor = .clear
        pinnedSolutionContainer.addSubview(pinnedSolutionScrollView)
        pinnedSolutionContainer.scrollView = pinnedSolutionScrollView  // Link for scroll capture

        // Get the text view from scrollable container
        pinnedSolutionTextView = pinnedSolutionScrollView.documentView as! NSTextView
        pinnedSolutionTextView.isEditable = false
        pinnedSolutionTextView.isSelectable = true
        pinnedSolutionTextView.drawsBackground = false
        pinnedSolutionTextView.backgroundColor = .clear
        pinnedSolutionTextView.textContainerInset = NSSize(width: 5, height: 5)
        pinnedSolutionTextView.font = .systemFont(ofSize: 12)
        pinnedSolutionTextView.textColor = .white

        // Configure text view for proper scrolling
        pinnedSolutionTextView.isVerticallyResizable = true
        pinnedSolutionTextView.isHorizontallyResizable = false
        pinnedSolutionTextView.autoresizingMask = [.width]
        pinnedSolutionTextView.minSize = NSSize(width: 0, height: 0)
        pinnedSolutionTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        pinnedSolutionTextView.textContainer?.widthTracksTextView = true
        pinnedSolutionTextView.textContainer?.heightTracksTextView = false
        pinnedSolutionTextView.textContainer?.containerSize = NSSize(width: pinnedSolutionScrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        // Ensure scroll view responds to scroll events
        pinnedSolutionScrollView.scrollsDynamically = true

        // === PROMPT INPUT FIELD (pill-styled at bottom) ===
        let promptHeight: CGFloat = 44
        let promptY: CGFloat = 10
        let promptPadding: CGFloat = 15
        
        promptInputContainer = NSView(frame: NSRect(x: promptPadding, y: promptY, width: voiceContentView.frame.width - (promptPadding * 2), height: promptHeight))
        promptInputContainer.autoresizingMask = [.width, .maxYMargin]
        promptInputContainer.wantsLayer = true
        promptInputContainer.layer?.cornerRadius = promptHeight / 2  // Capsule shape
        promptInputContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        promptInputContainer.layer?.borderWidth = 1
        promptInputContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        voiceContentView.addSubview(promptInputContainer)
        
        // Text input field
        let inputLeftPadding: CGFloat = 20
        let sendButtonSize: CGFloat = 32
        let inputRightPadding: CGFloat = 12
        let inputWidth = promptInputContainer.frame.width - inputLeftPadding - sendButtonSize - inputRightPadding - 8
        
        promptInputField = NSTextField(frame: NSRect(x: inputLeftPadding, y: (promptHeight - 24) / 2, width: inputWidth, height: 24))
        promptInputField.autoresizingMask = [.width]
        promptInputField.placeholderString = "Ask Claude anything..."
        promptInputField.font = .systemFont(ofSize: 14, weight: .regular)
        promptInputField.textColor = NSColor.white
        promptInputField.backgroundColor = .clear
        promptInputField.isBordered = false
        promptInputField.focusRingType = .none
        promptInputField.cell?.wraps = false
        promptInputField.cell?.isScrollable = true
        promptInputField.target = self
        promptInputField.action = #selector(sendPromptFromInput)
        promptInputContainer.addSubview(promptInputField)
        
        // Send button (circular, right side)
        let sendBtnX = promptInputContainer.frame.width - sendButtonSize - inputRightPadding
        let sendBtnY = (promptHeight - sendButtonSize) / 2
        
        let sendButtonBg = NSView(frame: NSRect(x: sendBtnX, y: sendBtnY, width: sendButtonSize, height: sendButtonSize))
        sendButtonBg.autoresizingMask = [.minXMargin]
        sendButtonBg.wantsLayer = true
        sendButtonBg.layer?.cornerRadius = sendButtonSize / 2
        sendButtonBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        promptInputContainer.addSubview(sendButtonBg)
        
        let sendIconSize: CGFloat = 14
        promptSendIcon = NSImageView(frame: NSRect(x: (sendButtonSize - sendIconSize) / 2, y: (sendButtonSize - sendIconSize) / 2, width: sendIconSize, height: sendIconSize))
        promptSendIcon.wantsLayer = true
        promptSendIcon.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        promptSendIcon.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        promptSendIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        sendButtonBg.addSubview(promptSendIcon)
        
        promptSendButton = HoverButton(frame: NSRect(x: sendBtnX, y: sendBtnY, width: sendButtonSize, height: sendButtonSize))
        promptSendButton.autoresizingMask = [.minXMargin]
        promptSendButton.title = ""
        promptSendButton.isBordered = false
        promptSendButton.target = self
        promptSendButton.action = #selector(sendPromptFromInput)
        promptSendButton.wantsLayer = true
        promptSendButton.layer?.cornerRadius = sendButtonSize / 2
        promptSendButton.toolTip = "Send message"
        promptInputContainer.addSubview(promptSendButton)

        // Timeline scroll view (positioned above prompt input)
        let timelineY: CGFloat = promptY + promptHeight + 10  // Above the input field
        let timelineHeight = voiceContentView.frame.height - 80 - promptHeight - 10  // Reduced for input field
        voiceTimelineScrollView = NSScrollView(frame: NSRect(x: 15, y: timelineY, width: voiceContentView.frame.width - 30, height: timelineHeight))
        voiceTimelineScrollView.autoresizingMask = [.width, .height]
        voiceTimelineScrollView.hasVerticalScroller = true
        voiceTimelineScrollView.borderType = .noBorder
        voiceTimelineScrollView.drawsBackground = false
        voiceTimelineScrollView.backgroundColor = .clear

        // Timeline container (grows as messages are added)
        voiceTimelineContainer = NSView(frame: NSRect(x: 0, y: 0, width: voiceTimelineScrollView.frame.width, height: 100))
        voiceTimelineContainer.autoresizingMask = [.width]
        voiceTimelineScrollView.documentView = voiceTimelineContainer

        // Empty state / Welcome message with friendly styling
        addVoiceMessage(type: .status, content: "Ready to help\n\nType a message or click Start to begin listening.", topic: nil)

        voiceContentView.addSubview(voiceTimelineScrollView)

        // Add pinned solution container AFTER timeline so it's on top in z-order
        voiceContentView.addSubview(pinnedSolutionContainer)

        // Search bar (hidden by default) - visionOS style
        searchContainer = NSVisualEffectView(frame: NSRect(x: contentView.frame.width / 2 - 200, y: contentView.frame.height - 160, width: 400, height: 50))
        searchContainer.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        searchContainer.blendingMode = .withinWindow
        searchContainer.material = .menu
        searchContainer.state = .active
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 14
        searchContainer.layer?.borderWidth = 1.5
        searchContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        searchContainer.alphaValue = 0
        searchContainer.isHidden = true
        contentView.addSubview(searchContainer)

        // Search field
        searchField = NSTextField(frame: NSRect(x: 15, y: 15, width: 300, height: 24))
        searchField.placeholderString = "Search notes... (e.g., hashmap)"
        searchField.font = .systemFont(ofSize: 13)
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(performSearch)
        searchContainer.addSubview(searchField)

        // Search results label
        searchResultsLabel = NSTextField(frame: NSRect(x: 320, y: 15, width: 70, height: 24))
        searchResultsLabel.stringValue = ""
        searchResultsLabel.isEditable = false
        searchResultsLabel.isBordered = false
        searchResultsLabel.backgroundColor = .clear
        searchResultsLabel.textColor = .appleGreen
        searchResultsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        searchResultsLabel.alignment = .right
        searchContainer.addSubview(searchResultsLabel)

        // Bottom status bar - transparent container for layout only (no background)
        statusBar = NSView(frame: NSRect(x: 20, y: 15, width: contentView.frame.width - 40, height: 28))
        statusBar.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(statusBar)

        // Claude status indicator
        let claudeIcon = NSImageView(frame: NSRect(x: 12, y: 6, width: 14, height: 14))
        claudeIcon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Claude")
        claudeIcon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        claudeIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        statusBar.addSubview(claudeIcon)
        
        anthropicStatusDot = NSView(frame: NSRect(x: 28, y: 10, width: 6, height: 6))
        anthropicStatusDot.wantsLayer = true
        anthropicStatusDot.layer?.cornerRadius = 3
        anthropicStatusDot.layer?.backgroundColor = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0).cgColor
        statusBar.addSubview(anthropicStatusDot)
        
        let claudeLabel = NSTextField(labelWithString: "Claude")
        claudeLabel.frame = NSRect(x: 38, y: 6, width: 45, height: 14)
        claudeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        claudeLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        statusBar.addSubview(claudeLabel)
        
        // Separator
        let sep1 = NSView(frame: NSRect(x: 90, y: 8, width: 1, height: 10))
        sep1.wantsLayer = true
        sep1.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        statusBar.addSubview(sep1)
        
        // Groq status indicator
        let groqIcon = NSImageView(frame: NSRect(x: 100, y: 6, width: 14, height: 14))
        groqIcon.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Groq")
        groqIcon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        groqIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        statusBar.addSubview(groqIcon)
        
        groqStatusDot = NSView(frame: NSRect(x: 116, y: 10, width: 6, height: 6))
        groqStatusDot.wantsLayer = true
        groqStatusDot.layer?.cornerRadius = 3
        groqStatusDot.layer?.backgroundColor = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0).cgColor
        statusBar.addSubview(groqStatusDot)
        
        let groqLabel = NSTextField(labelWithString: "Groq")
        groqLabel.frame = NSRect(x: 126, y: 6, width: 35, height: 14)
        groqLabel.font = .systemFont(ofSize: 10, weight: .medium)
        groqLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        statusBar.addSubview(groqLabel)

        // Tools container (will be populated dynamically for other tools)
        toolsContainer = NSStackView(frame: NSRect(x: 175, y: 4, width: 40, height: 20))
        toolsContainer.orientation = .horizontal
        toolsContainer.spacing = 10
        toolsContainer.alignment = .centerY
        toolsContainer.distribution = .fill
        statusBar.addSubview(toolsContainer)

        // Connection buttons - positioned after Groq with spacing
        let connBtnStart: CGFloat = 180  // Start after Groq label
        let connBtnSpacing: CGFloat = 12
        var currentX = connBtnStart

        // Confluence button
        confluenceButton = ConnectionButton(frame: NSRect(x: currentX, y: 1, width: 100, height: 26))
        confluenceButton.configure(icon: "book.closed.fill", label: "Confluence", accent: .systemBlue)
        confluenceButton.target = self
        confluenceButton.action = #selector(confluenceIndicatorClicked)
        confluenceButton.toolTip = "Click to connect Confluence"
        statusBar.addSubview(confluenceButton)
        currentX += confluenceButton.frame.width + connBtnSpacing

        // Jira button
        jiraButton = ConnectionButton(frame: NSRect(x: currentX, y: 1, width: 60, height: 26))
        jiraButton.configure(icon: "ticket.fill", label: "Jira", accent: .systemBlue)
        jiraButton.target = self
        jiraButton.action = #selector(jiraIndicatorClicked)
        jiraButton.toolTip = "Click to connect Jira"
        statusBar.addSubview(jiraButton)
        currentX += jiraButton.frame.width + connBtnSpacing

        // GitHub button
        githubButton = ConnectionButton(frame: NSRect(x: currentX, y: 1, width: 80, height: 26))
        githubButton.configure(icon: "chevron.left.forwardslash.chevron.right", label: "GitHub", accent: .systemPurple)
        githubButton.target = self
        githubButton.action = #selector(githubIndicatorClicked)
        githubButton.toolTip = "Click to connect GitHub"
        statusBar.addSubview(githubButton)

        // Settings button (far right)
        let settingsBtn = NSButton(frame: NSRect(x: statusBar.frame.width - 36, y: 0, width: 28, height: 28))
        settingsBtn.autoresizingMask = [.minXMargin]
        settingsBtn.title = ""
        settingsBtn.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsBtn.imagePosition = .imageOnly
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        settingsBtn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        settingsBtn.target = self
        settingsBtn.action = #selector(showSettings)
        statusBar.addSubview(settingsBtn)
        
        // Update status indicators based on current API key state
        updateStatusBarIndicators()

        renderMarkdown()
    }

    @objc func toggleFloating() {
        isFloating.toggle()

        if isFloating {
            window.level = .floating
            floatingButton.title = "⬆️ Floating"
            updateStatus()
        } else {
            window.level = .normal
            floatingButton.title = "⬇️ Normal"
            updateStatus()
        }
    }

    @objc func toggleAutoHide() {
        autoHideEnabled.toggle()
        autoHideButton.title = autoHideEnabled ? "Auto-Hide: ON" : "Auto-Hide: OFF"
        updateStatus()
    }

    func updateStatus() {
        var status = "🔒 Hidden"
        status += isFloating ? " • ⬆️ Floating" : " • ⬇️ Normal"
        status += autoHideEnabled ? " • 👁️ Auto-Hide" : ""
        statusLabel.stringValue = status
    }

    func createTabButton(frame: NSRect, title: String, isSelected: Bool) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)  // Semibold for crisp text

        if isSelected {
            // Crisp yellow text (#FFD700)
            button.contentTintColor = .appleGold
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
            button.layer?.cornerRadius = 6
        } else {
            // Pure white for inactive tabs (like other text)
            button.contentTintColor = NSColor(white: 1.0, alpha: 0.8)
        }

        return button
    }

    // MARK: - Apple Watch / visionOS Style Buttons
    func createCircularButton(diameter: CGFloat, icon: String, tintColor: NSColor = .white) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        button.title = icon
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: diameter * 0.4, weight: .medium)
        button.contentTintColor = tintColor
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        button.layer?.cornerRadius = diameter / 2  // Perfect circle
        button.layer?.borderWidth = 1.5
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        // Hover effect
        button.layer?.masksToBounds = true

        return button
    }

    func createCapsuleButton(width: CGFloat, height: CGFloat, title: String, icon: String = "", isSelected: Bool = false) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: height))
        button.title = icon.isEmpty ? title : "\(icon) \(title)"
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = height / 2  // Capsule shape

        if isSelected {
            button.contentTintColor = .appleGold
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            button.layer?.borderWidth = 2.0
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        } else {
            button.contentTintColor = NSColor.white
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            button.layer?.borderWidth = 1.5
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        }

        return button
    }

    func createBorderedCircleButton(diameter: CGFloat, icon: String, isSelected: Bool = false) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        button.title = icon
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: diameter * 0.45, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = diameter / 2

        if isSelected {
            button.contentTintColor = .appleGold
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            button.layer?.borderWidth = 2.5
            button.layer?.borderColor = NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.8).cgColor
        } else {
            button.contentTintColor = NSColor.white
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
            button.layer?.borderWidth = 2.0
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        }

        return button
    }

    @objc func switchToNotesTab() {
        currentTab = .notes
        notesContentView.isHidden = false
        codingContentView.isHidden = true
        voiceContentView.isHidden = true

        // Animate pill to Context tab with spring physics
        animateTabPill(to: notesTabButton)
    }

    @objc func switchToCodingTab() {
        currentTab = .coding
        notesContentView.isHidden = true
        codingContentView.isHidden = false
        voiceContentView.isHidden = true
        hideFormattingToolbar()
    }

    @objc func switchToVoiceTab() {
        currentTab = .voice
        notesContentView.isHidden = true
        codingContentView.isHidden = true
        voiceContentView.isHidden = false
        hideFormattingToolbar()

        // Animate pill to Timeline tab with spring physics
        animateTabPill(to: voiceTabButton)
    }
    
    /// Animate the selection pill to the target tab button with fast spring animation
    private func animateTabPill(to targetButton: NSButton) {
        let targetFrame = NSRect(
            x: targetButton.frame.origin.x,
            y: tabSelectionPill.frame.origin.y,
            width: targetButton.frame.width,
            height: tabSelectionPill.frame.height
        )

        // Fast spring animation using NSAnimationContext
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.tabSelectionPill.animator().frame = targetFrame
        }

        // Update button text colors with fade
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            
            if targetButton === notesTabButton {
                notesTabButton.contentTintColor = .white
                voiceTabButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
            } else {
                voiceTabButton.contentTintColor = .white
                notesTabButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
            }
        })
    }
    
    // MARK: - Recording Indicator (Dynamic Island Style)
    
    /// Show the recording pill with expand animation
    /// NOTE: Disabled - recording time now shown in voice bar
    func showRecordingIndicator() {
        return  // Recording indicator disabled - using voice bar instead
        recordingStartTime = Date()
        recordingPill.isHidden = false

        // Start with small pill
        recordingPill.frame = NSRect(x: recordingPill.frame.origin.x, y: recordingPill.frame.origin.y, width: 28, height: 28)
        recordingPill.layer?.cornerRadius = 14

        // Fade in fast
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            recordingPill.animator().alphaValue = 1.0
        })

        // Expand to show time quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.expandRecordingPill()
        }

        // Start pulsing animation on the dot - faster pulse
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        recordingDot.layer?.add(pulse, forKey: "pulse")

        // Start timer to update time
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRecordingTime()
        }
    }

    /// Expand pill to show recording time
    private func expandRecordingPill() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            recordingPill.frame = NSRect(
                x: recordingPill.frame.origin.x,
                y: recordingPill.frame.origin.y,
                width: 80,
                height: 28
            )
            recordingPill.layer?.cornerRadius = 14
            recordingTimeLabel.animator().alphaValue = 1.0
        })
    }
    
    /// Update the recording time display
    private func updateRecordingTime() {
        guard let startTime = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        recordingTimeLabel.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Hide the recording pill with collapse animation
    func hideRecordingIndicator() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDot.layer?.removeAnimation(forKey: "pulse")

        // Collapse first
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            recordingTimeLabel.animator().alphaValue = 0
            recordingPill.frame = NSRect(
                x: recordingPill.frame.origin.x,
                y: recordingPill.frame.origin.y,
                width: 28,
                height: 28
            )
        }) { [weak self] in
            // Then fade out
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                self?.recordingPill.animator().alphaValue = 0
            }) {
                self?.recordingPill.isHidden = true
            }
        }
    }
    
    // MARK: - Status Bar Updates
    
    /// Update the bottom status bar API indicators
    func updateStatusBarIndicators() {
        let hasAnthropic = ApiKeyManager.shared.hasKey(.anthropic)
        let hasGroq = ApiKeyManager.shared.hasKey(.groq)
        let hasConfluence = ConfluenceClient.shared.isConfigured
        let hasJira = JiraClient.shared.isConfigured
        let hasGitHub = GitHubClient.shared.isConfigured

        let greenColor = NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0).cgColor
        let orangeColor = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0).cgColor

        // Update API status dots (Anthropic, Groq)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            anthropicStatusDot.layer?.backgroundColor = hasAnthropic ? greenColor : orangeColor
            groqStatusDot.layer?.backgroundColor = hasGroq ? greenColor : orangeColor
        })

        // Update connection buttons (Confluence, Jira, GitHub)
        confluenceButton.isConnected = hasConfluence
        jiraButton.isConnected = hasJira
        githubButton.isConnected = hasGitHub

        // Update tooltips based on connection state
        updateToolTips()

        // Update tools container (for other tools like Database, WebSearch - excluding GitHub which has dedicated indicator)
        updateToolsIndicators()
    }

    /// Update the tools section in status bar (for tools other than Confluence/Jira/GitHub which have dedicated indicators)
    func updateToolsIndicators() {
        // Clear existing tool indicators
        toolsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Tool icons mapping
        let toolIcons: [String: String] = [
            "query_database": "cylinder.split.1x2",               // Database
            "web_search": "globe"                                 // Web Search
        ]

        // Tools to show in container (exclude Confluence, Jira, and GitHub which have dedicated indicators)
        let excludedTools = ["search_documentation", "search_jira", "search_codebase"]
        let toolStatus = ToolExecutor.shared.toolStatus
        let configuredTools = toolStatus.filter { $0.isConfigured && !excludedTools.contains($0.name) }

        for tool in configuredTools {
            // Create container for each tool
            let toolView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))

            // Tool icon
            let iconName = toolIcons[tool.name] ?? "wrench"
            let icon = NSImageView(frame: NSRect(x: 0, y: 3, width: 14, height: 14))
            icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: tool.displayName)
            icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            toolView.addSubview(icon)

            // Status dot (green = configured)
            let dot = NSView(frame: NSRect(x: 16, y: 7, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0).cgColor
            toolView.addSubview(dot)

            // Tool label (short name)
            let label = NSTextField(labelWithString: tool.displayName)
            label.frame = NSRect(x: 24, y: 3, width: 60, height: 14)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.6)
            label.lineBreakMode = .byTruncatingTail
            toolView.addSubview(label)

            // Set width based on label
            let labelWidth = label.intrinsicContentSize.width
            toolView.frame.size.width = min(24 + labelWidth, 80)

            toolsContainer.addArrangedSubview(toolView)
        }
    }

    // Voice search feature removed - not working correctly

    @objc func toggleSearch() {
        isSearchVisible.toggle()

        if isSearchVisible {
            // Show search
            searchContainer.isHidden = false
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                searchContainer.animator().alphaValue = 1
            }, completionHandler: {
                self.searchField.becomeFirstResponder()
            })
        } else {
            // Hide search
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                searchContainer.animator().alphaValue = 0
            }, completionHandler: {
                self.searchContainer.isHidden = true
                self.searchField.stringValue = ""
                self.searchResultsLabel.stringValue = ""
                self.clearSearchHighlights()
            })
        }
    }

    @objc func performSearch() {
        let searchTerm = searchField.stringValue.lowercased()
        guard !searchTerm.isEmpty else {
            clearSearchHighlights()
            searchResultsLabel.stringValue = ""
            return
        }

        // Search in notes
        let text = textView.string.lowercased()
        var matchCount = 0
        var searchStartIndex = text.startIndex

        // Count matches
        while let range = text.range(of: searchTerm, range: searchStartIndex..<text.endIndex) {
            matchCount += 1
            searchStartIndex = range.upperBound
        }

        // Update results label
        if matchCount > 0 {
            searchResultsLabel.stringValue = "✓ \(matchCount)"
            searchResultsLabel.textColor = .appleGreen
            highlightSearchResults(searchTerm: searchTerm)
        } else {
            searchResultsLabel.stringValue = "✗ 0"
            searchResultsLabel.textColor = .appleRed
            clearSearchHighlights()
        }
    }

    func highlightSearchResults(searchTerm: String) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        let lowercasedText = text.lowercased()

        clearSearchHighlights()

        var searchStartIndex = lowercasedText.startIndex
        var firstMatchRange: NSRange?

        while let range = lowercasedText.range(of: searchTerm, range: searchStartIndex..<lowercasedText.endIndex) {
            let nsRange = NSRange(range, in: text)

            // Store first match for scrolling
            if firstMatchRange == nil {
                firstMatchRange = nsRange
            }

            storage.addAttributes([
                .backgroundColor: NSColor.appleGold.withAlphaComponent(0.5),
                .foregroundColor: NSColor.black
            ], range: nsRange)
            searchStartIndex = range.upperBound
        }

        // Scroll to first match with a delay to ensure rendering is complete
        if let firstMatch = firstMatchRange {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.textView.scrollRangeToVisible(firstMatch)
                self.textView.setSelectedRange(firstMatch)
                self.textView.showFindIndicator(for: firstMatch)
            }
        }
    }

    func clearSearchHighlights() {
        renderMarkdown() // Re-render to clear highlights
    }

    func setupHotkey() {
        // Global hotkeys - work even when window is not focused
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            // ⌘+B = Toggle window visibility (ALWAYS GLOBAL)
            if event.modifierFlags.contains(.command) && event.keyCode == 11 {
                self.toggleWindowVisibility()
            }

            // ⌘+\ = Hide floating solution window (when main window is hidden)
            if event.modifierFlags.contains(.command) && event.keyCode == 42 && !self.window.isVisible {
                self.hideFloatingSolution()
            }

            // ⌘+1 = Switch to Notes tab (when visible)
            if event.modifierFlags.contains(.command) && event.keyCode == 18 && self.window.isVisible {
                self.switchToNotesTab()
            }

            // ⌘+2 = Switch to Voice tab (when visible)
            if event.modifierFlags.contains(.command) && event.keyCode == 19 && self.window.isVisible {
                self.switchToVoiceTab()
            }

            // ⌘+F = Toggle search (when visible and in notes tab)
            if event.modifierFlags.contains(.command) && event.keyCode == 3 && self.window.isVisible && self.currentTab == .notes {
                self.toggleSearch()
            }

            // ⌘+S = Capture screenshot (ALWAYS GLOBAL - thumbnail appears in voice timeline)
            if event.modifierFlags.contains(.command) && event.keyCode == 1 {
                // Auto-switch to voice tab to see the thumbnail
                if self.currentTab != .voice {
                    self.switchToVoiceTab()
                }
                // DON'T show window - let the screenshot alert notification appear instead
                // The user can press ⌘+B to show the main window if needed
                self.captureScreenshotPlaceholder()
            }

            // ⌘+Enter = Analyze screenshots (ALWAYS GLOBAL - shows result in pinned header)
            if event.modifierFlags.contains(.command) && event.keyCode == 36 {
                // Switch to voice tab to see the pinned result
                if self.currentTab != .voice {
                    self.switchToVoiceTab()
                }
                // Show window if hidden
                if !self.window.isVisible {
                    self.toggleWindowVisibility()
                }
                self.analyzeScreenshots()
            }

            // ⌘+G = Reset coding tab (when visible and in coding tab)
            if event.modifierFlags.contains(.command) && event.keyCode == 5 && self.window.isVisible && self.currentTab == .coding {
                self.resetCodingTab()
            }

        }

        // Local hotkey for when app is active
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // ⌘+B = Toggle window visibility
            if event.modifierFlags.contains(.command) && event.keyCode == 11 {
                self.toggleWindowVisibility()
                return nil
            }

            // ⌘+1 = Switch to Notes tab
            if event.modifierFlags.contains(.command) && event.keyCode == 18 {
                self.switchToNotesTab()
                return nil
            }

            // ⌘+2 = Switch to Voice tab
            if event.modifierFlags.contains(.command) && event.keyCode == 19 {
                self.switchToVoiceTab()
                return nil
            }

            // ⌘+F = Toggle search
            if event.modifierFlags.contains(.command) && event.keyCode == 3 {
                self.toggleSearch()
                return nil
            }

            // ⌘+S = Capture screenshot (works from voice tab)
            if event.modifierFlags.contains(.command) && event.keyCode == 1 && self.currentTab == .voice {
                self.captureScreenshotPlaceholder()
                return nil
            }

            // ⌘+Enter = Analyze screenshots (works from voice tab)
            if event.modifierFlags.contains(.command) && event.keyCode == 36 && self.currentTab == .voice {
                self.analyzeScreenshots()
                return nil
            }

            // ⌘+G = Clear screenshots (works from voice tab)
            if event.modifierFlags.contains(.command) && event.keyCode == 5 && self.currentTab == .voice {
                self.clearScreenshotsFromTimeline()
                return nil
            }

            // ESC = Close search
            if event.keyCode == 53 && self.isSearchVisible {
                self.toggleSearch()
                return nil
            }

            // ⌘+Arrow Keys = Move window
            if event.modifierFlags.contains(.command) {
                let moveDistance: CGFloat = 20
                var newOrigin = self.window.frame.origin

                switch event.keyCode {
                case 123: // Left arrow
                    newOrigin.x -= moveDistance
                    self.window.setFrameOrigin(newOrigin)
                    return nil
                case 124: // Right arrow
                    newOrigin.x += moveDistance
                    self.window.setFrameOrigin(newOrigin)
                    return nil
                case 125: // Down arrow
                    newOrigin.y -= moveDistance
                    self.window.setFrameOrigin(newOrigin)
                    return nil
                case 126: // Up arrow
                    newOrigin.y += moveDistance
                    self.window.setFrameOrigin(newOrigin)
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    @objc func toggleWindowVisibility() {
        if window.isVisible {
            // Fade out animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.window.animator().alphaValue = 0
            }, completionHandler: {
                self.window.orderOut(nil)
                self.window.alphaValue = 1

                // Hide Settings window with main window
                self.settingsWindowController?.window?.orderOut(nil)

                // Keep visible in dock
                NSApp.setActivationPolicy(.regular)

                // Show floating solution if there's a pinned solution
                if self.currentPinnedSolution != nil {
                    self.showFloatingSolutionWindow()
                }
            })
        } else {
            // Dismiss floating solution window first
            dismissFloatingSolutionWindow()

            // Show in dock when window is visible
            NSApp.setActivationPolicy(.regular)

            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Hide alert when main window becomes visible
            hideScreenshotAlert()

            // Fade in animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.window.animator().alphaValue = 1
            })
        }
    }

    // MARK: - Floating Solution Window

    /// Show floating solution window in top-right corner
    func showFloatingSolutionWindow() {
        guard let solution = currentPinnedSolution, !solution.isEmpty else { return }

        // Dismiss existing if any
        dismissFloatingSolutionWindow()

        // Get screen dimensions
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Floating window size (wider and taller for better readability)
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = min(750, screenFrame.height * 0.8)

        // Position in top-right corner with padding
        let windowX = screenFrame.maxX - windowWidth - 20
        let windowY = screenFrame.maxY - windowHeight - 20

        // Create borderless floating window
        let floatingWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        floatingWindow.level = .floating
        floatingWindow.isOpaque = false
        floatingWindow.backgroundColor = .clear
        floatingWindow.hasShadow = true
        floatingWindow.isMovableByWindowBackground = true

        // Container with blur effect
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.applePurple.withAlphaComponent(0.5).cgColor

        // Header with shortcuts
        let headerLabel = NSTextField(labelWithString: "⌘B Show  •  ⌘\\ Hide  •  ⌘J/K Scroll  •  ⌘Arrows Move")
        headerLabel.frame = NSRect(x: 12, y: windowHeight - 24, width: windowWidth - 24, height: 16)
        headerLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        headerLabel.textColor = .tertiaryLabelColor
        headerLabel.alignment = .center
        container.addSubview(headerLabel)

        // Calculate space for last Q&A (timeline style - taller to avoid overlap)
        let lastQA = getLastQuestionAnswer()
        let qaHeight: CGFloat = lastQA != nil ? 270 : 0
        let loadingHeight: CGFloat = 40

        // Solution scroll view (hidden scrollers, show on hover)
        let solutionScrollView = NSScrollView(frame: NSRect(x: 8, y: qaHeight + loadingHeight + 8, width: windowWidth - 16, height: windowHeight - 36 - qaHeight - loadingHeight))
        solutionScrollView.hasVerticalScroller = true
        solutionScrollView.hasHorizontalScroller = false
        solutionScrollView.autohidesScrollers = true
        solutionScrollView.scrollerStyle = .overlay
        solutionScrollView.borderType = .noBorder
        solutionScrollView.drawsBackground = false
        solutionScrollView.backgroundColor = .clear

        // Solution text view
        let solutionTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: solutionScrollView.contentSize.width, height: 0))
        solutionTextView.isEditable = false
        solutionTextView.isSelectable = true
        solutionTextView.drawsBackground = false
        solutionTextView.backgroundColor = .clear
        solutionTextView.textContainerInset = NSSize(width: 4, height: 4)
        solutionTextView.isVerticallyResizable = true
        solutionTextView.autoresizingMask = [.width]
        solutionTextView.textContainer?.widthTracksTextView = true

        // Format and set solution content
        let attributedSolution = formatMessageContent(solution, isQuestion: false)
        solutionTextView.textStorage?.setAttributedString(attributedSolution)

        solutionScrollView.documentView = solutionTextView
        container.addSubview(solutionScrollView)
        self.floatingSolutionTextView = solutionTextView
        self.floatingSolutionScrollView = solutionScrollView

        // Loading indicator - ambient glow
        let floatingGlowSize: CGFloat = 40
        let loadingView = NSView(frame: NSRect(
            x: (windowWidth - floatingGlowSize) / 2,
            y: qaHeight + (loadingHeight - floatingGlowSize) / 2,
            width: floatingGlowSize,
            height: floatingGlowSize
        ))
        loadingView.wantsLayer = true
        loadingView.isHidden = true

        // Pure glow layer
        let floatingGlow = CALayer()
        floatingGlow.frame = CGRect(x: 0, y: 0, width: floatingGlowSize, height: floatingGlowSize)
        floatingGlow.cornerRadius = floatingGlowSize / 2
        floatingGlow.backgroundColor = NSColor.appleGreen.withAlphaComponent(0.2).cgColor
        floatingGlow.shadowColor = NSColor.appleGreen.cgColor
        floatingGlow.shadowOffset = .zero
        floatingGlow.shadowRadius = 15
        floatingGlow.shadowOpacity = 0.5
        loadingView.layer?.addSublayer(floatingGlow)

        container.addSubview(loadingView)
        self.floatingLoadingView = loadingView

        // Q&A section (timeline style)
        if let (question, answer) = lastQA {
            // Divider
            let divider = NSView(frame: NSRect(x: 12, y: qaHeight + 4, width: windowWidth - 24, height: 1))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(divider)

            // Q&A container
            let qaContainer = NSView(frame: NSRect(x: 8, y: 8, width: windowWidth - 16, height: qaHeight - 12))
            qaContainer.wantsLayer = true
            container.addSubview(qaContainer)
            self.floatingQAContainer = qaContainer

            // Question bubble (timeline style - left aligned, darker)
            let qBubble = NSView(frame: NSRect(x: 0, y: qaHeight - 50, width: windowWidth - 40, height: 38))
            qBubble.wantsLayer = true
            qBubble.layer?.cornerRadius = 8
            qBubble.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            qaContainer.addSubview(qBubble)

            let qLabel = NSTextField(wrappingLabelWithString: question)
            qLabel.frame = NSRect(x: 8, y: 4, width: qBubble.frame.width - 16, height: 30)
            qLabel.font = .systemFont(ofSize: 11)
            qLabel.textColor = .secondaryLabelColor
            qLabel.lineBreakMode = .byTruncatingTail
            qLabel.maximumNumberOfLines = 2
            qBubble.addSubview(qLabel)

            // Answer bubble (timeline style - full width, lighter)
            let aBubble = NSView(frame: NSRect(x: 0, y: 4, width: windowWidth - 40, height: qaHeight - 58))
            aBubble.wantsLayer = true
            aBubble.layer?.cornerRadius = 8
            aBubble.layer?.backgroundColor = NSColor.applePurple.withAlphaComponent(0.15).cgColor
            qaContainer.addSubview(aBubble)

            let aScrollView = NSScrollView(frame: NSRect(x: 4, y: 4, width: aBubble.frame.width - 8, height: aBubble.frame.height - 8))
            aScrollView.hasVerticalScroller = true
            aScrollView.hasHorizontalScroller = false
            aScrollView.autohidesScrollers = true
            aScrollView.scrollerStyle = .overlay
            aScrollView.borderType = .noBorder
            aScrollView.drawsBackground = false

            let aTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: aScrollView.contentSize.width, height: 0))
            aTextView.isEditable = false
            aTextView.isSelectable = true
            aTextView.drawsBackground = false
            aTextView.textContainerInset = NSSize(width: 2, height: 2)
            aTextView.isVerticallyResizable = true
            aTextView.textContainer?.widthTracksTextView = true
            aTextView.font = .systemFont(ofSize: 11)
            aTextView.textColor = .labelColor

            let attributedAnswer = formatMessageContent(answer, isQuestion: false)
            aTextView.textStorage?.setAttributedString(attributedAnswer)

            aScrollView.documentView = aTextView
            aBubble.addSubview(aScrollView)
        }

        floatingWindow.contentView = container
        floatingWindow.alphaValue = 0
        floatingWindow.orderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            floatingWindow.animator().alphaValue = 1
        }

        self.floatingSolutionWindow = floatingWindow

        // Add global keyboard monitor for scrolling and moving - works when app is hidden
        floatingEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let floatingWindow = self.floatingSolutionWindow else { return }

            // Only respond to Cmd+key combinations
            guard event.modifierFlags.contains(.command) else { return }

            let scrollAmount: CGFloat = 50
            let moveAmount: CGFloat = 30

            // ⌘+J = scroll down
            if event.keyCode == 38 {
                self.scrollFloatingSolution(by: -scrollAmount)
            }
            // ⌘+K = scroll up
            if event.keyCode == 40 {
                self.scrollFloatingSolution(by: scrollAmount)
            }
            // ⌘+↑ = move window up
            if event.keyCode == 126 {
                var frame = floatingWindow.frame
                frame.origin.y += moveAmount
                floatingWindow.setFrame(frame, display: true)
            }
            // ⌘+↓ = move window down
            if event.keyCode == 125 {
                var frame = floatingWindow.frame
                frame.origin.y -= moveAmount
                floatingWindow.setFrame(frame, display: true)
            }
            // ⌘+← = move window left
            if event.keyCode == 123 {
                var frame = floatingWindow.frame
                frame.origin.x -= moveAmount
                floatingWindow.setFrame(frame, display: true)
            }
            // ⌘+→ = move window right
            if event.keyCode == 124 {
                var frame = floatingWindow.frame
                frame.origin.x += moveAmount
                floatingWindow.setFrame(frame, display: true)
            }
        }
    }

    /// Scroll the floating solution by delta
    func scrollFloatingSolution(by delta: CGFloat) {
        guard let scrollView = floatingSolutionScrollView,
              let clipView = scrollView.contentView as? NSClipView else { return }

        var newOrigin = clipView.bounds.origin
        newOrigin.y -= delta

        // Clamp to bounds
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height)
        newOrigin.y = max(0, min(newOrigin.y, maxY))

        clipView.setBoundsOrigin(newOrigin)
    }

    /// Dismiss the floating solution window
    func dismissFloatingSolutionWindow() {
        // Remove keyboard monitor
        if let monitor = floatingEventMonitor {
            NSEvent.removeMonitor(monitor)
            floatingEventMonitor = nil
        }

        guard let floatingWindow = floatingSolutionWindow else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            floatingWindow.animator().alphaValue = 0
        }, completionHandler: {
            floatingWindow.orderOut(nil)
            self.floatingSolutionWindow = nil
            self.floatingSolutionTextView = nil
            self.floatingSolutionScrollView = nil
            self.floatingQAContainer = nil
            self.floatingLoadingView = nil
        })
    }

    /// Hide floating solution window (⌘\)
    @objc func hideFloatingSolution() {
        dismissFloatingSolutionWindow()
    }

    /// Show loading animation on floating window
    func showFloatingLoading() {
        guard let loadingView = floatingLoadingView else { return }
        loadingView.isHidden = false
        startFloatingSpinner()
    }

    /// Hide loading animation on floating window
    func hideFloatingLoading() {
        floatingLoadingView?.isHidden = true
        stopFloatingSpinner()
    }

    /// Start glow pulse on floating window
    func startFloatingSpinner() {
        guard let loadingView = floatingLoadingView,
              let glowLayer = loadingView.layer?.sublayers?.first else { return }

        glowLayer.removeAllAnimations()

        let radiusPulse = CABasicAnimation(keyPath: "shadowRadius")
        radiusPulse.fromValue = 6
        radiusPulse.toValue = 15
        radiusPulse.duration = 1.2
        radiusPulse.autoreverses = true
        radiusPulse.repeatCount = .infinity
        radiusPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let opacityPulse = CABasicAnimation(keyPath: "shadowOpacity")
        opacityPulse.fromValue = 0.3
        opacityPulse.toValue = 0.7
        opacityPulse.duration = 1.2
        opacityPulse.autoreverses = true
        opacityPulse.repeatCount = .infinity
        opacityPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        glowLayer.add(radiusPulse, forKey: "radiusPulse")
        glowLayer.add(opacityPulse, forKey: "opacityPulse")
    }

    /// Stop glow pulse on floating window
    func stopFloatingSpinner() {
        guard let loadingView = floatingLoadingView,
              let glowLayer = loadingView.layer?.sublayers?.first else { return }
        glowLayer.removeAllAnimations()
    }

    /// Get the last question and answer from voice messages
    func getLastQuestionAnswer() -> (question: String, answer: String)? {
        // Find the last answer that's not a status message
        var lastAnswer: ConversationMessage?
        var lastQuestion: ConversationMessage?

        for message in voiceMessages.reversed() {
            if lastAnswer == nil && (message.type == .answer || message.type == .followUp) {
                lastAnswer = message
            }
            if lastAnswer != nil && message.type == .question {
                lastQuestion = message
                break
            }
        }

        guard let question = lastQuestion, let answer = lastAnswer else { return nil }

        return (question.content, answer.content)
    }

    /// Update the Q&A section in the floating window in real-time
    func updateFloatingQA() {
        guard let floatingWindow = floatingSolutionWindow,
              let container = floatingWindow.contentView as? NSVisualEffectView else { return }

        let windowWidth = floatingWindow.frame.width
        let windowHeight = floatingWindow.frame.height
        let qaHeight: CGFloat = 270
        let loadingHeight: CGFloat = 40

        // Remove existing Q&A container if any
        floatingQAContainer?.removeFromSuperview()
        floatingQAContainer = nil

        // Get latest Q&A
        guard let (question, answer) = getLastQuestionAnswer() else { return }

        // Resize solution scroll view to make room for Q&A
        if let solutionScrollView = floatingSolutionScrollView {
            let newSolutionHeight = windowHeight - 36 - qaHeight - loadingHeight
            solutionScrollView.frame = NSRect(x: 8, y: qaHeight + loadingHeight + 8, width: windowWidth - 16, height: newSolutionHeight)
        }

        // Find or create divider
        let dividerId = NSUserInterfaceItemIdentifier("floatingQADivider")
        if container.subviews.first(where: { $0.identifier == dividerId }) == nil {
            let divider = NSView(frame: NSRect(x: 12, y: qaHeight + 4, width: windowWidth - 24, height: 1))
            divider.identifier = dividerId
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(divider)
        }

        // Create new Q&A container
        let qaContainer = NSView(frame: NSRect(x: 8, y: 8, width: windowWidth - 16, height: qaHeight - 12))
        qaContainer.wantsLayer = true
        container.addSubview(qaContainer)
        self.floatingQAContainer = qaContainer

        // Question bubble
        let qBubble = NSView(frame: NSRect(x: 0, y: qaHeight - 50, width: windowWidth - 40, height: 38))
        qBubble.wantsLayer = true
        qBubble.layer?.cornerRadius = 8
        qBubble.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        qaContainer.addSubview(qBubble)

        let qLabel = NSTextField(wrappingLabelWithString: question)
        qLabel.frame = NSRect(x: 8, y: 4, width: qBubble.frame.width - 16, height: 30)
        qLabel.font = .systemFont(ofSize: 11)
        qLabel.textColor = .secondaryLabelColor
        qLabel.lineBreakMode = .byTruncatingTail
        qLabel.maximumNumberOfLines = 2
        qBubble.addSubview(qLabel)

        // Answer bubble
        let aBubble = NSView(frame: NSRect(x: 0, y: 4, width: windowWidth - 40, height: qaHeight - 58))
        aBubble.wantsLayer = true
        aBubble.layer?.cornerRadius = 8
        aBubble.layer?.backgroundColor = NSColor.applePurple.withAlphaComponent(0.15).cgColor
        qaContainer.addSubview(aBubble)

        let aScrollView = NSScrollView(frame: NSRect(x: 4, y: 4, width: aBubble.frame.width - 8, height: aBubble.frame.height - 8))
        aScrollView.hasVerticalScroller = true
        aScrollView.hasHorizontalScroller = false
        aScrollView.autohidesScrollers = true
        aScrollView.scrollerStyle = .overlay
        aScrollView.borderType = .noBorder
        aScrollView.drawsBackground = false

        let aTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: aScrollView.contentSize.width, height: 0))
        aTextView.isEditable = false
        aTextView.isSelectable = true
        aTextView.drawsBackground = false
        aTextView.textContainerInset = NSSize(width: 2, height: 2)
        aTextView.isVerticallyResizable = true
        aTextView.textContainer?.widthTracksTextView = true
        aTextView.font = .systemFont(ofSize: 11)
        aTextView.textColor = .labelColor

        let attributedAnswer = formatMessageContent(answer, isQuestion: false)
        aTextView.textStorage?.setAttributedString(attributedAnswer)

        aScrollView.documentView = aTextView
        aBubble.addSubview(aScrollView)
    }

    /// Update the solution content in the floating window in real-time
    func updateFloatingSolutionContent(_ content: String) {
        guard let textView = floatingSolutionTextView else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let attributedContent = self.formatMessageContent(content, isQuestion: false)
            textView.textStorage?.setAttributedString(attributedContent)
        }
    }

    func startScreenShareMonitoring() {
        guard autoHideEnabled else { return }

        // Monitor for screen recording (simplified version)
        // In production, you'd use more sophisticated detection
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.autoHideEnabled else { return }

            // Check if screen is being captured
            // This is a simplified check - real implementation would monitor actual screen sharing
            if CGPreflightScreenCaptureAccess() {
                // Hide window when screen sharing detected
                if self.window.isVisible {
                    self.window.orderOut(nil)
                }
            }
        }
    }

    // MARK: - Formatting Toolbar
    func setupFormattingToolbar(in parentView: NSView) {
        // Floating toolbar container - visionOS style
        formattingToolbar = NSVisualEffectView(frame: NSRect(
            x: (parentView.frame.width - 360) / 2,
            y: parentView.frame.height - 60,
            width: 360,
            height: 44
        ))
        formattingToolbar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        formattingToolbar.blendingMode = .withinWindow
        formattingToolbar.material = .hudWindow
        formattingToolbar.state = .active
        formattingToolbar.alphaValue = 0
        formattingToolbar.isHidden = true
        formattingToolbar.wantsLayer = true
        formattingToolbar.layer?.cornerRadius = 12
        formattingToolbar.layer?.borderWidth = 1.5
        formattingToolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        parentView.addSubview(formattingToolbar)

        let buttonWidth: CGFloat = 40
        let spacing: CGFloat = 4
        var xOffset: CGFloat = 8

        // Heading button
        let headingBtn = createFormattingButton(
            icon: "textformat.size",
            tooltip: "Heading",
            action: #selector(insertHeading)
        )
        headingBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(headingBtn)
        xOffset += buttonWidth + spacing

        // Bold button
        let boldBtn = createFormattingButton(
            icon: "bold",
            tooltip: "Bold",
            action: #selector(insertBold)
        )
        boldBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(boldBtn)
        xOffset += buttonWidth + spacing

        // Italic button
        let italicBtn = createFormattingButton(
            icon: "italic",
            tooltip: "Italic",
            action: #selector(insertItalic)
        )
        italicBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(italicBtn)
        xOffset += buttonWidth + spacing

        // Code button
        let codeBtn = createFormattingButton(
            icon: "chevron.left.forwardslash.chevron.right",
            tooltip: "Code",
            action: #selector(insertCode)
        )
        codeBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(codeBtn)
        xOffset += buttonWidth + spacing

        // Code block button
        let codeBlockBtn = createFormattingButton(
            icon: "curlybraces",
            tooltip: "Code Block",
            action: #selector(insertCodeBlock)
        )
        codeBlockBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(codeBlockBtn)
        xOffset += buttonWidth + spacing

        // List button
        let listBtn = createFormattingButton(
            icon: "list.bullet",
            tooltip: "Bullet List",
            action: #selector(insertList)
        )
        listBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(listBtn)
        xOffset += buttonWidth + spacing

        // Link button
        let linkBtn = createFormattingButton(
            icon: "link",
            tooltip: "Link",
            action: #selector(insertLink)
        )
        linkBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(linkBtn)
        xOffset += buttonWidth + spacing

        // Divider button
        let dividerBtn = createFormattingButton(
            icon: "minus",
            tooltip: "Divider",
            action: #selector(insertDivider)
        )
        dividerBtn.frame.origin = NSPoint(x: xOffset, y: 7)
        formattingToolbar.addSubview(dividerBtn)
    }

    func createFormattingButton(icon: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.contentTintColor = .white
        return button
    }

    func showFormattingToolbar() {
        guard let toolbar = formattingToolbar, !isFormattingToolbarVisible else { return }
        isFormattingToolbarVisible = true

        toolbar.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            toolbar.animator().alphaValue = 0.95
        })
    }

    func hideFormattingToolbar() {
        guard let toolbar = formattingToolbar, isFormattingToolbarVisible else { return }
        isFormattingToolbarVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            toolbar.animator().alphaValue = 0
        }, completionHandler: {
            toolbar.isHidden = true
        })
    }

    // MARK: - Formatting Actions
    @objc func insertHeading() {
        insertMarkdownWrapper(prefix: "## ", suffix: "", placeholder: "Heading")
    }

    @objc func insertBold() {
        insertMarkdownWrapper(prefix: "**", suffix: "**", placeholder: "bold text")
    }

    @objc func insertItalic() {
        insertMarkdownWrapper(prefix: "*", suffix: "*", placeholder: "italic text")
    }

    @objc func insertCode() {
        insertMarkdownWrapper(prefix: "`", suffix: "`", placeholder: "code")
    }

    @objc func insertCodeBlock() {
        insertMarkdownWrapper(prefix: "```\n", suffix: "\n```", placeholder: "code block")
    }

    @objc func insertList() {
        let range = textView.selectedRange()
        let selectedText = (textView.string as NSString).substring(with: range)

        guard !selectedText.isEmpty else { return }

        // Split by lines and add bullet to each line
        let lines = selectedText.components(separatedBy: .newlines)
        let bulletedText = lines.map { line in
            line.isEmpty ? "" : "- \(line)"
        }.joined(separator: "\n")

        textView.insertText(bulletedText, replacementRange: range)

        DispatchQueue.main.async {
            self.renderMarkdown()
        }
    }

    @objc func insertLink() {
        insertMarkdownWrapper(prefix: "[", suffix: "](url)", placeholder: "link text")
    }

    @objc func insertDivider() {
        let range = textView.selectedRange()
        textView.insertText("\n\n---\n\n", replacementRange: range)
        renderMarkdown()
    }

    func insertMarkdownWrapper(prefix: String, suffix: String, placeholder: String) {
        let range = textView.selectedRange()
        let selectedText = (textView.string as NSString).substring(with: range)

        // Only format if there's selected text
        guard !selectedText.isEmpty else { return }

        let textToInsert = prefix + selectedText + suffix
        textView.insertText(textToInsert, replacementRange: range)

        // Force re-render markdown
        DispatchQueue.main.async {
            self.renderMarkdown()
        }
    }

    // MARK: - Markdown Rendering (Basic)
    func renderMarkdown() {
        guard let storage = textView.textStorage else { return }
        notesMarkdownRenderer.render(in: storage)
    }

    // MARK: - Markdown Rendering for Analysis View
    func renderAnalysisMarkdown() {
        guard let storage = analysisTextView.textStorage else { return }
        analysisMarkdownRenderer.render(in: storage)
    }

    // MARK: - NSTextViewDelegate
    func textDidChange(_ notification: Notification) {
        // Re-render markdown with debounce to prevent conflicts
        guard let currentTextView = notification.object as? NSTextView else { return }
        if currentTextView == textView {
            let currentLength = textView.string.count
            let textGrew = currentLength > lastTextLength

            // Only auto-continue lists when text grew (not when deleting)
            if textGrew {
                handleListAutoContinuation()
            }

            lastTextLength = currentLength

            // Auto-save notes to UserDefaults
            saveNotes()

            renderTimer?.invalidate()
            renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.renderMarkdown()
            }
        }
    }

    // MARK: - Persistence
    func saveNotes() {
        UserDefaults.standard.set(textView.string, forKey: notesStorageKey)
    }

    func handleListAutoContinuation() {
        let text = textView.string as NSString
        let cursorLocation = textView.selectedRange().location

        // Check if user just pressed Enter (newline at cursor-1)
        guard cursorLocation > 0,
              cursorLocation <= text.length,
              text.character(at: cursorLocation - 1) == 10 else { return } // 10 = newline

        // Find the start of the previous line
        var lineStart = cursorLocation - 2
        while lineStart > 0 && text.character(at: lineStart) != 10 {
            lineStart -= 1
        }
        if lineStart > 0 { lineStart += 1 }

        // Get the previous line
        let lineLength = cursorLocation - lineStart - 1
        guard lineLength > 0 else { return }
        let previousLine = text.substring(with: NSRange(location: lineStart, length: lineLength))

        // Check if previous line starts with "- " or is just "- "
        if previousLine.hasPrefix("- ") {
            let content = String(previousLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)

            // If previous line was just "- " (empty bullet), remove it and stop list
            if content.isEmpty {
                // Remove the bullet line and the newline we just added
                textView.undoManager?.beginUndoGrouping()
                let removeRange = NSRange(location: lineStart, length: lineLength + 1)
                textView.shouldChangeText(in: removeRange, replacementString: "")
                textView.replaceCharacters(in: removeRange, with: "")
                textView.didChangeText()
                textView.undoManager?.endUndoGrouping()
            } else {
                // Add new bullet for next item
                textView.insertText("- ", replacementRange: NSRange(location: cursorLocation, length: 0))
            }
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Show toolbar when editing notes
        guard let currentTextView = notification.object as? NSTextView else { return }
        if currentTextView == textView && currentTab == .notes {
            showFormattingToolbar()
        }
    }

    @objc func captureScreenshotPlaceholder() {
        // Only allow screenshots during active session
        guard isSessionActive else {
            return
        }

        // Check permission first
        if !CGPreflightScreenCaptureAccess() {
            showPermissionAlert()
            return
        }

        Task {
            await captureScreenshot()
        }
    }

    func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Conversation Assistant needs Screen Recording permission to capture screenshots.\n\n1. Click 'Open Settings' below\n2. Enable 'ConversationAssistant' in Screen Recording\n3. Restart the app"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings > Privacy & Security > Screen Recording
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func captureScreenshot() async {
        let result = await screenCaptureService.captureScreen()

        switch result {
        case .success(let screenshot):
            // Generate thumbnail for timeline (larger)
            let timelineThumbnailSize = NSSize(width: 200, height: 112)
            let timelineThumbnail = screenshot.generateThumbnail(size: timelineThumbnailSize)

            // Add to screenshots array
            screenshots.append(screenshot)

            // Add thumbnail to voice timeline (main UI)
            await MainActor.run {
                addScreenshotToTimeline(thumbnail: timelineThumbnail, screenshotId: screenshot.id)
            }

        case .failure(let error):
            await MainActor.run {
                let message: String
                switch error {
                case .noDisplayFound:
                    message = "No display found"
                case .captureFailed(let underlyingError):
                    message = "Error: \(underlyingError.localizedDescription)"
                }
                showAlert(title: "Screenshot Failed", message: message)
            }
        }
    }


    func addThumbnailToUI(thumbnail: NSImage, id: UUID) {
        let thumbnailHeight: CGFloat = 35
        let thumbnailWidth: CGFloat = 62  // Proportional 16:9 to height
        let spacing: CGFloat = 10
        let xOffset = CGFloat(screenshotThumbnails.count) * (thumbnailWidth + spacing)

        let thumbnailButton = NSButton(frame: NSRect(x: xOffset, y: 0, width: thumbnailWidth, height: thumbnailHeight))
        thumbnailButton.image = thumbnail
        thumbnailButton.imageScaling = .scaleProportionallyUpOrDown
        thumbnailButton.isBordered = false
        thumbnailButton.bezelStyle = .rounded
        thumbnailButton.tag = screenshotThumbnails.count
        thumbnailButton.wantsLayer = true
        thumbnailButton.layer?.cornerRadius = 6
        thumbnailButton.layer?.borderWidth = 1.5
        thumbnailButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        thumbnailButton.layer?.masksToBounds = true

        screenshotThumbnailsContainer.addSubview(thumbnailButton)
        screenshotThumbnails.append(thumbnailButton)

        // Update container width
        screenshotThumbnailsContainer.frame.size.width = CGFloat(screenshotThumbnails.count) * (thumbnailWidth + spacing)
    }

    @objc func resetCodingTab() {
        // Clear all screenshots
        screenshots.removeAll()

        // Remove all thumbnail buttons from UI
        for thumbnail in screenshotThumbnails {
            thumbnail.removeFromSuperview()
        }
        screenshotThumbnails.removeAll()

        // Reset container width
        screenshotThumbnailsContainer.frame.size.width = 0

        // Clear analysis text
        analysisTextView.string = ""
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func analyzeScreenshots() {
        guard !screenshots.isEmpty else {
            showAlert(title: "No Screenshots", message: "Please capture at least one screenshot first (⌘S)")
            return
        }

        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            showAlert(title: "API Key Required", message: "Please configure your Anthropic API key in settings (⚙️ API Key)")
            return
        }

        // Check for data consent (required by App Store Guideline 5.1.2)
        if !UserDefaults.standard.bool(forKey: dataConsentKey) {
            let consentGiven = showDataConsentDialog()
            if !consentGiven {
                return
            }
            UserDefaults.standard.set(true, forKey: dataConsentKey)
        }

        Task {
            await performAnalysis(apiKey: apiKey)
        }
    }

    func showDataConsentDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Data Sharing Consent"
        alert.informativeText = """
        To analyze your screenshots, Conversation Assistant will send them to Anthropic's Claude AI service.

        What is shared:
        • Screenshot images you capture
        • Analysis prompts

        What is NOT shared:
        • Your notes
        • Personal information
        • API keys

        Anthropic processes data according to their privacy policy. Screenshots are not stored permanently.

        Do you consent to share screenshot data with Anthropic for AI analysis?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "I Consent")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Privacy Policy")

        let response = alert.runModal()

        if response == .alertThirdButtonReturn {
            // Show Anthropic privacy policy
            if let url = URL(string: "https://www.anthropic.com/privacy") {
                NSWorkspace.shared.open(url)
            }
            // Show dialog again after viewing privacy policy
            return showDataConsentDialog()
        }

        return response == .alertFirstButtonReturn
    }

    func performAnalysis(apiKey: String) async {
        // Convert screenshots to base64
        var base64Images: [String] = []
        for screenshot in screenshots {
            if let base64 = screenshot.toBase64() {
                base64Images.append(base64)
            }
        }

        // Show loading state in pinned header
        await MainActor.run {
            setPinnedSolution("🤔 Analyzing \(screenshots.count) screenshot\(screenshots.count == 1 ? "" : "s")...")
        }

        // Always create fresh client with current API key
        let client = AnthropicClient(apiKey: apiKey)

        // Get prompt from analysis mode
        let prompt = analysisMode.prompt

        // Get conversation history for context
        let conversationHistory = conversationContext.getFullConversation()
        let contextForAPI = conversationHistory.isEmpty ? nil : conversationHistory

        // Collect full response for pinning
        var fullResponse = ""

        // Stream the response directly to pinned solution
        let result = await client.sendMessageStream(
            images: base64Images,
            prompt: prompt,
            conversationContext: contextForAPI
        ) { [weak self] chunk in
            fullResponse += chunk
            Task { @MainActor in
                guard let self = self else { return }
                // Update pinned solution with streaming content
                self.updatePinnedSolutionContent(fullResponse)
            }
        }

        if case .failure(let error) = result {
            await MainActor.run {
                showAlert(title: "Analysis Failed", message: error.localizedDescription)
                setPinnedSolution("❌ Analysis failed: \(error.localizedDescription)")
            }
        } else {
            // Final update - reformat content
            await MainActor.run {
                currentPinnedSolution = fullResponse
                let attributedSolution = formatMessageContent(fullResponse, isQuestion: false)
                pinnedSolutionTextView.textStorage?.setAttributedString(attributedSolution)

                // Clear screenshots for next task
                screenshots.removeAll()
            }
        }
    }

    /// Update pinned solution content and expand height smoothly during streaming
    func updatePinnedSolutionContent(_ content: String) {
        let attributedSolution = formatMessageContent(content, isQuestion: false)
        pinnedSolutionTextView.textStorage?.setAttributedString(attributedSolution)

        // Calculate text height using layout manager
        guard let layoutManager = pinnedSolutionTextView.layoutManager,
              let textContainer = pinnedSolutionTextView.textContainer else { return }

        // Ensure container width is correct for text calculation
        let halfWidth = voiceContentView.frame.width / 2
        let scrollViewWidth = halfWidth - 25
        textContainer.containerSize = NSSize(width: scrollViewWidth - 10, height: CGFloat.greatestFiniteMagnitude)

        // Force complete layout recalculation
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: pinnedSolutionTextView.string.count), actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height + 30

        // Calculate max allowed height for container
        let maxPinnedHeight = voiceContentView.frame.height * 0.7
        let targetHeight = min(textHeight + 35, maxPinnedHeight)

        // Only expand container if content needs more space
        if targetHeight > pinnedSolutionContainer.frame.height {
            pinnedSolutionContainer.frame = NSRect(
                x: halfWidth,
                y: voiceContentView.frame.height - 65 - targetHeight,
                width: halfWidth - 15,
                height: targetHeight
            )

            // Update header position
            if let header = pinnedSolutionContainer.viewWithTag(100) {
                header.frame.origin.y = targetHeight - 25
            }

            // Update scroll view
            pinnedSolutionScrollView.frame = NSRect(
                x: 5, y: 5,
                width: pinnedSolutionContainer.frame.width - 10,
                height: targetHeight - 35
            )

            // Update text view width (height auto-expands)
            pinnedSolutionTextView.frame.size.width = pinnedSolutionScrollView.contentSize.width
        }

        pinnedSolutionTextView.scrollToEndOfDocument(nil)

        // Sync to floating window if visible
        if floatingSolutionWindow != nil {
            updateFloatingSolutionContent(content)
        }
    }

    /// Clear timeline messages when a new coding task is pinned
    func clearTimelineForNewTask() {
        // Remove all subviews from timeline
        for subview in voiceTimelineContainer.subviews {
            subview.removeFromSuperview()
        }
        voiceMessages.removeAll()

        // Add status message indicating new task
        addVoiceMessage(type: .status, content: "New coding task loaded\n\nAsk follow-up questions about the solution above.", topic: nil)
    }

    @objc func clearAllScreenshots() {
        screenshots.removeAll()
        screenshotThumbnails.forEach { $0.removeFromSuperview() }
        screenshotThumbnails.removeAll()
        screenshotThumbnailsContainer.frame.size.width = 100
        analysisTextView.string = "💻 AI Analysis will appear here\n\nCapture screenshots (⌘S) and press Analyze (⌘Enter)"
    }

    /// Clear screenshots from voice timeline
    func clearScreenshotsFromTimeline() {
        // Clear screenshots array
        screenshots.removeAll()

        // Remove screenshot containers from timeline
        for subview in voiceTimelineContainer.subviews {
            if let identifier = subview.identifier?.rawValue, identifier.hasPrefix("screenshot_") {
                subview.removeFromSuperview()
            }
        }

        // Remove screenshot messages from array
        voiceMessages.removeAll { $0.type == .screenshot }

        // Hide pinned solution if showing
        clearPinnedSolution()

        // Recalculate timeline height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
    }

    @objc func showSettings() {
        // Show settings window for API keys configuration
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController.create()
        }

        // Ensure window appears on top
        if let settingsWindow = settingsWindowController?.window {
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Data Source Indicator Click Handlers

    @objc func confluenceIndicatorClicked() {
        if OAuthManager.shared.isConnected(provider: .atlassian) {
            // Show disconnect confirmation
            showDisconnectAlert(for: .atlassian)
        } else {
            // Start OAuth flow
            OAuthManager.shared.startOAuthFlow(for: .atlassian)
        }
    }

    @objc func jiraIndicatorClicked() {
        // Jira uses same Atlassian OAuth as Confluence
        if OAuthManager.shared.isConnected(provider: .atlassian) {
            showDisconnectAlert(for: .atlassian)
        } else {
            OAuthManager.shared.startOAuthFlow(for: .atlassian)
        }
    }

    @objc func githubIndicatorClicked() {
        print("[GitHub] githubIndicatorClicked called!")
        NSLog("GitHub button clicked!")
        if OAuthManager.shared.isConnected(provider: .github) {
            print("[GitHub] Already connected, showing disconnect")
            showDisconnectAlert(for: .github)
        } else {
            print("[GitHub] Not connected, starting OAuth flow")
            OAuthManager.shared.startOAuthFlow(for: .github)
        }
    }

    private func showDisconnectAlert(for provider: OAuthProvider) {
        let alert = NSAlert()
        alert.messageText = "Disconnect \(provider.displayName)?"
        alert.informativeText = "This will remove your OAuth connection. You can reconnect anytime by clicking the indicator again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            OAuthManager.shared.disconnect(provider: provider)
            updateStatusBarIndicators()
            updateToolTips()
        }
    }

    private func updateToolTips() {
        let isAtlassianConnected = OAuthManager.shared.isConnected(provider: .atlassian)
        confluenceButton.toolTip = isAtlassianConnected ? "Click to disconnect Confluence" : "Click to connect Confluence"
        jiraButton.toolTip = isAtlassianConnected ? "Click to disconnect Jira" : "Click to connect Jira"

        let isGitHubConnected = OAuthManager.shared.isConnected(provider: .github)
        githubButton.toolTip = isGitHubConnected ? "Click to disconnect GitHub" : "Click to connect GitHub"
    }

    func maskApiKey(_ key: String) -> String {
        guard key.count > 10 else { return "sk-ant-***" }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(3))
        return "\(prefix)***\(suffix)"
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        screenshotMonitorTimer?.invalidate()
    }

    // MARK: - OAuth URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == OAuthConfig.urlScheme {
                NSLog("App: Received OAuth callback: \(url)")
                OAuthManager.shared.handleCallback(url)

                // Bring Settings window to front if open
                if let settingsWindow = settingsWindowController?.window, settingsWindow.isVisible {
                    settingsWindow.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - Screenshot Alert System
    func startScreenshotMonitoring() {
        // Monitor for new screenshots
        screenshotMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Check if we have new screenshots and app is not focused
            if self.screenshots.count > self.lastScreenshotCount && !self.window.isKeyWindow {
                self.showScreenshotAlert()
            }

            self.lastScreenshotCount = self.screenshots.count
        }
    }

    func showScreenshotAlert() {
        // Don't show if alert already visible
        if let existingAlert = alertWindow, existingAlert.isVisible {
            if let container = alertThumbnailsContainer {
                alertWindowManager.createThumbnails(for: screenshots, in: container)
            }
            return
        }

        // Create alert window with container
        guard let (window, container) = alertWindowManager.createWindow() else { return }
        
        alertWindow = window
        alertThumbnailsContainer = container
        
        // Populate thumbnails
        alertWindowManager.createThumbnails(for: screenshots, in: container)
        
        // Show with animation
        alertWindowManager.show(window)
        
        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            self.alertWindowManager.hide(window)
        }
    }

    func updateAlertThumbnails() {
        guard let container = alertThumbnailsContainer else { return }
        alertWindowManager.createThumbnails(for: screenshots, in: container)
    }

    func hideScreenshotAlert() {
        guard let window = alertWindow else { return }
        alertWindowManager.hide(window)
    }

    // MARK: - Permissions Panel
    var dataConsentStatusLabel: NSTextField!

    func setupPermissionsPanel(in parentView: NSView) {
        // Center the panel vertically and horizontally
        let panelWidth: CGFloat = 560
        let panelHeight: CGFloat = 360
        let panel = NSVisualEffectView(frame: NSRect(
            x: (parentView.frame.width - panelWidth) / 2,
            y: (parentView.frame.height - panelHeight) / 2,
            width: panelWidth,
            height: panelHeight
        ))
        panel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        panel.blendingMode = .withinWindow
        panel.material = .hudWindow
        panel.state = .active
        panel.alphaValue = 0.96
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 20
        panel.layer?.borderWidth = 2.0
        panel.layer?.borderColor = NSColor.appleGold.withAlphaComponent(0.6).cgColor
        parentView.addSubview(panel)
        self.permissionsPanel = panel

        // Title
        let title = NSTextField(labelWithString: "🔐 Setup Required")
        title.frame = NSRect(x: 40, y: panel.frame.height - 60, width: panel.frame.width - 80, height: 35)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = .white
        title.alignment = .center
        panel.addSubview(title)

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Complete the following steps to use Conversation Assistant")
        subtitle.frame = NSRect(x: 40, y: panel.frame.height - 88, width: panel.frame.width - 80, height: 20)
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitle.alignment = .center
        panel.addSubview(subtitle)

        // Screen Recording Permission (top row)
        createPermissionRow(
            in: panel,
            yOffset: panel.frame.height - 175,
            icon: "📸",
            title: "Screen Recording",
            description: "Capture screenshots during sessions",
            buttonTitle: "Open Settings",
            action: #selector(openScreenRecordingSettings),
            isScreenRecording: true
        )

        // Anthropic Data Consent (bottom row)
        createPermissionRow(
            in: panel,
            yOffset: panel.frame.height - 260,
            icon: "🤖",
            title: "AI Data Sharing",
            description: "Send screenshots to Anthropic Claude for analysis",
            buttonTitle: "I Consent",
            action: #selector(grantDataConsent),
            isScreenRecording: false
        )

        // Hint text at bottom
        let hint = NSTextField(labelWithString: "Global shortcuts (⌘B, ⌘S, ⌘Enter) work from any app")
        hint.frame = NSRect(x: 40, y: 20, width: panel.frame.width - 80, height: 16)
        hint.font = .systemFont(ofSize: 11, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.5)
        hint.alignment = .center
        panel.addSubview(hint)

        // Check permissions and update UI
        updatePermissionStatus()
        startPermissionMonitoring()
    }

    func createPermissionRow(in panel: NSView, yOffset: CGFloat, icon: String, title: String, description: String, buttonTitle: String, action: Selector, isScreenRecording: Bool) {
        // Container
        let container = NSView(frame: NSRect(x: 40, y: yOffset, width: panel.frame.width - 80, height: 70))
        panel.addSubview(container)

        // Icon
        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.frame = NSRect(x: 0, y: 20, width: 40, height: 30)
        iconLabel.font = .systemFont(ofSize: 28)
        iconLabel.alignment = .center
        container.addSubview(iconLabel)

        // Title & Description
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 50, y: 38, width: 200, height: 20)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        container.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.frame = NSRect(x: 50, y: 18, width: 300, height: 18)
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = NSColor.white
        container.addSubview(descLabel)

        // Status indicator
        let statusLabel = NSTextField(labelWithString: "⚠️ Required")
        statusLabel.frame = NSRect(x: container.frame.width - 180, y: 42, width: 120, height: 18)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemOrange
        statusLabel.alignment = .right
        container.addSubview(statusLabel)

        // Store reference based on type
        if isScreenRecording {
            screenRecordingStatusLabel = statusLabel
        } else {
            dataConsentStatusLabel = statusLabel
        }

        // Action button
        let button = NSButton(frame: NSRect(x: container.frame.width - 120, y: 12, width: 120, height: 28))
        button.title = buttonTitle
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.font = .systemFont(ofSize: 12, weight: .medium)
        container.addSubview(button)
    }

    @objc func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func grantDataConsent() {
        UserDefaults.standard.set(true, forKey: dataConsentKey)
        updatePermissionStatus()
    }

    func updatePermissionStatus() {
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        let hasDataConsent = UserDefaults.standard.bool(forKey: dataConsentKey)

        screenRecordingStatusLabel?.stringValue = hasScreenRecording ? "✅ Enabled" : "⚠️ Required"
        screenRecordingStatusLabel?.textColor = hasScreenRecording ? .appleGreen : .systemOrange

        dataConsentStatusLabel?.stringValue = hasDataConsent ? "✅ Granted" : "⚠️ Required"
        dataConsentStatusLabel?.textColor = hasDataConsent ? .appleGreen : .systemOrange

        // Hide panel if both permissions granted
        if hasScreenRecording && hasDataConsent {
            permissionsPanel?.isHidden = true
            stopPermissionMonitoring()
        } else {
            permissionsPanel?.isHidden = false
        }
    }

    func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
    }

    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    // MARK: - Voice Session Methods

    @objc func toggleListening() {
        if isSessionActive {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        // Check for Groq API key
        if groqApiKey == nil {
            promptForGroqApiKey()
            return
        }

        // Check for Anthropic API key (needed for Haiku answers)
        if apiKey == nil {
            showAlert(title: "API Key Required", message: "Please configure your Anthropic API key in Settings (⌘,)")
            return
        }

        // Initialize recorder and clients
        vadRecorder = VADAudioRecorder()
        systemAudioCapture = SystemAudioCapture()
        groqClient = GroqSpeechClient(apiKey: groqApiKey!)
        anthropicClient = AnthropicClient(apiKey: apiKey!)

        // === USER MIC CALLBACKS (your voice) ===
        vadRecorder?.onLevelUpdate = { [weak self] db, isSpeaking in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.pulseMicIcon(isSpeaking: isSpeaking, db: db)
            }
        }

        vadRecorder?.onStatusChange = { [weak self] _ in
            // Status updates disabled - UI shows visual feedback
        }

        vadRecorder?.onSpeechSegment = { [weak self] audioData in
            guard let self = self else { return }
            self.processAudioSegment(audioData, source: .microphone)
        }

        // === SYSTEM AUDIO CALLBACKS (what you hear - Zoom/Teams) ===
        systemAudioCapture?.onStatusChange = { [weak self] _ in
            // Status updates disabled - UI shows visual feedback
        }

        systemAudioCapture?.onLevelUpdate = { [weak self] db, isSpeaking in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.animateWaveform(bars: self.systemWaveformBars, color: .appleGold, isSpeaking: isSpeaking, db: db)
                // Pulse the speaker icon when system audio is detected
                self.pulseSpeakerIcon(isSpeaking: isSpeaking, db: db)
            }
        }

        systemAudioCapture?.onSpeechSegment = { [weak self] audioData in
            guard let self = self else { return }
            self.processAudioSegment(audioData, source: .systemAudio)
        }

        // Start listening to BOTH audio sources
        do {
            // Start user mic capture
            try vadRecorder?.startListening()

            // Start system audio capture in background
            Task {
                do {
                    try await systemAudioCapture?.startCapturing()
                } catch {
                    // System audio optional - mic still works
                }
            }

            isSessionActive = true

            // Clear screenshots array for new session
            screenshots.removeAll()
            // Rename old gallery so new screenshots create a fresh one (old gallery stays visible)
            if let oldGallery = voiceTimelineContainer.subviews.first(where: { $0.identifier?.rawValue == "screenshotGallery" }) {
                oldGallery.identifier = NSUserInterfaceItemIdentifier("screenshotGallery_archived")
            }

            // Update Nest button to recording state
            updateNestButtonState(recording: true)

            // Show recording indicator (Dynamic Island style)
            showRecordingIndicator()

            addVoiceMessage(type: .status, content: "Listening...", topic: nil)

        } catch {
            showAlert(title: "Audio Error", message: "Could not start audio recording: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        vadRecorder?.stopListening()
        vadRecorder = nil

        // Stop system audio capture
        Task {
            await systemAudioCapture?.stopCapturing()
            await MainActor.run {
                systemAudioCapture = nil
            }
        }

        isSessionActive = false

        // Clear conversation context but keep timeline visible
        conversationContext.clear()
        utteranceBuffer = ""

        // Hide loading indicator
        hideLoading()

        // Hide recording indicator
        hideRecordingIndicator()

        // Update Nest button to idle state
        updateNestButtonState(recording: false)

        voiceStatusLabel.stringValue = ""
        // Waveform bars reset handled by updateNestButtonState collapse animation

        // Add status to timeline (preserved)
        addVoiceMessage(type: .status, content: "Session ended", topic: nil)
    }

    // MARK: - Text Prompt Input

    @objc func sendPromptFromInput() {
        let prompt = promptInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard !isPromptProcessing else { return }  // Prevent double-send

        // Check for API key
        guard let anthropicKey = apiKey else {
            showAlert(title: "API Key Required", message: "Please configure your Anthropic API key in Settings (⌘,)")
            return
        }

        // Set loading state
        isPromptProcessing = true
        let originalPlaceholder = promptInputField.placeholderString
        promptInputField.stringValue = ""
        promptInputField.placeholderString = "Thinking..."
        promptInputField.isEnabled = false
        promptSendButton.isEnabled = false
        
        // Animate send icon to loading spinner
        promptSendIcon.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Loading")
        startPromptLoadingAnimation()

        // Add user message to timeline
        addVoiceMessage(type: .question, content: prompt, topic: nil)

        // Create streaming answer container
        addStreamingMessage(type: .answer, topic: nil)
        streamingContent = ""

        // Process with Claude using chatWithTools
        Task {
            let client = AnthropicClient(apiKey: anthropicKey)

            // Build user context from OAuth data
            var userContext = ""
            let displayName = DataSourceConfig.shared.getValue(for: .confluence, field: "userDisplayName")
            let email = DataSourceConfig.shared.getValue(for: .confluence, field: "userEmail")

            if let displayName = displayName {
                userContext = "\nCONNECTED USER: \(displayName)\(email.map { " (\($0))" } ?? "")\n"
            } else if let email = email {
                userContext = "\nCONNECTED USER: \(email)\n"
            }

            // Get conversation history for context
            let conversationHistory = conversationContext.getFullConversation()
            let historyContext = conversationHistory.isEmpty ? "" : """

            CONVERSATION SO FAR:
            \(conversationHistory)
            """

            // Build system prompt
            let systemPrompt = """
            You are a fast, action-oriented assistant with access to work tools.
            \(userContext)
            TOOL ROUTING (use immediately, don't ask):
            • Ticket key (PROJ-123) → search_jira (returns full ticket details)
            • Sprint/my tickets/work items → search_jira
            • Docs/process/how-to → search_documentation
            • Code/PRs/issues → search_codebase (detects "PR", "issue", "bug" keywords)
            • External info → web_search (last resort)

            MULTI-TOOL STRATEGY:
            • Use MULTIPLE tools when helpful (e.g., Jira + GitHub for feature status)
            • Cross-reference: ticket mentions code? search_codebase too
            • If first tool returns nothing, try another before giving up

            RESPONSE RULES:
            1. NEVER ask clarifying questions - search with reasonable defaults
            2. ALWAYS include clickable URLs from results
            3. Be concise: 3-5 bullet points, cite sources
            4. When user says "it"/"that", check CONVERSATION SO FAR
            \(historyContext)
            Tech stack: \(AppSettings.shared.techStack.displayName)
            """

            // Use chatWithTools for tool support
            let configuredTools = ToolExecutor.shared.configuredToolDefinitions

            let result = await client.chatWithTools(
                question: prompt,
                tools: configuredTools,
                systemPrompt: systemPrompt,
                conversationHistory: self.chatHistory,  // Pass multi-turn history
                onToolUse: { [weak self] toolName in
                    DispatchQueue.main.async {
                        let icon = ToolExecutor.shared.icon(for: toolName)
                        let displayName = ToolExecutor.shared.displayName(for: toolName)
                        // Update streaming status instead of adding separate message
                        self?.updateStreamingStatus("\(icon) Searching \(displayName)...")
                    }
                },
                onChunk: { [weak self] chunk in
                    DispatchQueue.main.async {
                        self?.streamingContent += chunk
                        if let content = self?.streamingContent {
                            self?.updateStreamingMessage(content)
                        }
                    }
                }
            )

            // Handle result
            await MainActor.run { [weak self] in
                guard let self = self else { return }

                switch result {
                case .success(let answer):
                    // Add to multi-turn chat history (native Claude format)
                    self.chatHistory.addUser(prompt)
                    self.chatHistory.addAssistant(answer)
                    // Also add to legacy context for other flows
                    self.conversationContext.addUtterance(text: prompt, topic: nil, isQuestion: true)
                    self.conversationContext.addUtterance(text: answer, topic: nil, isQuestion: false)
                    self.finalizeStreamingMessage(answer)
                case .failure(let error):
                    self.finalizeStreamingMessage("Error: \(error.localizedDescription)")
                }

                // Reset loading state
                self.isPromptProcessing = false
                self.promptInputField.placeholderString = originalPlaceholder
                self.promptInputField.isEnabled = true
                self.promptSendButton.isEnabled = true
                self.stopPromptLoadingAnimation()
                self.promptSendIcon.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
            }
        }
    }
    
    private func startPromptLoadingAnimation() {
        // Rotate the loading icon
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        promptSendIcon.layer?.add(rotation, forKey: "loadingRotation")
    }
    
    private func stopPromptLoadingAnimation() {
        promptSendIcon.layer?.removeAnimation(forKey: "loadingRotation")
    }

    // MARK: - Direct Question (Ask Button)

    @objc func toggleDirectQuestion() {
        if isAskingDirectQuestion {
            cancelDirectQuestion()
        } else {
            startDirectQuestion()
        }
    }

    func startDirectQuestion() {
        // Check for Groq API key
        guard groqApiKey != nil else {
            promptForGroqApiKey()
            return
        }

        // Check for Anthropic API key
        guard apiKey != nil else {
            showAlert(title: "API Key Required", message: "Please configure your Anthropic API key in Settings (⌘,)")
            return
        }

        isAskingDirectQuestion = true

        // Update UI to active state
        updateAskButtonState(active: true)

        // Add status message
        addVoiceMessage(type: .status, content: "Listening to you...", topic: nil)

        // Use Task to handle async operations properly
        Task { @MainActor in
            // Pause system audio capture if session is active
            if isSessionActive {
                await systemAudioCapture?.stopCapturing()
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }

            // Initialize mic recorder with VAD timeout for direct questions
            directQuestionRecorder = VADAudioRecorder()
            directQuestionRecorder?.silenceTimeout = 0.8  // Quick response for questions

            // Set up callbacks
            directQuestionRecorder?.onLevelUpdate = { [weak self] db, isSpeaking in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let intensity = max(0, min(1, (db + 50) / 40))
                    self.pulseAskButton(intensity: CGFloat(intensity), isSpeaking: isSpeaking)
                }
            }

            directQuestionRecorder?.onStatusChange = { _ in }

            directQuestionRecorder?.onSpeechSegment = { [weak self] audioData in
                guard let self = self else { return }
                self.processDirectQuestion(audioData)
            }

            // Start listening
            do {
                guard let recorder = directQuestionRecorder else {
                    cancelDirectQuestion()
                    return
                }
                try recorder.startListening()
            } catch {
                cancelDirectQuestion()
            }
        }
    }

    func processDirectQuestion(_ audioData: Data) {
        // Stop recording immediately
        directQuestionRecorder?.stopListening()

        // Update UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateAskButtonState(active: false, processing: true)
        }

        // Transcribe with Groq
        Task {
            guard let groqKey = groqApiKey else { return }
            let groq = GroqSpeechClient(apiKey: groqKey)

            do {
                let transcribeResult = try await groq.transcribe(audioData: audioData)
                let transcription = transcribeResult.text

                // Skip empty or very short transcriptions
                guard transcription.count > 3 else {
                    await MainActor.run {
                        self.addVoiceMessage(type: .status, content: "No question detected", topic: nil)
                        self.finishDirectQuestion()
                    }
                    return
                }

                await MainActor.run {
                    // Add the question to timeline (marked as from microphone)
                    self.addVoiceMessage(type: .question, content: transcription, topic: nil, audioSource: .microphone)

                    // Create streaming answer container
                    self.addStreamingMessage(type: .answer, topic: nil)
                    self.streamingContent = ""
                }

                // Process with Claude using chatWithTools for tool-supported answers
                guard let anthropicKey = self.apiKey else { return }
                let client = AnthropicClient(apiKey: anthropicKey)

                // Build system prompt for direct questions
                let systemPrompt = """
                You are a helpful assistant answering direct questions from the user.
                Be concise but thorough. Use the available tools to search for relevant information if needed.
                Tech stack context: \(AppSettings.shared.techStack.displayName)
                """

                // Use chatWithTools for Q&A with tool support
                let configuredTools = ToolExecutor.shared.configuredToolDefinitions
                let result = await client.chatWithTools(
                    question: transcription,
                    tools: configuredTools,
                    systemPrompt: systemPrompt,
                    onToolUse: { [weak self] toolName in
                        DispatchQueue.main.async {
                            let icon = ToolExecutor.shared.icon(for: toolName)
                            let displayName = ToolExecutor.shared.displayName(for: toolName)
                            // Update streaming status instead of adding separate message
                            self?.updateStreamingStatus("\(icon) Searching \(displayName)...")
                        }
                    },
                    onChunk: { [weak self] chunk in
                        DispatchQueue.main.async {
                            self?.streamingContent += chunk
                            if let content = self?.streamingContent {
                                self?.updateStreamingMessage(content)
                            }
                        }
                    }
                )

                await MainActor.run {
                    self.hideLoading()
                    switch result {
                    case .success(let answer):
                        self.finalizeStreamingMessage(answer)
                    case .failure(let error):
                        self.addVoiceMessage(type: .status, content: "Error: \(error.localizedDescription)", topic: nil)
                    }
                }

            } catch {
                await MainActor.run {
                    self.hideLoading()
                    self.addVoiceMessage(type: .status, content: "Failed to process: \(error.localizedDescription)", topic: nil)
                }
            }

            // Finish and resume
            await MainActor.run {
                self.finishDirectQuestion()
            }
        }
    }

    func cancelDirectQuestion() {
        directQuestionRecorder?.stopListening()
        finishDirectQuestion()
        addVoiceMessage(type: .status, content: "Question cancelled", topic: nil)
    }

    func finishDirectQuestion() {
        directQuestionRecorder = nil
        isAskingDirectQuestion = false

        // Reset button state
        updateAskButtonState(active: false, processing: false)

        // Resume system audio capture if session was active
        if isSessionActive {
            Task {
                try? await systemAudioCapture?.startCapturing()
            }
        }
    }

    func updateAskButtonState(active: Bool, processing: Bool = false) {
        let baseColor: NSColor
        let iconName: String
        let iconColor: NSColor

        if processing {
            // Processing state - purple tint
            baseColor = NSColor.systemPurple
            iconName = "ellipsis"
            iconColor = .white
        } else if active {
            // Active listening state - orange/recording tint
            baseColor = NSColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
            iconName = "mic.fill"
            iconColor = .white
        } else {
            // Idle state
            baseColor = NSColor.white.withAlphaComponent(0.08)
            iconName = "mic.fill"
            iconColor = NSColor.white.withAlphaComponent(0.9)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            askButtonInner.backgroundColor = baseColor.cgColor
            if active || processing {
                askButtonInner.borderColor = baseColor.withAlphaComponent(0.5).cgColor
            } else {
                askButtonInner.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            }
        }

        askIconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: active ? "Listening" : "Ask")
        askIconView.contentTintColor = iconColor
    }

    func pulseAskButton(intensity: CGFloat, isSpeaking: Bool) {
        guard isAskingDirectQuestion else { return }

        let scale = 1.0 + (intensity * 0.1)  // Subtle pulse
        let brightness = 0.3 + (intensity * 0.4)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05
            // Pulse the mic button
            voiceBarMicButton.animator().layer?.transform = CATransform3DMakeScale(scale, scale, 1.0)
            voiceBarMicButton.layer?.backgroundColor = NSColor(red: 0.3, green: 1.0, blue: brightness, alpha: 0.3).cgColor
            // Update mic icon color intensity
            voiceBarMicIcon.animator().contentTintColor = NSColor.appleGreen.withAlphaComponent(0.5 + intensity * 0.5)
        }
    }

    /// Pulse the voice bar based on system audio levels (animates waveform bars)
    func pulseSpeakerIcon(isSpeaking: Bool, db: Float) {
        guard isSessionActive, isVoiceBarExpanded else { return }

        // Animate waveform bars - this is the main audio visualization in the new design
        animateWaveform(bars: voiceBarWaveformBars, color: .white, isSpeaking: isSpeaking, db: db)
    }

    /// Pulse the mic icon based on user's microphone audio levels
    func pulseMicIcon(isSpeaking: Bool, db: Float) {
        guard isSessionActive else { return }
        guard !isAskingDirectQuestion else { return }  // Don't interfere with push-to-talk animation

        let normalizedDb = max(0, min(1, (db + 60) / 40))
        let intensity = CGFloat(normalizedDb)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = isSpeaking ? 0.05 : 0.2

            if isSpeaking {
                // Pulse effect when user speaks
                let scale = 1.0 + (intensity * 0.08)
                voiceBarMicButton.animator().layer?.transform = CATransform3DMakeScale(scale, scale, 1.0)
                voiceBarMicButton.layer?.backgroundColor = NSColor.appleGreen.withAlphaComponent(0.15 + intensity * 0.2).cgColor
                voiceBarMicIcon.animator().contentTintColor = NSColor.appleGreen.withAlphaComponent(0.6 + intensity * 0.4)
            } else {
                // Return to idle state
                voiceBarMicButton.animator().layer?.transform = CATransform3DIdentity
                voiceBarMicButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
                voiceBarMicIcon.animator().contentTintColor = NSColor.appleGreen.withAlphaComponent(0.9)
            }
        }
    }

    // MARK: - Settings Dropdowns

    @objc func languageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < AppLanguage.allCases.count else { return }
        AppSettings.shared.language = AppLanguage.allCases[index]
        NSLog("🌐 Language changed to: \(AppSettings.shared.language.displayName)")
    }

    @objc func techStackChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < TechStack.allCases.count else { return }
        AppSettings.shared.techStack = TechStack.allCases[index]
        NSLog("💻 Tech stack changed to: \(AppSettings.shared.techStack.displayName)")
    }

    // MARK: - Export Session

    @objc func exportSession() {
        // Filter to only questions, answers, and followups (user responses disabled)
        let exportableMessages = voiceMessages.filter { msg in
            switch msg.type {
            case .question, .answer, .followUp:
                return true
            case .userResponse:  // DISABLED: User voice responses
                return false
            case .status, .screenshot, .toolUse, .source:
                return false
            }
        }

        guard !exportableMessages.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Nothing to Export"
            alert.informativeText = "Start a session and have some Q&A before exporting."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Format the export
        var markdown = "# Session Transcript\n\n"
        markdown += "**Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n"
        markdown += "**Tech Stack:** \(AppSettings.shared.techStack.displayName)\n\n"
        markdown += "**Legend:**\n"
        markdown += "- <span style=\"color: #E74C3C\">🎙️ **Speaker**</span> - Questions from the speaker\n"
        markdown += "- <span style=\"color: #27AE60\">💡 **Suggested Answer**</span> - AI-generated answer hints\n\n"
        markdown += "---\n\n"

        var currentTopic: String? = nil

        for msg in exportableMessages {
            // Add topic header if changed
            if let topic = msg.topic, topic != currentTopic, topic != "unknown" {
                markdown += "## \(topic.capitalized)\n\n"
                currentTopic = topic
            }

            let time = msg.displayTime
            switch msg.type {
            case .question:
                // Red/coral for speaker
                markdown += "### <span style=\"color: #E74C3C\">🎙️ Speaker</span> <small>(\(time))</small>\n\n"
                markdown += "> \(msg.content)\n\n"
            case .answer, .followUp:
                // Green for AI suggested answer
                markdown += "### <span style=\"color: #27AE60\">💡 Suggested Answer</span>\n\n"
                markdown += "\(msg.content)\n\n"
            // DISABLED: User voice responses
            // case .userResponse:
            //     let cleanedContent = cleanUserResponse(msg.content)
            //     guard !cleanedContent.isEmpty else { continue }
            //     markdown += "### <span style=\"color: #3498DB\">🗣️ Your Response</span> <small>(\(time))</small>\n\n"
            //     markdown += "\(cleanedContent)\n\n"
            default:
                break
            }
        }

        markdown += "---\n\n*Exported from Conversation Assistant*\n"

        // Show save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Session"
        savePanel.nameFieldStringValue = "session_\(formattedDateForFilename()).md"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: Date())
    }

    /// Clean up hallucinations from the start of user responses
    private func cleanUserResponse(_ text: String) -> String {
        var cleaned = text

        // Remove leading non-ASCII garbage (replacement chars, random unicode)
        while let first = cleaned.unicodeScalars.first, !first.isASCII || first.value < 32 {
            cleaned = String(cleaned.dropFirst())
        }

        // Common hallucination prefixes to remove
        let hallucationPrefixes = [
            "tabii,", "tabii", "tabibi", "merci beaucoup", "merci", "gracias",
            "thank you for watching", "thanks for watching", "subscribe",
            "reunited with", "accidental", "nexus,", "nexus"
        ]

        let lowerCleaned = cleaned.lowercased()
        for prefix in hallucationPrefixes {
            if lowerCleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // If starts with lowercase gibberish followed by actual content with capital letter,
        // try to find where real content starts (look for capital after space)
        if let firstChar = cleaned.first, firstChar.isLowercase {
            // Look for pattern: gibberish + space + Capital (start of real sentence)
            let words = cleaned.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            for (index, word) in words.enumerated() {
                if let first = word.first, first.isUppercase && index > 0 {
                    // Check if this looks like a real word (not just "You" alone)
                    let restOfSentence = words[index...].joined(separator: " ")
                    if restOfSentence.count > 10 {
                        cleaned = restOfSentence
                        break
                    }
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Loading Indicator

    func showLoading(_ text: String = "", color: NSColor = .systemCyan) {
        DispatchQueue.main.async {
            self.startTypingDotsAnimation()

            // Also show on floating window if visible
            if self.floatingSolutionWindow != nil {
                self.showFloatingLoading()
            }
        }
    }

    func hideLoading() {
        DispatchQueue.main.async {
            self.stopTypingDotsAnimation()

            // Also hide on floating window
            self.hideFloatingLoading()
        }
    }

    /// Animate waveform bars based on speaking state and dB level
    /// Supports both old 5-bar layout and new 25-bar voice bar design
    func animateWaveform(bars: [NSView], color: NSColor, isSpeaking: Bool, db: Float) {
        // Only animate if voice bar is expanded (or using legacy 5-bar setup)
        guard isVoiceBarExpanded || bars.count <= 5 else { return }

        let barMaxHeight: CGFloat = bars.count > 5 ? 20 : 14  // Taller bars for new design
        let barMinHeight: CGFloat = bars.count > 5 ? 4 : 3
        let barCount = bars.count

        // When speaking, animate bars to varying heights based on volume
        // When silent, shrink all bars to minimum with wave pattern
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isSpeaking ? 0.05 : 0.2  // Faster response for new design
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            for (index, bar) in bars.enumerated() {
                var targetHeight: CGFloat
                var alpha: CGFloat

                // Calculate wave multiplier based on position (center bars taller)
                let normalizedPos = abs(CGFloat(index) - CGFloat(barCount) / 2) / (CGFloat(barCount) / 2)
                let waveMultiplier = 0.5 + 0.5 * (1 - normalizedPos)  // 0.5 at edges, 1.0 at center

                if isSpeaking {
                    // Map dB to height: -60dB = min, -20dB = max
                    let normalizedDb = max(0, min(1, (db + 60) / 40))
                    // Add organic variation per bar with slight position-based offset
                    let phaseOffset = sin(Double(index) * 0.5 + CACurrentMediaTime() * 3) * 0.15
                    let variation = CGFloat(0.7 + 0.3 * CGFloat.random(in: 0...1) + phaseOffset)
                    let baseHeight = barMinHeight + (barMaxHeight - barMinHeight) * CGFloat(normalizedDb)
                    targetHeight = baseHeight * waveMultiplier * variation
                    targetHeight = max(barMinHeight, min(barMaxHeight, targetHeight))
                    alpha = 0.5 + CGFloat(normalizedDb) * 0.5
                } else {
                    // Resting state with gentle wave pattern
                    targetHeight = barMinHeight + (barMaxHeight - barMinHeight) * 0.25 * waveMultiplier
                    alpha = 0.4
                }

                // Update bar frame (animate height from center)
                var frame = bar.frame
                let centerY = frame.midY
                frame.size.height = targetHeight
                frame.origin.y = centerY - targetHeight / 2
                bar.animator().frame = frame

                // Update color with smooth transition (white/gray for new design)
                let barColor = bars.count > 5 ? NSColor.white : color
                bar.animator().layer?.backgroundColor = barColor.withAlphaComponent(alpha).cgColor
            }
        }
    }

    /// Start typing dots animation - iMessage style bounce
    func startTypingDotsAnimation() {
        typingDotsView.isHidden = false

        for (index, dot) in typingDots.enumerated() {
            dot.removeAllAnimations()

            // Bounce animation
            let bounce = CAKeyframeAnimation(keyPath: "transform.translateY")
            bounce.values = [0, -6, 0]
            bounce.keyTimes = [0, 0.4, 1.0]
            bounce.duration = 0.5
            bounce.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            bounce.repeatCount = .infinity
            bounce.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn)
            ]

            // Opacity pulse for extra polish
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.4, 1.0, 0.4]
            opacity.keyTimes = [0, 0.4, 1.0]
            opacity.duration = 0.5
            opacity.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            opacity.repeatCount = .infinity

            dot.add(bounce, forKey: "bounce")
            dot.add(opacity, forKey: "opacity")
        }
    }

    /// Stop typing dots animation
    func stopTypingDotsAnimation() {
        for dot in typingDots {
            dot.removeAllAnimations()
            dot.opacity = 1.0
        }
        typingDotsView.isHidden = true
    }

    /// Set loading indicator to inactive state (not used for spinning arc)
    func setWaveformInactiveState() {
        // No-op for spinning arc - just hide when not loading
    }

    // MARK: - Nest Button Animation

    /// Update voice bar state - expands/collapses with animation
    func updateNestButtonState(recording: Bool) {
        isVoiceBarExpanded = recording

        if recording {
            // === EXPAND VOICE BAR ===
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                // Expand container width
                var containerFrame = voiceBarContainer.frame
                containerFrame.size.width = voiceBarExpandedWidth
                voiceBarContainer.animator().frame = containerFrame

                // Expand background layer
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.35)
                voiceBarInner.frame = CGRect(x: 0, y: 0, width: voiceBarExpandedWidth, height: voiceBarContainer.frame.height)
                voiceBarInner.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
                CATransaction.commit()

                // Expand click area
                var toggleFrame = voiceToggleButton.frame
                toggleFrame.size.width = voiceBarExpandedWidth
                voiceToggleButton.animator().frame = toggleFrame

                // Hide collapsed state elements
                nestIconView.animator().alphaValue = 0
                voiceBarLabel.animator().alphaValue = 0

                // Show expanded state elements
                voiceBarMicButton.animator().alphaValue = 1
                voiceBarMicClickArea.animator().alphaValue = 1
                voiceBarSendButton.animator().alphaValue = 1
                voiceBarSendClickArea.animator().alphaValue = 1

                // Show waveform bars with staggered fade
                for (index, bar) in voiceBarWaveformBars.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.012) {
                        NSAnimationContext.runAnimationGroup { innerContext in
                            innerContext.duration = 0.15
                            bar.animator().alphaValue = 1
                        }
                    }
                }
            }
        } else {
            // === COLLAPSE VOICE BAR ===
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                // Collapse container width
                var containerFrame = voiceBarContainer.frame
                containerFrame.size.width = voiceBarCollapsedWidth
                voiceBarContainer.animator().frame = containerFrame

                // Collapse background layer
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                voiceBarInner.frame = CGRect(x: 0, y: 0, width: voiceBarCollapsedWidth, height: voiceBarContainer.frame.height)
                voiceBarInner.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
                CATransaction.commit()

                // Collapse click area
                var toggleFrame = voiceToggleButton.frame
                toggleFrame.size.width = voiceBarCollapsedWidth
                voiceToggleButton.animator().frame = toggleFrame

                // Show collapsed state elements
                nestIconView.animator().alphaValue = 1
                voiceBarLabel.animator().alphaValue = 1

                // Reset to idle visuals
                nestIconView.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Voice")
                nestIconView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
                voiceBarLabel.stringValue = "Start"
                voiceBarLabel.textColor = NSColor.white.withAlphaComponent(0.95)

                // Hide expanded state elements
                voiceBarMicButton.animator().alphaValue = 0
                voiceBarMicClickArea.animator().alphaValue = 0
                voiceBarSendButton.animator().alphaValue = 0
                voiceBarSendClickArea.animator().alphaValue = 0

                // Hide waveform bars
                for bar in voiceBarWaveformBars {
                    bar.animator().alphaValue = 0
                }
            }
        }
    }

    func clearTimeline() {
        voiceMessages.removeAll()
        for subview in voiceTimelineContainer.subviews {
            subview.removeFromSuperview()
        }
    }

    func promptForGroqApiKey() {
        let alert = NSAlert()
        alert.messageText = "Groq API Key Required"
        alert.informativeText = "Please configure your Groq API key in Settings to use voice transcription.\n\nYou can get a key at console.groq.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            showSettings()
        }
    }

    // MARK: - Deduplication helpers

    /// Jaccard similarity between two strings (word-level)
    func stringSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map { String($0) })
        let wordsB = Set(b.lowercased().split(separator: " ").map { String($0) })
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    /// Check if transcription is duplicate (similar text within time window)
    func isDuplicateTranscription(_ text: String, source: AudioSource) -> Bool {
        let now = Date()
        // Clean old entries
        recentTranscriptions.removeAll { now.timeIntervalSince($0.timestamp) > dedupeWindow }

        // Check similarity with recent transcriptions
        for recent in recentTranscriptions {
            let similarity = stringSimilarity(text, recent.text)
            if similarity > similarityThreshold {
                // Don't dedupe if new text is significantly longer (more complete)
                let lengthRatio = Double(text.count) / Double(max(recent.text.count, 1))
                if lengthRatio > 1.3 { continue }
                return true  // Skip duplicate
            }
        }

        recentTranscriptions.append((text, now, source))
        return false
    }

    func processAudioSegment(_ audioData: Data, source: AudioSource) {
        guard let client = groqClient else { return }

        Task {
            do {
                await MainActor.run { showLoading("🎙️ Transcribing...", color: .systemBlue) }
                let (transcription, sttLatency) = try await client.transcribe(audioData: audioData)

                let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    await MainActor.run { hideLoading() }
                    return
                }

                // Skip duplicates
                if isDuplicateTranscription(trimmed, source: source) {
                    await MainActor.run { hideLoading() }
                    return
                }

                // Log transcription (main output)
                let sourceIcon = source == .microphone ? "🎤" : "🔊"
                print("\(sourceIcon) [\(Int(sttLatency))ms] \(trimmed)")

                // Filter Whisper hallucinations (common artifacts from silence/noise)
                // Only filter if it's EXACTLY these phrases (not part of a longer sentence)
                let whisperHallucinations = [
                    // YouTube-style outros
                    "thank you", "thank you for watching", "thank you for listening",
                    "thanks", "thanks for watching", "thanks for listening",
                    "please subscribe", "like and subscribe", "see you next time",
                    "bye", "goodbye", "bye bye", "bye-bye", "take care",
                    "see you", "see you later", "see you soon",
                    // Filler/noise
                    "you", "the end", "so", "okay", "ok", "right",
                    "hmm", "hm", "um", "uh", "ah", "oh", "mhm", "uh-huh",
                    // Media artifacts
                    "music", "applause", "laughter", "silence", "crickets",
                    "[music]", "[applause]", "[laughter]", "[silence]",
                    "(music)", "(applause)", "(laughter)", "(silence)",
                    // Attribution
                    "subtitles by", "captions by", "translated by",
                    // German hallucinations
                    "danke", "danke fürs zuschauen", "abonnieren", "abonniert", "tschüss", "auf wiedersehen", "bis bald",
                    // Spanish hallucinations
                    "gracias", "gracias por ver", "suscríbete", "suscribirse", "adiós", "hasta luego", "hasta pronto",
                    // French hallucinations
                    "merci", "merci d'avoir regardé", "abonnez-vous", "s'abonner", "au revoir", "à bientôt", "salut",
                    // Italian hallucinations
                    "grazie", "grazie per la visione", "iscriviti", "iscrivetevi", "ciao", "arrivederci", "a presto",
                    // Portuguese hallucinations
                    "obrigado", "obrigada", "inscreva-se", "se inscreva", "tchau", "adeus", "até logo", "até mais",
                    // Bulgarian hallucinations
                    "благодаря", "благодаря ви", "абонирайте се", "абонирай се", "харесайте", "довиждане", "чао",
                    // Russian hallucinations
                    "спасибо", "спасибо за просмотр", "подписывайтесь", "подпишитесь", "пока", "до свидания", "до скорого",
                    // Chinese hallucinations (Mandarin pinyin + characters)
                    "谢谢", "谢谢观看", "订阅", "请订阅", "再见", "拜拜",
                    "xièxiè", "dìngyuè", "zàijiàn",
                    // Japanese hallucinations
                    "ありがとう", "ありがとうございます", "チャンネル登録", "登録", "さようなら", "バイバイ", "じゃね",
                    // Korean hallucinations
                    "감사합니다", "구독", "구독해주세요", "좋아요", "안녕", "안녕하세요", "다음에 봐요"
                ]
                let lowerTrimmed = trimmed.lowercased()
                    .replacingOccurrences(of: "!", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                // Filter exact matches (ignoring punctuation)
                if trimmed.count < 30 && whisperHallucinations.contains(where: { lowerTrimmed == $0 }) {
                    await MainActor.run { hideLoading() }
                    return
                }

                // Filter non-ASCII garbage when language is English
                if AppSettings.shared.language == .english {
                    let nonAsciiCount = trimmed.unicodeScalars.filter { !$0.isASCII }.count
                    let nonAsciiRatio = Float(nonAsciiCount) / Float(max(trimmed.count, 1))
                    if nonAsciiRatio > 0.15 && nonAsciiCount > 3 {
                        await MainActor.run { hideLoading() }
                        return
                    }
                }

                // Filter very short transcriptions (likely noise)
                if trimmed.count < 5 && !trimmed.contains("?") {
                    await MainActor.run { hideLoading() }
                    return
                }

                // MICROPHONE = YOUR VOICE → Check for tool-worthy questions
                if source == .microphone {
                    let micToolKeywords = ["jira", "ticket", "sprint", "backlog", "issue", "confluence", "documentation", "wiki", "page", "assigned", "my tickets", "my issues", "what's left", "remaining", "blockers", "playwright"]
                    let micQuestionLower = trimmed.lowercased()
                    let micNeedsTools = micToolKeywords.contains { micQuestionLower.contains($0) } && ToolExecutor.shared.hasConfiguredTools

                    if micNeedsTools {
                        await MainActor.run { [self] in
                            showLoading("🔍 Searching...", color: .systemBlue)
                            addVoiceMessage(type: .question, content: trimmed, topic: "tools", audioSource: .microphone)
                        }

                        // Add to context and call tool-enabled flow
                        conversationContext.addUtterance(text: trimmed, topic: "tools", isQuestion: true)
                        await answerWithToolsForVoice(question: trimmed, topic: "tools", messageType: .question)
                        await MainActor.run { hideLoading() }
                        return
                    }

                    // Not a tool question - just show as user response
                    await MainActor.run { [self] in
                        hideLoading()
                        // DISABLED: User response display in timeline
                        // addUserResponseMessage(content: trimmed, topic: conversationContext.lastTopic)
                    }
                    conversationContext.addUtterance(text: trimmed, topic: conversationContext.lastTopic ?? "unknown")
                    return
                }

                // SYSTEM AUDIO = INTERVIEWER → Classify and potentially generate answer

                // LOCAL PRE-FILTER: Skip API call for obvious fillers/greetings (saves ~800ms)
                let normalizedText = trimmed.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[.!?,']", with: "", options: .regularExpression)

                // Check for greeting patterns (start of utterance)
                let greetingStarts = ["hello", "hi ", "hey ", "good morning", "good afternoon", "good evening", "welcome to"]
                let isGreeting = greetingStarts.contains { normalizedText.hasPrefix($0) }

                // Check for filler/acknowledgment patterns
                let fillerPatterns = ["thank you", "thanks", "yes sure", "yeah sure", "okay", "sure", "sounds good", "got it", "i see", "i understand", "alright"]
                let isFiller = fillerPatterns.contains { normalizedText.hasPrefix($0) || normalizedText == $0 }

                // Check for question indicators - if present, NEVER skip (it's a real question)
                let questionWords = ["what", "how", "why", "when", "where", "which", "who", "can you", "could you", "would you", "tell me", "explain", "describe", "give me", "show me", "walk me"]
                let hasQuestionWord = questionWords.contains { normalizedText.contains($0) }

                // Skip greetings/fillers
                if (isGreeting || isFiller) && normalizedText.count < 50 && !hasQuestionWord {
                    await MainActor.run { hideLoading() }
                    return
                }

                // Skip very short utterances
                if normalizedText.count < 4 {
                    await MainActor.run { hideLoading() }
                    return
                }

                guard let haiku = anthropicClient else {
                    await MainActor.run { hideLoading() }
                    return
                }

                // Buffer incomplete sentences locally
                let textForIncompleteCheck = trimmed.lowercased().trimmingCharacters(in: .whitespaces)
                let incompleteEndings = [" so", " and", " but", " the", " a", " an", " to", " of", " that", " if", " when", " is", " are", " have", " can", " will", " for", " with", " on", " in", ","]
                let endsIncomplete = incompleteEndings.contains { textForIncompleteCheck.hasSuffix($0) }
                let hasQuestionMark = textForIncompleteCheck.contains("?")

                if endsIncomplete && !hasQuestionMark {
                    await MainActor.run {
                        utteranceBuffer = utteranceBuffer.isEmpty ? trimmed : "\(utteranceBuffer) \(trimmed)"
                        bufferTimestamp = Date()
                        hideLoading()
                    }
                    return
                }

                await MainActor.run { showLoading("🔍 Analyzing...", color: .applePurple) }

                // Get context for the combined call
                let userBackground = await MainActor.run { self.textView.string }
                let conversationHistory = conversationContext.getFullConversation()
                let topicsSummary = conversationContext.getTopicsSummary()
                let pinnedSolution = currentPinnedSolution

                // State for handling classification result
                var shouldStreamAnswer = false
                var shouldUseTools = false  // Route to tool-enabled flow instead of Haiku
                var detectedTopic: String = "unknown"
                var messageType: ConversationMessage.MessageType = .answer
                var fullText = ""

                // Tool-worthy keywords - questions about these should use tools
                let toolKeywords = ["jira", "ticket", "sprint", "backlog", "issue", "confluence", "documentation", "wiki", "page", "assigned", "my tickets", "my issues", "what's left", "remaining", "blockers"]

                let startTime = Date()

                let result = await haiku.classifyAndStreamAnswer(
                    transcription: trimmed,
                    buffer: utteranceBuffer,
                    lastTopic: conversationContext.lastTopic,
                    userBackground: userBackground.isEmpty ? nil : userBackground,
                    conversationHistory: conversationHistory,
                    topicsSummary: topicsSummary,
                    pinnedSolution: pinnedSolution,
                    onClassification: { [self] classification in
                        // Log classification result
                        print("→ \(classification.status) | topic: \(classification.topic ?? "unknown")")

                        // Handle filler words
                        if classification.status == "filler" { return }

                        // Override: Comma-ending sentences are incomplete
                        let combinedForCheck = utteranceBuffer.isEmpty ? trimmed : "\(utteranceBuffer) \(trimmed)"
                        let endsWithComma = combinedForCheck.trimmingCharacters(in: .whitespaces).hasSuffix(",")
                        if classification.status == "question" && endsWithComma {
                            utteranceBuffer = combinedForCheck
                            bufferTimestamp = Date()
                            return
                        }

                        // Handle incomplete utterances - buffer them
                        if classification.status == "incomplete" {
                            utteranceBuffer = utteranceBuffer.isEmpty ? trimmed : "\(utteranceBuffer) \(trimmed)"
                            bufferTimestamp = Date()
                            return
                        }

                        // Complete utterance - combine with buffer if any
                        fullText = utteranceBuffer.isEmpty ? trimmed : "\(utteranceBuffer) \(trimmed)"
                        utteranceBuffer = ""
                        detectedTopic = classification.topic ?? "unknown"

                        // System audio classified as "answer" = speaker talking (not a question)
                        if classification.status == "answer" {
                            conversationContext.addUtterance(text: fullText, topic: detectedTopic)
                            return
                        }

                        // Check cooldown
                        if let lastAnswer = lastAnswerTime {
                            let elapsed = Date().timeIntervalSince(lastAnswer)
                            if elapsed < answerCooldown {
                                let isClearQuestion = checkForQuestionMarkers(fullText)
                                if !isClearQuestion {
                                    conversationContext.addUtterance(text: fullText, topic: detectedTopic)
                                    return
                                }
                                let wordCount = fullText.split(separator: " ").count
                                let startsWithContinuation = ["so ", "and ", "then ", "but ", "or "].contains {
                                    fullText.lowercased().hasPrefix($0)
                                }
                                if elapsed < 3.0 && wordCount <= 6 && startsWithContinuation {
                                    conversationContext.addUtterance(text: fullText, topic: detectedTopic)
                                    return
                                }
                            }
                        }

                        // Determine message type based on topic
                        let topicLower = detectedTopic.lowercased()
                        if topicLower == "followup" && conversationContext.lastTopic != nil {
                            messageType = .followUp
                            detectedTopic = conversationContext.lastTopic!
                        } else if topicLower == "followup" && conversationContext.lastTopic == nil {
                            // Orphan follow-up - check if background question
                            let backgroundKeywords = ["experience", "background", "yourself", "projects", "position", "role", "job", "work", "company", "team", "career"]
                            let isLikelyBackground = backgroundKeywords.contains { fullText.lowercased().contains($0) }
                            if !isLikelyBackground { return }
                            detectedTopic = "experience"
                        } else if topicLower == "unknown", let lastTopic = conversationContext.lastTopic {
                            if checkForQuestionMarkers(fullText) {
                                messageType = .followUp
                                detectedTopic = lastTopic
                            } else {
                                return
                            }
                        }

                        // Check if this question needs tools (Jira, Confluence, etc.)
                        let questionLower = fullText.lowercased()
                        let needsTools = toolKeywords.contains { questionLower.contains($0) } && ToolExecutor.shared.hasConfiguredTools

                        if needsTools {
                            shouldUseTools = true
                            shouldStreamAnswer = false
                        } else {
                            shouldStreamAnswer = true
                        }

                        // Update context and UI on main thread
                        DispatchQueue.main.async { [self] in
                            let loadingMsg = needsTools ? "🔍 Searching..." : "💭 Generating answer..."
                            showLoading(loadingMsg, color: needsTools ? .systemBlue : .appleGreen)
                            addVoiceMessage(type: .question, content: fullText, topic: detectedTopic, audioSource: .systemAudio)
                            if !needsTools {
                                streamingContent = ""
                                addStreamingMessage(type: messageType, topic: detectedTopic)
                            }
                        }

                        conversationContext.addUtterance(text: fullText, topic: detectedTopic, isQuestion: true)
                        lastAnswerTime = Date()
                    },
                    onAnswerChunk: { [self] chunk in
                        guard shouldStreamAnswer else { return }
                        DispatchQueue.main.async { [self] in
                            streamingContent += chunk
                            updateStreamingMessage(streamingContent)
                        }
                    }
                )

                let totalLatency = Date().timeIntervalSince(startTime) * 1000

                switch result {
                case .success:
                    if shouldStreamAnswer {
                        print("💡 Answer (Haiku \(Int(totalLatency))ms): \(streamingContent.prefix(100))...")
                        // Add answer to conversation context for follow-up questions
                        conversationContext.addUtterance(text: streamingContent, topic: detectedTopic, isQuestion: false)
                        await MainActor.run { finalizeStreamingMessage(streamingContent) }
                    }
                case .failure:
                    if shouldStreamAnswer {
                        await MainActor.run { updateStreamingMessage("Error processing request") }
                    }
                }

                // If tool-worthy question detected, call tool-enabled flow
                if shouldUseTools && !fullText.isEmpty {
                    await answerWithToolsForVoice(question: fullText, topic: detectedTopic, messageType: messageType)
                }

                await MainActor.run { hideLoading() }

            } catch {
                await MainActor.run {
                    hideLoading()
                    voiceStatusLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reference to current streaming text view for updates
    var currentStreamingTextView: NSTextView?
    var currentStreamingContainer: NSView?
    var streamingContent: String = ""

    /// Generate answer using Haiku with streaming
    func streamAnswerWithHaiku(question: String, topic: String, userBackground: String?, messageType: ConversationMessage.MessageType) async {
        guard let haiku = anthropicClient else { return }

        let backgroundContext = userBackground != nil && !userBackground!.isEmpty ? """
        YOUR BACKGROUND (use for personal questions like "tell me about yourself"):
        \(userBackground!)

        """ : ""

        // Get full conversation history
        let conversationHistory = conversationContext.getFullConversation()
        let topicsSummary = conversationContext.getTopicsSummary()
        let historyContext = conversationHistory.isEmpty ? "" : """

        INTERVIEW SO FAR:
        \(conversationHistory)
        \(topicsSummary)

        """

        // Include pinned coding task solution if available
        let pinnedContext = currentPinnedSolution != nil ? """

        CURRENT CODING TASK SOLUTION (pinned above):
        \(currentPinnedSolution!)

        If the question relates to this solution, answer in context of it.

        """ : ""

        let languageInstruction = AppSettings.shared.llmLanguageInstruction
        let prompt = """
        You are helping someone who is BEING INTERVIEWED for a software engineering position.
        They need quick, glanceable answers to help them respond to the speaker.

        \(backgroundContext)\(historyContext)\(pinnedContext)CURRENT QUESTION: "\(question)"
        Topic: \(topic)

        SPEECH-TO-TEXT: The question text is from voice transcription and may contain errors.
        ALWAYS answer about the Topic shown above. Ignore garbled words.
        Example: "What is key developer?" with Topic: hashmap → Answer about HashMap keys.

        FORBIDDEN PHRASES (never use these):
        - "doesn't exist", "you might mean", "you might be thinking of"
        - "ask them to clarify", "could you clarify", "did you mean"
        - "I think you're asking about", "possible intended question"

        Just answer the topic directly and confidently.

        FORMAT (pick best for quick scanning):
        • Comparisons: X: [brief] | Y: [brief]
        • Definitions: One sentence + 2-3 bullets
        • Code: `command` + one line why

        RULES: MAX 4-5 lines. Bullets only. No fluff. Be direct.\(languageInstruction)
        """

        // Create empty streaming message on main thread
        await MainActor.run {
            streamingContent = ""
            addStreamingMessage(type: messageType, topic: topic)
        }

        // Stream the response
        let result = await haiku.streamTextMessage(prompt: prompt, maxTokens: 250) { [weak self] chunk in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.streamingContent += chunk
                self.updateStreamingMessage(self.streamingContent)
            }
        }

        switch result {
        case .success:
            // Final update with formatting
            await MainActor.run {
                finalizeStreamingMessage(streamingContent)
            }
        case .failure(let error):
            await MainActor.run {
                updateStreamingMessage("Error: \(error.localizedDescription)")
            }
        }
    }

    /// Generate answer using tools to search knowledge sources
    func answerWithTools(question: String, topic: String) async {
        guard let client = anthropicClient else { return }
        
        // Check if any tools are configured
        let configuredTools = ToolExecutor.shared.configuredToolDefinitions
        if configuredTools.isEmpty {
            // Fall back to regular answer without tools
            await streamAnswerWithHaiku(question: question, topic: topic, userBackground: nil, messageType: .answer)
            return
        }
        
        // Build user context from OAuth data
        var userContext = ""
        let displayName = DataSourceConfig.shared.getValue(for: .confluence, field: "userDisplayName")
        let email = DataSourceConfig.shared.getValue(for: .confluence, field: "userEmail")
        let accountId = DataSourceConfig.shared.getValue(for: .confluence, field: "userAccountId")

        if let displayName = displayName {
            userContext = """

            CONNECTED USER: \(displayName)\(email.map { " (\($0))" } ?? "")
            When the user asks for "my tickets", "my issues", or anything personal, use this identity.
            """
        } else if let email = email {
            // Fallback to email if displayName not available
            userContext = """

            CONNECTED USER: \(email)
            When the user asks for "my tickets", "my issues", or anything personal, use this identity.
            """
        }

        // Build system prompt for tool use
        let systemPrompt = """
        You are a fast, action-oriented assistant with access to work tools.
        \(userContext)
        TOOL ROUTING (use immediately, don't ask):
        • Ticket/sprint/work → search_jira (supports "PROJ-123" for direct lookup)
        • Docs/process/how-to → search_documentation
        • Code/PRs/GitHub issues → search_codebase (detects "PR", "issue" keywords)
        • External/library docs → web_search (last resort)

        MULTI-TOOL STRATEGY:
        • Cross-reference: If Jira ticket mentions a feature, also search code/docs
        • Combine results: Give user a complete picture from multiple sources
        • Follow leads: If one tool mentions something, search for it in others

        RESPONSE RULES:
        1. Be concise - 3-5 bullet points max
        2. ALWAYS include clickable URLs from every result (Jira, Confluence, GitHub)
        3. Cite sources: "From Jira:", "From Confluence:", "From GitHub:"
        4. If tool returns nothing, try another before saying "not found"
        """
        
        // Create streaming message on main thread
        await MainActor.run {
            streamingContent = ""
            addStreamingMessage(type: .answer, topic: topic)
        }
        
        let result = await client.chatWithTools(
            question: question,
            tools: configuredTools,
            systemPrompt: systemPrompt,
            onToolUse: { [weak self] toolName in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    // Update streaming status instead of adding separate message
                    let icon = ToolExecutor.shared.icon(for: toolName)
                    let displayName = ToolExecutor.shared.displayName(for: toolName)
                    self.updateStreamingStatus("\(icon) Searching \(displayName)...")
                }
            },
            onChunk: { [weak self] chunk in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.streamingContent += chunk
                    self.updateStreamingMessage(self.streamingContent)
                }
            }
        )
        
        switch result {
        case .success(let answer):
            await MainActor.run {
                finalizeStreamingMessage(answer)
            }
        case .failure(let error):
            await MainActor.run {
                updateStreamingMessage("Error: \(error.localizedDescription)")
            }
        }
    }

    /// Answer voice questions using tools (Jira, Confluence, etc.)
    func answerWithToolsForVoice(question: String, topic: String, messageType: ConversationMessage.MessageType) async {
        guard let anthropicKey = ApiKeyManager.shared.getKey(.anthropic) else { return }

        let client = AnthropicClient(apiKey: anthropicKey)

        // Build user context from OAuth data
        var userContext = ""
        let displayName = DataSourceConfig.shared.getValue(for: .confluence, field: "userDisplayName")
        let email = DataSourceConfig.shared.getValue(for: .confluence, field: "userEmail")

        if let displayName = displayName {
            userContext = "\nCONNECTED USER: \(displayName)\(email.map { " (\($0))" } ?? "")\n"
        }

        // System prompt - conversation history is now passed via native multi-turn
        let systemPrompt = """
        You are a fast, action-oriented assistant with access to work tools.
        \(userContext)
        TOOL ROUTING (use immediately, don't ask):
        • Ticket/sprint/work → search_jira (supports "PROJ-123" for direct lookup)
        • Docs/process/how-to → search_documentation
        • Code/PRs/GitHub issues → search_codebase (detects "PR", "issue" keywords)
        • External/library docs → web_search (last resort)

        MULTI-TOOL STRATEGY:
        • "What's the status of feature X?" → search_jira + search_codebase (find ticket AND related PRs)
        • "How do we deploy X?" → search_documentation + search_jira (find docs AND related tickets)
        • Ticket mentions code? → Also search_codebase for related PRs

        RESPONSE RULES:
        1. Be concise - 3-5 bullet points max
        2. ALWAYS include clickable URLs from results (Jira, Confluence, GitHub)
        3. When user says "it"/"that", check conversation history
        4. If first tool returns nothing useful, try another tool

        Tech stack: \(AppSettings.shared.techStack.displayName)
        """

        // Set up streaming UI
        await MainActor.run { [self] in
            streamingContent = ""
            addStreamingMessage(type: messageType, topic: topic)
        }

        let configuredTools = ToolExecutor.shared.configuredToolDefinitions

        let result = await client.chatWithTools(
            question: question,
            tools: configuredTools,
            systemPrompt: systemPrompt,
            conversationHistory: chatHistory,  // Pass multi-turn history
            onToolUse: { [weak self] (toolName: String) in
                DispatchQueue.main.async {
                    let icon = ToolExecutor.shared.icon(for: toolName)
                    let displayName = ToolExecutor.shared.displayName(for: toolName)
                    self?.updateStreamingStatus("\(icon) Searching \(displayName)...")
                }
            },
            onChunk: { [weak self] (chunk: String) in
                DispatchQueue.main.async {
                    self?.streamingContent += chunk
                    if let content = self?.streamingContent {
                        self?.updateStreamingMessage(content)
                    }
                }
            }
        )

        switch result {
        case .success(let answer):
            // Add to multi-turn chat history (native Claude format)
            chatHistory.addUser(question)
            chatHistory.addAssistant(answer)
            // Also add to legacy context for other flows
            conversationContext.addUtterance(text: question, topic: topic, isQuestion: true)
            conversationContext.addUtterance(text: answer, topic: topic, isQuestion: false)
            await MainActor.run { [self] in
                finalizeStreamingMessage(answer)
            }
        case .failure(let error):
            await MainActor.run { [self] in
                finalizeStreamingMessage("Error: \(error.localizedDescription)")
            }
        }
    }

    /// Add an empty streaming message that will be updated
    func addStreamingMessage(type: ConversationMessage.MessageType, topic: String?) {
        let message = ConversationMessage(type: type, content: "▌", topic: topic)
        voiceMessages.append(message)

        // Layout: A badge indented 20px, card after badge
        let badgeWidth: CGFloat = 22
        let badgeGap: CGFloat = 8
        let answerIndent: CGFloat = 20
        let badgeX: CGFloat = answerIndent
        let cardX: CGFloat = badgeX + badgeWidth + badgeGap
        let cardWidth = voiceTimelineContainer.frame.width - 40 - cardX
        let initialHeight: CGFloat = 80

        // Outer container for badge + card
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: voiceTimelineContainer.frame.width - 40, height: initialHeight))
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
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
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
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.string = ""
        textView.isHidden = true
        textView.identifier = NSUserInterfaceItemIdentifier("streamingText")
        textView.isAutomaticLinkDetectionEnabled = true  // Enable clicking links
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        container.addSubview(textView)

        outerContainer.addSubview(container)

        currentStreamingTextView = textView
        currentStreamingContainer = container

        // Push existing messages up
        let newMessageHeight = initialHeight + 15
        for subview in voiceTimelineContainer.subviews {
            subview.frame.origin.y += newMessageHeight
        }

        outerContainer.frame.origin.y = 10
        voiceTimelineContainer.addSubview(outerContainer)

        // Update container height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
        voiceTimelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// Update the streaming message with new content (with live formatting)
    func updateStreamingMessage(_ content: String) {
        guard let textView = currentStreamingTextView,
              let container = currentStreamingContainer else { return }

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
        let formattedContent = formatMessageContent(content, isQuestion: false)
        let mutableContent = NSMutableAttributedString(attributedString: formattedContent)

        // Add blinking cursor
        let cursorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.appleGreen
        ]
        mutableContent.append(NSAttributedString(string: " ▌", attributes: cursorAttrs))

        textView.textStorage?.setAttributedString(mutableContent)

        // Dynamically resize container as content grows
        let width = container.frame.width - 30
        let newTextHeight = max(40, estimateTextHeight(content, width: width))
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

            // Update icon and labels position
            for subview in container.subviews {
                if subview is NSTextField || subview is NSImageView {
                    if subview.identifier?.rawValue != "streamingText" &&
                       subview.identifier?.rawValue != "streamingSpinner" &&
                       subview.identifier?.rawValue != "streamingLoadingLabel" {
                        subview.frame.origin.y = newContainerHeight - 22
                    }
                }
            }

            // Push other messages up (compare with outer container)
            let outerContainer = container.superview ?? container
            for subview in voiceTimelineContainer.subviews where subview != outerContainer {
                subview.frame.origin.y += heightDiff
            }

            // Update total container height
            var maxY: CGFloat = 0
            for subview in voiceTimelineContainer.subviews {
                maxY = max(maxY, subview.frame.maxY)
            }
            voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
        }
    }

    /// Update the streaming status label (e.g., "Searching Jira...")
    func updateStreamingStatus(_ status: String) {
        guard let container = currentStreamingContainer else { return }
        
        if let loadingLabel = container.subviews.first(where: { $0.identifier?.rawValue == "streamingLoadingLabel" }) as? NSTextField {
            loadingLabel.stringValue = status
        }
    }

    /// Finalize streaming message with proper formatting
    func finalizeStreamingMessage(_ content: String) {
        guard let textView = currentStreamingTextView,
              let container = currentStreamingContainer else { return }

        // Apply formatted text
        let attributedContent = formatMessageContent(content, isQuestion: false)
        textView.textStorage?.setAttributedString(attributedContent)

        // Recalculate height
        let width = container.frame.width - 30
        let newTextHeight = estimateTextHeight(content, width: width)
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

        // Push other messages up if height changed
        if heightDiff > 0 {
            for subview in voiceTimelineContainer.subviews where subview != container {
                subview.frame.origin.y += heightDiff
            }
        }

        // Update container height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)

        // Update the last message in voiceMessages with final content
        if !voiceMessages.isEmpty {
            let lastIndex = voiceMessages.count - 1
            let lastMessage = voiceMessages[lastIndex]
            voiceMessages[lastIndex] = ConversationMessage(type: lastMessage.type, content: content, topic: lastMessage.topic)

            // Update floating window Q&A in real-time
            if floatingSolutionWindow != nil {
                updateFloatingQA()
            }
        }

        // Clean up references
        currentStreamingTextView = nil
        currentStreamingContainer = nil
    }

    func checkForQuestionMarkers(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        let markers = [
            // Universal
            "?",
            // English
            "what is", "what are", "what's", "whats", "what did", "what do",
            "how do", "how does", "how is", "how would", "how can", "how to",
            "why do", "why does", "why is", "why would",
            "can you explain", "could you explain", "can you tell", "could you tell",
            "tell me about", "tell me more",
            "explain ", "describe ",
            "what about", "how about",
            "difference between", "differences between",
            "when do", "when does", "when would", "when should",
            "where do", "where does", "where is",
            "which ", "who ", "whose ",
            // Bulgarian
            "какво", "как", "защо", "кога", "къде", "кой", "коя", "кое", "кои",
            "разкажи", "обясни", "опиши",
            // German
            "was ", "wie ", "warum", "wann", "wo ", "wer ", "welche",
            // French
            "qu'est", "comment", "pourquoi", "quand", "où ", "qui ",
            // Spanish
            "qué ", "cómo", "por qué", "cuándo", "dónde", "quién"
        ]
        return markers.contains { lowerText.contains($0) }
    }

    func addVoiceMessage(type: ConversationMessage.MessageType, content: String, topic: String?, audioSource: AudioSource? = nil) {
        let message = ConversationMessage(type: type, content: content, topic: topic, audioSource: audioSource)
        voiceMessages.append(message)

        // Create message view
        let messageView = createMessageView(for: message)

        // Calculate total height needed for new message
        let newMessageHeight = messageView.frame.height + 15

        // Push all existing messages up to make room for new message at bottom
        for subview in voiceTimelineContainer.subviews {
            subview.frame.origin.y += newMessageHeight
        }

        // Position new message at the bottom
        messageView.frame.origin.y = 10
        voiceTimelineContainer.addSubview(messageView)

        // Calculate total content height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        let newHeight = max(voiceTimelineScrollView.frame.height, maxY + 20)
        voiceTimelineContainer.frame.size.height = newHeight

        // Auto-scroll to bottom (where newest message is)
        voiceTimelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))

        // Update floating window Q&A if visible (real-time sync)
        if floatingSolutionWindow != nil && (type == .question || type == .answer || type == .followUp) {
            updateFloatingQA()
        }
    }

    /// Show a tool use indicator in the timeline
    func showToolStatus(_ toolName: String) {
        let icons: [String: String] = [
            "search_documentation": "📚",
            "search_codebase": "💻",
            "query_database": "🗄️",
            "web_search": "🌐"
        ]
        let displayNames: [String: String] = [
            "search_documentation": "documentation",
            "search_codebase": "codebase",
            "query_database": "database",
            "web_search": "web"
        ]
        let icon = icons[toolName] ?? "🔧"
        let displayName = displayNames[toolName] ?? toolName.replacingOccurrences(of: "_", with: " ")
        let message = "\(icon) Searching \(displayName)..."
        addVoiceMessage(type: .toolUse, content: message, topic: nil)
    }

    /// Show a source citation in the timeline
    func showSourceCitation(title: String, url: String?) {
        var content = title
        if let url = url, !url.isEmpty {
            content = "[\(title)](\(url))"
        }
        addVoiceMessage(type: .source, content: content, topic: nil)
    }

    /// Add a user response message (collapsed by default, expandable)
    func addUserResponseMessage(content: String, topic: String?) {
        var message = ConversationMessage(type: .userResponse, content: content, topic: topic, audioSource: .microphone)
        message.isCollapsed = true
        voiceMessages.append(message)

        // Create collapsed message view
        let messageView = createCollapsedUserResponseView(for: message)

        // Calculate total height needed for new message
        let newMessageHeight = messageView.frame.height + 15

        // Push all existing messages up
        for subview in voiceTimelineContainer.subviews {
            subview.frame.origin.y += newMessageHeight
        }

        // Position new message at bottom
        messageView.frame.origin.y = 10
        voiceTimelineContainer.addSubview(messageView)

        // Update container height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
        voiceTimelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// Create a collapsed user response view (click to expand)
    func createCollapsedUserResponseView(for message: ConversationMessage) -> NSView {
        let width = voiceTimelineContainer.frame.width - 40
        let collapsedHeight: CGFloat = 36

        let container = NSView(frame: NSRect(x: 20, y: 0, width: width, height: collapsedHeight))
        container.wantsLayer = true
        container.identifier = NSUserInterfaceItemIdentifier("userResponse_\(message.id.uuidString)")

        // Blue separator line on left
        let lineView = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: collapsedHeight))
        lineView.wantsLayer = true
        lineView.layer?.backgroundColor = NSColor.systemBlue.cgColor
        container.addSubview(lineView)

        // Time label
        let timeLabel = NSTextField(labelWithString: message.displayTime)
        timeLabel.frame = NSRect(x: 15, y: 10, width: 70, height: 16)
        timeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        container.addSubview(timeLabel)

        // "You said:" label with expand indicator
        let youSaidLabel = NSTextField(labelWithString: "🎤 You said:")
        youSaidLabel.frame = NSRect(x: 90, y: 10, width: 80, height: 16)
        youSaidLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        youSaidLabel.textColor = NSColor.systemBlue
        container.addSubview(youSaidLabel)

        // Preview of content (first ~40 chars)
        let preview = message.content.prefix(40) + (message.content.count > 40 ? "..." : "")
        let previewLabel = NSTextField(labelWithString: String(preview))
        previewLabel.frame = NSRect(x: 175, y: 10, width: width - 230, height: 16)
        previewLabel.font = .systemFont(ofSize: 12, weight: .regular)
        previewLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        previewLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(previewLabel)

        // Expand button
        let expandButton = NSButton(frame: NSRect(x: width - 50, y: 6, width: 40, height: 24))
        expandButton.title = "▶"
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.font = .systemFont(ofSize: 10)
        expandButton.contentTintColor = NSColor.systemBlue
        expandButton.target = self
        expandButton.action = #selector(toggleUserResponseExpand(_:))
        expandButton.identifier = NSUserInterfaceItemIdentifier(message.id.uuidString)
        container.addSubview(expandButton)

        // Store full content in container for expansion
        container.toolTip = message.content

        return container
    }

    @objc func toggleUserResponseExpand(_ sender: NSButton) {
        guard let messageId = sender.identifier?.rawValue,
              let uuid = UUID(uuidString: messageId) else { return }

        // Find the container view
        guard let container = voiceTimelineContainer.subviews.first(where: {
            $0.identifier?.rawValue == "userResponse_\(messageId)"
        }) else { return }

        // Get stored content from tooltip
        let fullContent = container.toolTip ?? ""

        // Check if already expanded
        let isExpanded = container.frame.height > 50

        if isExpanded {
            // Collapse: animate to small height
            let collapsedHeight: CGFloat = 36
            let heightDiff = container.frame.height - collapsedHeight

            // Update button
            sender.title = "▶"

            // Hide content text view if exists
            for subview in container.subviews {
                if subview is NSScrollView {
                    subview.removeFromSuperview()
                }
            }

            // Resize container
            container.frame.size.height = collapsedHeight

            // Move messages below this one down
            for subview in voiceTimelineContainer.subviews where subview.frame.origin.y > container.frame.origin.y {
                subview.frame.origin.y -= heightDiff
            }

            // Update separator line height
            if let lineView = container.subviews.first {
                lineView.frame.size.height = collapsedHeight
            }

        } else {
            // Expand: show full content
            let textHeight = estimateTextHeight(fullContent, width: container.frame.width - 30)
            let expandedHeight = max(60, textHeight + 45)
            let heightDiff = expandedHeight - container.frame.height

            // Update button
            sender.title = "▼"

            // Move messages below this one up to make room
            for subview in voiceTimelineContainer.subviews where subview.frame.origin.y > container.frame.origin.y {
                subview.frame.origin.y += heightDiff
            }

            // Resize container
            container.frame.size.height = expandedHeight

            // Update separator line height
            if let lineView = container.subviews.first {
                lineView.frame.size.height = expandedHeight
            }

            // Add content text view
            let contentScrollView = NSScrollView(frame: NSRect(x: 15, y: 5, width: container.frame.width - 30, height: expandedHeight - 40))
            contentScrollView.hasVerticalScroller = false
            contentScrollView.drawsBackground = false

            let contentView = NSTextView(frame: contentScrollView.bounds)
            contentView.isEditable = false
            contentView.isSelectable = true
            contentView.drawsBackground = false
            contentView.backgroundColor = .clear
            contentView.textContainerInset = .zero
            contentView.string = fullContent
            contentView.font = .systemFont(ofSize: 12)
            contentView.textColor = NSColor.white.withAlphaComponent(0.8)

            contentScrollView.documentView = contentView
            container.addSubview(contentScrollView)
        }

        // Update container height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
    }

    /// Add a screenshot thumbnail to the voice timeline (gallery style - one entry, multiple thumbnails)
    func addScreenshotToTimeline(thumbnail: NSImage, screenshotId: UUID) {
        let message = ConversationMessage(type: .screenshot, content: "Screenshot", topic: nil, screenshotId: screenshotId)
        voiceMessages.append(message)

        let thumbWidth: CGFloat = 80
        let thumbHeight: CGFloat = 50
        let thumbGap: CGFloat = 8

        // Check if screenshot gallery already exists - add to it
        if let existingGallery = voiceTimelineContainer.subviews.first(where: { $0.identifier?.rawValue == "screenshotGallery" }) {
            if let card = existingGallery.subviews.first(where: { $0.identifier?.rawValue == "screenshotCard" }),
               let scrollView = card.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
               let galleryContainer = scrollView.documentView {

                // Count existing thumbnails to position new one
                let existingCount = galleryContainer.subviews.count
                let newX = CGFloat(existingCount) * (thumbWidth + thumbGap)

                // Create new thumbnail button
                let thumbnailButton = NSButton(frame: NSRect(x: newX, y: 0, width: thumbWidth, height: thumbHeight))
                thumbnailButton.image = thumbnail
                thumbnailButton.imageScaling = .scaleProportionallyUpOrDown
                thumbnailButton.isBordered = false
                thumbnailButton.bezelStyle = .rounded
                thumbnailButton.wantsLayer = true
                thumbnailButton.layer?.cornerRadius = 6
                thumbnailButton.layer?.borderWidth = 2
                thumbnailButton.layer?.borderColor = NSColor.applePurple.withAlphaComponent(0.4).cgColor
                thumbnailButton.layer?.masksToBounds = true
                thumbnailButton.target = self
                thumbnailButton.action = #selector(screenshotThumbnailClicked(_:))
                thumbnailButton.identifier = NSUserInterfaceItemIdentifier(screenshotId.uuidString)
                galleryContainer.addSubview(thumbnailButton)

                // Update gallery container width
                galleryContainer.frame.size.width = newX + thumbWidth + thumbGap

                // Update count label
                if let countLabel = card.subviews.first(where: { $0.identifier?.rawValue == "screenshotCount" }) as? NSTextField {
                    countLabel.stringValue = "\(screenshots.count) screenshots"
                }

                // Scroll to show newest thumbnail
                scrollView.contentView.scroll(to: NSPoint(x: max(0, galleryContainer.frame.width - scrollView.frame.width), y: 0))
            }
            return
        }

        // Create new screenshot gallery entry
        let badgeWidth: CGFloat = 22
        let badgeGap: CGFloat = 8
        let cardX: CGFloat = badgeWidth + badgeGap
        let cardWidth = voiceTimelineContainer.frame.width - 40 - cardX
        let containerHeight: CGFloat = 100

        // Outer container to hold badge + card
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: voiceTimelineContainer.frame.width - 40, height: containerHeight))
        outerContainer.identifier = NSUserInterfaceItemIdentifier("screenshotGallery")

        // S Badge - purple pill on the left
        let badge = NSView(frame: NSRect(x: 0, y: containerHeight - 26, width: badgeWidth, height: badgeWidth))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.applePurple.withAlphaComponent(0.15).cgColor
        badge.layer?.cornerRadius = badgeWidth / 2

        let badgeLabel = NSTextField(labelWithString: "S")
        badgeLabel.frame = NSRect(x: 0, y: 3, width: badgeWidth, height: 16)
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = NSColor.applePurple
        badgeLabel.alignment = .center
        badge.addSubview(badgeLabel)
        outerContainer.addSubview(badge)

        // Card container
        let card = NSView(frame: NSRect(x: cardX, y: 0, width: cardWidth, height: containerHeight))
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.applePurple.withAlphaComponent(0.06).cgColor
        card.identifier = NSUserInterfaceItemIdentifier("screenshotCard")
        outerContainer.addSubview(card)

        // Accent bar on left of card
        let accentBar = NSView(frame: NSRect(x: 0, y: 8, width: 3, height: containerHeight - 16))
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = NSColor.applePurple.cgColor
        accentBar.layer?.cornerRadius = 1.5
        card.addSubview(accentBar)

        // Header with icon and count
        let headerIcon = NSImageView(frame: NSRect(x: 15, y: containerHeight - 26, width: 14, height: 14))
        headerIcon.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Screenshot")
        headerIcon.contentTintColor = NSColor.applePurple
        card.addSubview(headerIcon)

        let countLabel = NSTextField(labelWithString: "1 screenshot")
        countLabel.frame = NSRect(x: 34, y: containerHeight - 25, width: 100, height: 14)
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        countLabel.identifier = NSUserInterfaceItemIdentifier("screenshotCount")
        card.addSubview(countLabel)

        // Hint text on right
        let hintLabel = NSTextField(labelWithString: "⌘↩ analyze")
        hintLabel.frame = NSRect(x: cardWidth - 85, y: containerHeight - 25, width: 70, height: 14)
        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        card.addSubview(hintLabel)

        // Horizontal scroll view for thumbnails
        let scrollView = NSScrollView(frame: NSRect(x: 15, y: 10, width: cardWidth - 30, height: thumbHeight + 10))
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        // Gallery container (expands horizontally)
        let galleryContainer = NSView(frame: NSRect(x: 0, y: 0, width: thumbWidth + thumbGap, height: thumbHeight))
        scrollView.documentView = galleryContainer

        // First thumbnail
        let thumbnailButton = NSButton(frame: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        thumbnailButton.image = thumbnail
        thumbnailButton.imageScaling = .scaleProportionallyUpOrDown
        thumbnailButton.isBordered = false
        thumbnailButton.bezelStyle = .rounded
        thumbnailButton.wantsLayer = true
        thumbnailButton.layer?.cornerRadius = 6
        thumbnailButton.layer?.borderWidth = 2
        thumbnailButton.layer?.borderColor = NSColor.applePurple.withAlphaComponent(0.4).cgColor
        thumbnailButton.layer?.masksToBounds = true
        thumbnailButton.target = self
        thumbnailButton.action = #selector(screenshotThumbnailClicked(_:))
        thumbnailButton.identifier = NSUserInterfaceItemIdentifier(screenshotId.uuidString)
        galleryContainer.addSubview(thumbnailButton)

        card.addSubview(scrollView)

        // Push existing messages up
        let newMessageHeight = containerHeight + 15
        for subview in voiceTimelineContainer.subviews {
            subview.frame.origin.y += newMessageHeight
        }

        outerContainer.frame.origin.y = 10
        voiceTimelineContainer.addSubview(outerContainer)

        // Update container height
        var maxY: CGFloat = 0
        for subview in voiceTimelineContainer.subviews {
            maxY = max(maxY, subview.frame.maxY)
        }
        voiceTimelineContainer.frame.size.height = max(voiceTimelineScrollView.frame.height, maxY + 20)
        voiceTimelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    @objc func screenshotThumbnailClicked(_ sender: NSButton) {
        // Trigger analysis when screenshot is clicked
        analyzeScreenshots()
    }

    /// Pin a coding task solution above the timeline
    func setPinnedSolution(_ solution: String) {
        currentPinnedSolution = solution

        // Format solution with markdown rendering
        let attributedSolution = formatMessageContent(solution, isQuestion: false)
        pinnedSolutionTextView.textStorage?.setAttributedString(attributedSolution)

        // Calculate required height based on content
        guard let layoutManager = pinnedSolutionTextView.layoutManager,
              let textContainer = pinnedSolutionTextView.textContainer else { return }

        // Update text container width first
        let halfWidth = voiceContentView.frame.width / 2
        let scrollViewWidth = halfWidth - 25  // Container width - padding
        textContainer.containerSize = NSSize(width: scrollViewWidth - 10, height: CGFloat.greatestFiniteMagnitude)

        // Force complete layout recalculation
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: pinnedSolutionTextView.string.count), actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height + 30

        // Calculate container height (max 50% of voice content view, min 100 for questions below)
        let maxPinnedHeight = voiceContentView.frame.height * 0.5
        let minTimelineHeight: CGFloat = 150  // Minimum space for Q&A
        let availableHeight = voiceContentView.frame.height - 80 - minTimelineHeight  // 80 for control bar

        let pinnedHeight = min(textHeight + 30, min(maxPinnedHeight, availableHeight))  // +30 for header and padding

        // Update container size and position (right half of screen)
        pinnedSolutionContainer.frame = NSRect(
            x: halfWidth,
            y: voiceContentView.frame.height - 65 - pinnedHeight,
            width: halfWidth - 15,
            height: pinnedHeight
        )

        // Update header position (at top of container)
        if let header = pinnedSolutionContainer.viewWithTag(100) {
            header.frame.origin.y = pinnedHeight - 25
        }

        // Update scroll view frame
        pinnedSolutionScrollView.frame = NSRect(
            x: 5,
            y: 5,
            width: pinnedSolutionContainer.frame.width - 10,
            height: pinnedHeight - 35  // Leave room for header
        )

        // Update text view frame to match scroll view content width (height auto-expands)
        pinnedSolutionTextView.frame.size.width = pinnedSolutionScrollView.contentSize.width

        // Timeline stays full width (pinned solution is on right, overlaying)
        // No need to adjust timeline frame

        // Show pinned container
        pinnedSolutionContainer.isHidden = false
    }

    /// Clear the pinned solution and restore timeline
    func clearPinnedSolution() {
        currentPinnedSolution = nil
        pinnedSolutionContainer.isHidden = true
        pinnedSolutionTextView.string = ""

        // Restore timeline to full height
        voiceTimelineScrollView.frame = NSRect(
            x: 15,
            y: 15,
            width: voiceContentView.frame.width - 30,
            height: voiceContentView.frame.height - 80
        )
    }

    func createMessageView(for message: ConversationMessage) -> NSView {
        // Determine styling based on message type
        let isQuestion = message.type == .question
        let isStatus = message.type == .status
        let isScreenshot = message.type == .screenshot
        let isAnswer = message.type == .answer || message.type == .followUp
        let isToolUse = message.type == .toolUse
        let isSource = message.type == .source

        // Layout: badge on left, card after badge, answers indented 20px
        let badgeWidth: CGFloat = 22
        let badgeGap: CGFloat = 8
        let answerIndent: CGFloat = 20

        // Badge position: questions at 0, answers/tool messages indented
        let badgeX: CGFloat = (isAnswer || isToolUse || isSource) ? answerIndent : 0
        // Card starts after badge
        let cardX: CGFloat = badgeX + badgeWidth + badgeGap
        let cardWidth = voiceTimelineContainer.frame.width - 40 - cardX

        // Calculate dimensions
        let headerHeight: CGFloat = 28
        let contentPadding: CGFloat = 12
        let textWidth = cardWidth - 52  // Account for icon and padding
        let textHeight = estimateTextHeight(message.content, width: textWidth)
        let viewHeight = max(textHeight + headerHeight + contentPadding * 2, 60)

        // Outer container to hold badge + card
        let outerContainer = NSView(frame: NSRect(x: 20, y: 0, width: voiceTimelineContainer.frame.width - 40, height: viewHeight))

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
        let bgAlpha: CGFloat

        if isQuestion {
            accentColor = NSColor.appleGold
            symbolName = "mic.fill"
            bgAlpha = 0.06
        } else if isStatus {
            accentColor = NSColor.white.withAlphaComponent(0.5)
            symbolName = "info.circle.fill"
            bgAlpha = 0.03
        } else if isScreenshot {
            accentColor = NSColor.applePurple
            symbolName = "camera.fill"
            bgAlpha = 0.05
        } else if isToolUse {
            // Tool use indicator - uses tool-specific icon from content prefix
            accentColor = NSColor.systemBlue
            // Extract tool icon from content (e.g., "📚 Searching..." -> use magnifyingglass)
            symbolName = "magnifyingglass"
            bgAlpha = 0.04
        } else if isSource {
            // Source/citation - subtle link style
            accentColor = NSColor.systemTeal
            symbolName = "link"
            bgAlpha = 0.03
        } else {
            // Answer, followUp, userResponse all treated as AI response
            accentColor = NSColor.appleGreen
            symbolName = "sparkles"
            bgAlpha = 0.05
        }

        // Card background
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(bgAlpha).cgColor

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

        // Header label only for status/screenshot/toolUse/source (Q/A have badges instead)
        if isStatus || isScreenshot || isToolUse || isSource {
            let headerText: String
            if isStatus {
                headerText = "Status"
            } else if isScreenshot {
                headerText = "Screenshot"
            } else if isToolUse {
                headerText = "Searching"
            } else {
                headerText = "Source"
            }
            let headerLabel = NSTextField(labelWithString: headerText)
            headerLabel.frame = NSRect(x: 32, y: viewHeight - headerHeight + 2, width: 80, height: 18)
            headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            headerLabel.textColor = accentColor
            container.addSubview(headerLabel)
        }

        // Topic badge if present - modern pill style
        let topicX: CGFloat = (isStatus || isScreenshot || isToolUse || isSource) ? 110 : 32
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

        // Time label - right aligned, subtle
        let timeLabel = NSTextField(labelWithString: message.displayTime)
        timeLabel.frame = NSRect(x: cardWidth - 80, y: viewHeight - headerHeight + 2, width: 70, height: 18)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        // Content text
        let contentView = NSTextView(frame: NSRect(x: 12, y: contentPadding, width: textWidth + 28, height: textHeight))
        contentView.isEditable = false
        contentView.isSelectable = true
        contentView.drawsBackground = false
        contentView.backgroundColor = .clear
        contentView.textContainerInset = .zero
        contentView.textContainer?.lineFragmentPadding = 0
        contentView.isAutomaticLinkDetectionEnabled = true  // Enable clicking links
        contentView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]

        let attributedContent = formatMessageContent(message.content, isQuestion: isQuestion)
        contentView.textStorage?.setAttributedString(attributedContent)
        container.addSubview(contentView)

        // Add card to outer container
        outerContainer.addSubview(container)

        return outerContainer
    }

    func formatMessageContent(_ text: String, isQuestion: Bool) -> NSAttributedString {
        let baseFont = isQuestion ? NSFont.systemFont(ofSize: 14, weight: .medium) : NSFont.systemFont(ofSize: 13, weight: .regular)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let codeBgColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)

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

    func formatAnswerLine(_ line: String, baseFont: NSFont, codeFont: NSFont, labelFont: NSFont) -> NSAttributedString {
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
        let bulletPrefixes = ["• ", "- ", "* ", "· "]
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
        let headerPrefixes = ["When to use:", "Use case:", "Tip:", "Note:", "Gotcha:"]
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

    func formatInlineCode(_ text: String, baseAttrs: [NSAttributedString.Key: Any], codeFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Combined pattern for **bold**, `code`, and URLs
        let pattern = "\\*\\*([^*]+)\\*\\*|`([^`]+)`|(https?://[^\\s\\)\\]]+)"

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

            // Check which group matched: group 1 = bold, group 2 = code, group 3 = URL
            if let boldRange = Range(match.range(at: 1), in: text) {
                // **bold** text - yellow and bold
                let boldText = String(text[boldRange])
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
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
            } else if let urlRange = Range(match.range(at: 3), in: text) {
                // URL - make it clickable
                let urlText = String(text[urlRange])
                if let url = URL(string: urlText) {
                    let linkAttrs: [NSAttributedString.Key: Any] = [
                        .font: baseAttrs[.font] ?? NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.systemBlue,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .link: url,
                        .cursor: NSCursor.pointingHand
                    ]
                    result.append(NSAttributedString(string: urlText, attributes: linkAttrs))
                } else {
                    result.append(NSAttributedString(string: urlText, attributes: baseAttrs))
                }
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
        let font = NSFont.systemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(40, ceil(boundingRect.height) + 10)
    }
}

@available(macOS 14.0, *)
@main
struct ConversationAssistantApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = ConversationAssistantDelegate()
        app.delegate = delegate
        app.run()
    }
}
