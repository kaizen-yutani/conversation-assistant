import AppKit

/// Settings window for managing API keys and data sources - visionOS-inspired glassmorphism design
final class SettingsWindowController: NSWindowController {
    
    // Tab views
    private var tabSegmentedControl: NSSegmentedControl!
    private var apiKeysView: NSView!
    private var dataSourcesView: NSView!
    
    // API Keys UI References
    private var anthropicTextField: NSTextField!
    private var groqTextField: NSTextField!
    private var anthropicStatusDot: NSView!
    private var groqStatusDot: NSView!
    private var anthropicStatusLabel: NSTextField!
    private var groqStatusLabel: NSTextField!
    private var anthropicShowButton: NSButton!
    private var groqShowButton: NSButton!
    private var anthropicCard: NSVisualEffectView!
    private var groqCard: NSVisualEffectView!
    
    // Data Sources UI References
    private var dataSourceCards: [DataSourceType: NSVisualEffectView] = [:]
    private var dataSourceTextFields: [String: NSTextField] = [:]
    private var dataSourceToggles: [DataSourceType: NSSwitch] = [:]
    
    // State
    private var isAnthropicVisible = false
    private var isGroqVisible = false
    private var anthropicPlaceholder = ""
    private var groqPlaceholder = ""
    private var currentTab = 0
    
    // Design constants
    private struct Design {
        static let cardCornerRadius: CGFloat = 16
        static let inputCornerRadius: CGFloat = 8
        static let buttonCornerRadius: CGFloat = 10
        static let cardPadding: CGFloat = 16
        static let spacing: CGFloat = 12

        // Colors — new design system
        static let anthropicAccent = NSColor.accentPrimary              // Teal
        static let groqAccent = NSColor.accentSecondary                 // Electric blue
        static let activeGreen = NSColor.accentSuccess                  // Apple green
        static let warningOrange = NSColor.accentWarning                // Amber
        static let cardBorder = NSColor.white.withAlphaComponent(0.15)
        static let inputBackground = NSColor.black.withAlphaComponent(0.2)
    }
    
    static func create() -> SettingsWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .floating  // Ensure window appears on top
        window.hidesOnDeactivate = false  // Don't auto-hide when app loses focus

        let controller = SettingsWindowController(window: window)
        controller.setupUI()
        return controller
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // === GLASSMORPHISM BACKGROUND ===
        let backgroundBlur = NSVisualEffectView(frame: contentView.bounds)
        backgroundBlur.autoresizingMask = [.width, .height]
        backgroundBlur.blendingMode = .behindWindow
        backgroundBlur.material = .hudWindow
        backgroundBlur.state = .active
        backgroundBlur.wantsLayer = true
        backgroundBlur.layer?.cornerRadius = 16
        contentView.addSubview(backgroundBlur)
        
        // === HEADER ===
        let headerY: CGFloat = 460
        
        // Settings icon
        let iconView = NSImageView(frame: NSRect(x: 24, y: headerY, width: 32, height: 32))
        iconView.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        iconView.contentTintColor = .white
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        contentView.addSubview(iconView)
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Settings")
        titleLabel.frame = NSRect(x: 62, y: headerY + 2, width: 200, height: 28)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        contentView.addSubview(titleLabel)
        
        // === API KEYS VIEW (Tab 0) ===
        // Add tab views FIRST so they're behind the segmented control
        apiKeysView = NSView(frame: NSRect(x: 0, y: 70, width: 520, height: 340))
        contentView.addSubview(apiKeysView)
        setupApiKeysTab()

        // === DATA SOURCES VIEW (Tab 1) ===
        dataSourcesView = NSView(frame: NSRect(x: 0, y: 70, width: 520, height: 340))
        dataSourcesView.isHidden = true
        contentView.addSubview(dataSourcesView)
        setupDataSourcesTab()

        // === SEGMENTED TAB CONTROL ===
        // Add AFTER tab views so it's on top and receives clicks
        tabSegmentedControl = NSSegmentedControl(frame: NSRect(x: 24, y: headerY - 40, width: 220, height: 28))
        tabSegmentedControl.segmentCount = 2
        tabSegmentedControl.setLabel("API Keys", forSegment: 0)
        tabSegmentedControl.setLabel("Data Sources", forSegment: 1)
        tabSegmentedControl.setWidth(110, forSegment: 0)
        tabSegmentedControl.setWidth(110, forSegment: 1)
        tabSegmentedControl.trackingMode = .selectOne
        tabSegmentedControl.segmentStyle = .rounded
        tabSegmentedControl.selectedSegment = 0
        tabSegmentedControl.target = self
        tabSegmentedControl.action = #selector(tabChanged(_:))
        contentView.addSubview(tabSegmentedControl)
        
        // === ACTION BUTTONS ===
        let buttonY: CGFloat = 24
        
        // Save button - styled like main app
        let saveButton = createStyledButton(
            title: "Save",
            frame: NSRect(x: 396, y: buttonY, width: 100, height: 36),
            backgroundColor: Design.activeGreen.withAlphaComponent(0.25),
            borderColor: Design.activeGreen.withAlphaComponent(0.5),
            textColor: Design.activeGreen,
            action: #selector(saveSettings)
        )
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
        
        // Cancel button - subtle style
        let cancelButton = createStyledButton(
            title: "Cancel",
            frame: NSRect(x: 286, y: buttonY, width: 100, height: 36),
            backgroundColor: NSColor.white.withAlphaComponent(0.08),
            borderColor: NSColor.white.withAlphaComponent(0.15),
            textColor: NSColor.white.withAlphaComponent(0.8),
            action: #selector(cancelSettings)
        )
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
        
        // Load current values
        loadCurrentKeys()
        loadDataSourceSettings()

        // Listen for OAuth events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOAuthCompleted(_:)),
            name: .oauthCompleted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOAuthFailed(_:)),
            name: .oauthFailed,
            object: nil
        )
    }

    @objc private func handleOAuthCompleted(_ notification: Notification) {
        guard let provider = notification.userInfo?["provider"] as? OAuthProvider else { return }
        // Refresh data sources tab to show updated OAuth status
        switch provider {
        case .atlassian:
            updateDataSourceStatus(.confluence)
        case .github:
            updateDataSourceStatus(.github)
        }
        NSLog("Settings: OAuth completed for \(provider.displayName)")
    }

    @objc private func handleOAuthFailed(_ notification: Notification) {
        guard let provider = notification.userInfo?["provider"] as? OAuthProvider,
              let error = notification.userInfo?["error"] as? String else { return }

        let alert = NSAlert()
        alert.messageText = "OAuth Failed"
        alert.informativeText = "Failed to connect with \(provider.displayName): \(error)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setupApiKeysTab() {
        // Subtitle for API keys
        let subtitleLabel = NSTextField(labelWithString: "Configure your AI service API keys")
        subtitleLabel.frame = NSRect(x: 24, y: 330, width: 400, height: 20)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        apiKeysView.addSubview(subtitleLabel)
        
        // === ANTHROPIC CARD ===
        anthropicPlaceholder = ApiKeyManager.ApiKeyType.anthropic.placeholder
        anthropicCard = createApiKeyCard(
            in: apiKeysView,
            yOffset: 195,
            keyType: .anthropic,
            accentColor: Design.anthropicAccent,
            textFieldRef: &anthropicTextField,
            statusDotRef: &anthropicStatusDot,
            statusLabelRef: &anthropicStatusLabel,
            showButtonRef: &anthropicShowButton,
            showAction: #selector(toggleAnthropicVisibility),
            getKeyAction: #selector(openAnthropicConsole)
        )
        
        // === GROQ CARD ===
        groqPlaceholder = ApiKeyManager.ApiKeyType.groq.placeholder
        groqCard = createApiKeyCard(
            in: apiKeysView,
            yOffset: 80,
            keyType: .groq,
            accentColor: Design.groqAccent,
            textFieldRef: &groqTextField,
            statusDotRef: &groqStatusDot,
            statusLabelRef: &groqStatusLabel,
            showButtonRef: &groqShowButton,
            showAction: #selector(toggleGroqVisibility),
            getKeyAction: #selector(openGroqConsole)
        )
    }
    
    private func setupDataSourcesTab() {
        let leftMargin: CGFloat = 24

        // Subtitle for data sources
        let subtitleLabel = NSTextField(labelWithString: "Configure data source connections")
        subtitleLabel.frame = NSRect(x: leftMargin, y: 300, width: 450, height: 20)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        dataSourcesView.addSubview(subtitleLabel)

        // OAuth hint
        let hintLabel = NSTextField(labelWithString: "💡 Tip: Click Confluence, Jira, or GitHub in the status bar to connect via OAuth")
        hintLabel.frame = NSRect(x: leftMargin, y: 278, width: 470, height: 16)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.systemBlue.withAlphaComponent(0.8)
        dataSourcesView.addSubview(hintLabel)

        // Create scrollable container for data source cards
        let scrollView = NSScrollView(frame: NSRect(x: leftMargin, y: 10, width: 472, height: 260))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        dataSourcesView.addSubview(scrollView)

        let cardSpacing: CGFloat = 10
        let cardHeight: CGFloat = 100  // All cards now same height (no OAuth buttons)

        // Calculate total height
        let totalHeight: CGFloat = CGFloat(DataSourceType.allCases.count) * (cardHeight + cardSpacing) + 10

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 448, height: totalHeight))
        scrollView.documentView = containerView

        // Create cards from bottom to top
        var yOffset: CGFloat = 10
        for sourceType in DataSourceType.allCases.reversed() {
            createDataSourceCard(in: containerView, yOffset: yOffset, sourceType: sourceType)
            yOffset += cardHeight + cardSpacing
        }
    }
    
    private func createDataSourceCard(in containerView: NSView, yOffset: CGFloat, sourceType: DataSourceType) {
        let cardWidth: CGFloat = 448
        let cardHeight: CGFloat = 100  // Standard height for all cards

        // Card container
        let card = NSVisualEffectView(frame: NSRect(x: 0, y: yOffset, width: cardWidth, height: cardHeight))
        card.blendingMode = .withinWindow
        card.material = .popover
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = Design.cardCornerRadius
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Design.cardBorder.cgColor
        card.layer?.masksToBounds = true
        containerView.addSubview(card)
        dataSourceCards[sourceType] = card

        // Accent bar
        let accentColor = colorForDataSource(sourceType)
        let accentBar = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: cardHeight))
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = accentColor.cgColor
        card.addSubview(accentBar)

        // SF Symbol icon instead of emoji
        let iconView = NSImageView(frame: NSRect(x: 14, y: cardHeight - 30, width: 20, height: 20))
        iconView.image = NSImage(systemSymbolName: sfSymbolForDataSource(sourceType), accessibilityDescription: sourceType.displayName)
        iconView.contentTintColor = accentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        card.addSubview(iconView)

        // Name
        let nameLabel = NSTextField(labelWithString: sourceType.displayName)
        nameLabel.frame = NSRect(x: 40, y: cardHeight - 30, width: 120, height: 20)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .white
        card.addSubview(nameLabel)

        // Enable toggle
        let toggle = NSSwitch(frame: NSRect(x: cardWidth - 60, y: cardHeight - 32, width: 40, height: 20))
        toggle.target = self
        toggle.action = #selector(dataSourceToggled(_:))
        toggle.tag = DataSourceType.allCases.firstIndex(of: sourceType) ?? 0
        card.addSubview(toggle)
        dataSourceToggles[sourceType] = toggle

        // Status label
        let statusLabel = NSTextField(labelWithString: DataSourceConfig.shared.configurationStatus(sourceType))
        statusLabel.frame = NSRect(x: cardWidth - 145, y: cardHeight - 28, width: 75, height: 16)
        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        statusLabel.alignment = .right
        statusLabel.identifier = NSUserInterfaceItemIdentifier("status_\(sourceType.rawValue)")
        card.addSubview(statusLabel)

        // For Confluence: Show OAuth status note instead of fields
        if sourceType == .confluence {
            let isOAuthConnected = OAuthManager.shared.isConnected(provider: .atlassian)
            let noteText = isOAuthConnected
                ? "Connected via OAuth (click status bar to manage)"
                : "Click Confluence in status bar to connect"
            let noteLabel = NSTextField(labelWithString: noteText)
            noteLabel.frame = NSRect(x: 14, y: 35, width: cardWidth - 28, height: 20)
            noteLabel.font = .systemFont(ofSize: 11)
            noteLabel.textColor = isOAuthConnected
                ? NSColor.systemGreen.withAlphaComponent(0.8)
                : NSColor.white.withAlphaComponent(0.5)
            card.addSubview(noteLabel)

            if isOAuthConnected {
                let testButton = NSButton(frame: NSRect(x: 14, y: 8, width: 130, height: 22))
                testButton.title = "Test Connection"
                testButton.bezelStyle = .inline
                testButton.isBordered = false
                testButton.font = .systemFont(ofSize: 11, weight: .medium)
                testButton.contentTintColor = accentColor
                testButton.target = self
                testButton.action = #selector(testConfluenceConnection)
                card.addSubview(testButton)
            }
            return  // No manual fields for Confluence
        }

        // For GitHub: Show OAuth status note instead of fields
        if sourceType == .github {
            let isOAuthConnected = OAuthManager.shared.isConnected(provider: .github)
            let noteText = isOAuthConnected
                ? "Connected via OAuth (click status bar to manage)"
                : "Click GitHub in status bar to connect"
            let noteLabel = NSTextField(labelWithString: noteText)
            noteLabel.frame = NSRect(x: 14, y: 35, width: cardWidth - 28, height: 20)
            noteLabel.font = .systemFont(ofSize: 11)
            noteLabel.textColor = isOAuthConnected
                ? NSColor.systemGreen.withAlphaComponent(0.8)
                : NSColor.white.withAlphaComponent(0.5)
            card.addSubview(noteLabel)

            if isOAuthConnected {
                let testButton = NSButton(frame: NSRect(x: 14, y: 8, width: 130, height: 22))
                testButton.title = "Test Connection"
                testButton.bezelStyle = .inline
                testButton.isBordered = false
                testButton.font = .systemFont(ofSize: 11, weight: .medium)
                testButton.contentTintColor = accentColor
                testButton.target = self
                testButton.action = #selector(testGitHubConnection)
                card.addSubview(testButton)
            }
            return  // No manual fields for GitHub - use OAuth
        }

        // Create input fields for required configuration
        var fieldY: CGFloat = 10
        let fields = sourceType.requiredFields.prefix(2) // Show max 2 fields in compact view

        for field in fields.reversed() {
            let fieldKey = "\(sourceType.rawValue).\(field.key)"

            let inputContainer = NSView(frame: NSRect(x: 14, y: fieldY, width: cardWidth - 28, height: 26))
            inputContainer.wantsLayer = true
            inputContainer.layer?.cornerRadius = 6
            inputContainer.layer?.backgroundColor = Design.inputBackground.cgColor
            inputContainer.layer?.borderWidth = 1
            inputContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
            card.addSubview(inputContainer)

            let textField: NSTextField
            if field.isSecret {
                textField = NSSecureTextField(frame: NSRect(x: 8, y: 3, width: inputContainer.frame.width - 16, height: 20))
            } else {
                textField = NSTextField(frame: NSRect(x: 8, y: 3, width: inputContainer.frame.width - 16, height: 20))
            }
            textField.placeholderString = field.placeholder
            textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textField.textColor = .white
            textField.backgroundColor = .clear
            textField.isBordered = false
            textField.focusRingType = .none
            textField.drawsBackground = false
            inputContainer.addSubview(textField)
            dataSourceTextFields[fieldKey] = textField

            fieldY += 30
        }
    }

    private func sfSymbolForDataSource(_ type: DataSourceType) -> String {
        switch type {
        case .confluence: return "book.closed.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder.fill"
        case .webSearch: return "globe"
        }
    }
    
    private func colorForDataSource(_ type: DataSourceType) -> NSColor {
        switch type {
        case .confluence: return NSColor.systemBlue
        case .github: return NSColor.systemPurple
        case .database: return NSColor.systemOrange
        case .webSearch: return NSColor.systemTeal
        }
    }
    
    @objc func tabChanged(_ sender: NSSegmentedControl) {
        currentTab = sender.selectedSegment
        NSLog("🔄 Tab changed to: \(currentTab) - API Keys hidden: \(currentTab != 0), Data Sources hidden: \(currentTab != 1)")

        // Update visibility
        apiKeysView.isHidden = (currentTab != 0)
        dataSourcesView.isHidden = (currentTab != 1)

        // Force layout update
        apiKeysView.needsLayout = true
        dataSourcesView.needsLayout = true
        window?.contentView?.needsLayout = true
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    
    @objc private func dataSourceToggled(_ sender: NSSwitch) {
        guard sender.tag < DataSourceType.allCases.count else { return }
        let sourceType = DataSourceType.allCases[sender.tag]
        DataSourceConfig.shared.setEnabled(sourceType, enabled: sender.state == .on)
        updateDataSourceStatus(sourceType)
    }
    
    private func updateDataSourceStatus(_ sourceType: DataSourceType) {
        guard let card = dataSourceCards[sourceType] else { return }
        let statusLabel = card.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "status_\(sourceType.rawValue)" }
        statusLabel?.stringValue = DataSourceConfig.shared.configurationStatus(sourceType)
    }
    
    private func loadDataSourceSettings() {
        for sourceType in DataSourceType.allCases {
            // Load toggle state
            dataSourceToggles[sourceType]?.state = DataSourceConfig.shared.isEnabled(sourceType) ? .on : .off
            
            // Load field values
            for field in sourceType.requiredFields {
                let fieldKey = "\(sourceType.rawValue).\(field.key)"
                if let textField = dataSourceTextFields[fieldKey],
                   let value = DataSourceConfig.shared.getValue(for: sourceType, field: field.key) {
                    textField.stringValue = value
                }
            }
        }
    }
    
    private func saveDataSourceSettings() {
        for sourceType in DataSourceType.allCases {
            for field in sourceType.requiredFields {
                let fieldKey = "\(sourceType.rawValue).\(field.key)"
                if let textField = dataSourceTextFields[fieldKey] {
                    let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        DataSourceConfig.shared.setValue(for: sourceType, field: field.key, value: value)
                    }
                }
            }
        }
    }
    
    // MARK: - Card Creation
    
    private func createApiKeyCard(
        in contentView: NSView,
        yOffset: CGFloat,
        keyType: ApiKeyManager.ApiKeyType,
        accentColor: NSColor,
        textFieldRef: inout NSTextField!,
        statusDotRef: inout NSView!,
        statusLabelRef: inout NSTextField!,
        showButtonRef: inout NSButton!,
        showAction: Selector,
        getKeyAction: Selector
    ) -> NSVisualEffectView {
        
        let cardWidth: CGFloat = 432
        let cardHeight: CGFloat = 100
        let cardX: CGFloat = 24
        
        // Card container with glassmorphism
        let card = NSVisualEffectView(frame: NSRect(x: cardX, y: yOffset, width: cardWidth, height: cardHeight))
        card.blendingMode = .withinWindow
        card.material = .popover
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = Design.cardCornerRadius
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Design.cardBorder.cgColor
        card.layer?.masksToBounds = true
        contentView.addSubview(card)
        
        // Accent bar on left
        let accentBar = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: cardHeight))
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = accentColor.cgColor
        card.addSubview(accentBar)
        
        // Provider icon
        let icon = keyType == .anthropic ? "sparkles" : "bolt.fill"
        let iconView = NSImageView(frame: NSRect(x: 16, y: cardHeight - 32, width: 20, height: 20))
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: keyType.displayName)
        iconView.contentTintColor = accentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        card.addSubview(iconView)
        
        // Provider name
        let nameLabel = NSTextField(labelWithString: keyType.displayName)
        nameLabel.frame = NSRect(x: 42, y: cardHeight - 34, width: 150, height: 20)
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .white
        card.addSubview(nameLabel)
        
        // Status dot (animated)
        let statusDot = NSView(frame: NSRect(x: cardWidth - 90, y: cardHeight - 30, width: 8, height: 8))
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = Design.warningOrange.cgColor
        card.addSubview(statusDot)
        statusDotRef = statusDot
        
        // Status label
        let statusLabel = NSTextField(labelWithString: "Not configured")
        statusLabel.frame = NSRect(x: cardWidth - 78, y: cardHeight - 33, width: 70, height: 16)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        statusLabel.alignment = .left
        card.addSubview(statusLabel)
        statusLabelRef = statusLabel
        
        // Input field container (for styling)
        let inputContainer = NSView(frame: NSRect(x: 14, y: 32, width: cardWidth - 90, height: 30))
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = Design.inputCornerRadius
        inputContainer.layer?.backgroundColor = Design.inputBackground.cgColor
        inputContainer.layer?.borderWidth = 1
        inputContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.addSubview(inputContainer)
        
        // Text field
        let textField = NSSecureTextField(frame: NSRect(x: 8, y: 4, width: inputContainer.frame.width - 16, height: 22))
        textField.placeholderString = keyType.placeholder
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.drawsBackground = false
        inputContainer.addSubview(textField)
        textFieldRef = textField
        
        // Show/Hide button - minimal style
        let showButton = NSButton(frame: NSRect(x: cardWidth - 70, y: 34, width: 55, height: 26))
        showButton.title = "Show"
        showButton.bezelStyle = .inline
        showButton.isBordered = false
        showButton.font = .systemFont(ofSize: 11, weight: .medium)
        showButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        showButton.target = self
        showButton.action = showAction
        card.addSubview(showButton)
        showButtonRef = showButton
        
        // Get Key link
        let getKeyButton = NSButton(frame: NSRect(x: 14, y: 6, width: 100, height: 20))
        getKeyButton.title = "Get API Key →"
        getKeyButton.bezelStyle = .inline
        getKeyButton.isBordered = false
        getKeyButton.font = .systemFont(ofSize: 11, weight: .medium)
        getKeyButton.contentTintColor = accentColor
        getKeyButton.target = self
        getKeyButton.action = getKeyAction
        card.addSubview(getKeyButton)
        
        return card
    }
    
    // MARK: - Styled Button
    
    private func createStyledButton(
        title: String,
        frame: NSRect,
        backgroundColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor,
        action: Selector
    ) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = Design.buttonCornerRadius
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.borderWidth = 1.5
        button.layer?.borderColor = borderColor.cgColor
        button.contentTintColor = textColor
        button.target = self
        button.action = action
        
        // Add subtle shadow
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.2
        button.layer?.shadowRadius = 4
        button.layer?.shadowOffset = CGSize(width: 0, height: -2)
        
        return button
    }
    
    // MARK: - Data Loading
    
    private func loadCurrentKeys() {
        let manager = ApiKeyManager.shared
        
        // Anthropic
        if let key = manager.getKey(.anthropic) {
            anthropicTextField.stringValue = key
            setStatusActive(dot: anthropicStatusDot, label: anthropicStatusLabel, active: true)
        } else {
            setStatusActive(dot: anthropicStatusDot, label: anthropicStatusLabel, active: false)
        }
        
        // Groq
        if let key = manager.getKey(.groq) {
            groqTextField.stringValue = key
            setStatusActive(dot: groqStatusDot, label: groqStatusLabel, active: true)
        } else {
            setStatusActive(dot: groqStatusDot, label: groqStatusLabel, active: false)
        }
    }
    
    private func setStatusActive(dot: NSView, label: NSTextField, active: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            if active {
                dot.layer?.backgroundColor = Design.activeGreen.cgColor
                label.stringValue = "Active"
                label.textColor = Design.activeGreen
                
                // Pulse animation for active status
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.5
                pulse.duration = 1.5
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                dot.layer?.add(pulse, forKey: "pulse")
            } else {
                dot.layer?.backgroundColor = Design.warningOrange.cgColor
                label.stringValue = "Setup"
                label.textColor = Design.warningOrange
                dot.layer?.removeAnimation(forKey: "pulse")
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleAnthropicVisibility() {
        isAnthropicVisible.toggle()
        anthropicTextField = replaceTextField(
            oldField: anthropicTextField,
            makeSecure: !isAnthropicVisible,
            placeholder: anthropicPlaceholder
        )
        anthropicShowButton.title = isAnthropicVisible ? "Hide" : "Show"
    }
    
    @objc private func toggleGroqVisibility() {
        isGroqVisible.toggle()
        groqTextField = replaceTextField(
            oldField: groqTextField,
            makeSecure: !isGroqVisible,
            placeholder: groqPlaceholder
        )
        groqShowButton.title = isGroqVisible ? "Hide" : "Show"
    }
    
    private func replaceTextField(oldField: NSTextField, makeSecure: Bool, placeholder: String) -> NSTextField {
        let currentValue = oldField.stringValue
        guard let superview = oldField.superview else { return oldField }
        let frame = oldField.frame
        
        oldField.removeFromSuperview()
        
        let newField: NSTextField
        if makeSecure {
            newField = NSSecureTextField(frame: frame)
        } else {
            newField = NSTextField(frame: frame)
        }
        newField.stringValue = currentValue
        newField.placeholderString = placeholder
        newField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        newField.textColor = .white
        newField.backgroundColor = .clear
        newField.isBordered = false
        newField.focusRingType = .none
        newField.drawsBackground = false
        superview.addSubview(newField)
        
        return newField
    }
    
    @objc private func openAnthropicConsole() {
        NSWorkspace.shared.open(URL(string: ApiKeyManager.ApiKeyType.anthropic.helpURL)!)
    }
    
    @objc private func openGroqConsole() {
        NSWorkspace.shared.open(URL(string: ApiKeyManager.ApiKeyType.groq.helpURL)!)
    }
    
    @objc private func saveSettings() {
        let manager = ApiKeyManager.shared
        
        let anthropicKey = anthropicTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let groqKey = groqTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate if not empty
        if !anthropicKey.isEmpty && !manager.validateKey(.anthropic, value: anthropicKey) {
            showValidationError("Invalid Anthropic API key format.\nIt should start with 'sk-ant-'")
            return
        }
        
        if !groqKey.isEmpty && !manager.validateKey(.groq, value: groqKey) {
            showValidationError("Invalid Groq API key format.\nIt should start with 'gsk_'")
            return
        }
        
        do {
            try manager.setKey(.anthropic, value: anthropicKey.isEmpty ? nil : anthropicKey)
            try manager.setKey(.groq, value: groqKey.isEmpty ? nil : groqKey)
            
            // Update status indicators with animation
            setStatusActive(dot: anthropicStatusDot, label: anthropicStatusLabel, active: !anthropicKey.isEmpty)
            setStatusActive(dot: groqStatusDot, label: groqStatusLabel, active: !groqKey.isEmpty)
            
            // Save data source settings
            saveDataSourceSettings()
            
            // Post notifications so the app can reload configuration
            NotificationCenter.default.post(name: .apiKeysUpdated, object: nil)
            NotificationCenter.default.post(name: .dataSourcesUpdated, object: nil)
            
            // Brief delay to show status change, then close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.window?.close()
            }
        } catch {
            showValidationError("Failed to save settings:\n\(error.localizedDescription)")
        }
    }
    
    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid API Key"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        // Style the alert icon
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
        
        alert.beginSheetModal(for: window!)
    }
    
    @objc private func cancelSettings() {
        window?.close()
    }

    // MARK: - Test Connection

    @objc private func testConfluenceConnection() {
        Task {
            let result = await ToolExecutor.shared.testConnection(toolName: "search_documentation")
            await MainActor.run { [weak self] in
                self?.showTestResult(result, title: "Confluence")
            }
        }
    }

    @objc private func testGitHubConnection() {
        Task {
            let result = await ToolExecutor.shared.testConnection(toolName: "search_codebase")
            await MainActor.run { [weak self] in
                self?.showTestResult(result, title: "GitHub")
            }
        }
    }

    private func showTestResult(_ result: ToolResult, title: String) {
        let alert = NSAlert()
        if result.success {
            alert.messageText = "\(title) Connected"
            alert.informativeText = result.content
            alert.alertStyle = .informational
        } else {
            alert.messageText = "\(title) Connection Failed"
            alert.informativeText = result.error ?? "Unknown error"
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "OK")
        if let window = self.window {
            alert.beginSheetModal(for: window)
        }
    }
}

// apiKeysUpdated notification is defined in ApiKeyManager.swift
