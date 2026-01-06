import AppKit

/// Settings window for managing API keys - visionOS-inspired glassmorphism design
final class SettingsWindowController: NSWindowController {
    
    // UI References
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
    
    // State
    private var isAnthropicVisible = false
    private var isGroqVisible = false
    private var anthropicPlaceholder = ""
    private var groqPlaceholder = ""
    
    // Design constants
    private struct Design {
        static let cardCornerRadius: CGFloat = 14
        static let inputCornerRadius: CGFloat = 8
        static let buttonCornerRadius: CGFloat = 10
        static let cardPadding: CGFloat = 16
        static let spacing: CGFloat = 12
        
        // Colors
        static let anthropicAccent = NSColor(red: 0.85, green: 0.467, blue: 0.341, alpha: 1.0) // Claude coral
        static let groqAccent = NSColor(red: 0.0, green: 0.75, blue: 0.85, alpha: 1.0) // Electric cyan
        static let activeGreen = NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0)
        static let warningOrange = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        static let cardBorder = NSColor.white.withAlphaComponent(0.15)
        static let inputBackground = NSColor.black.withAlphaComponent(0.2)
    }
    
    static func create() -> SettingsWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
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
        backgroundBlur.layer?.cornerRadius = 12
        contentView.addSubview(backgroundBlur)
        
        // === HEADER ===
        let headerY: CGFloat = 340
        
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
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Configure your AI service API keys")
        subtitleLabel.frame = NSRect(x: 24, y: headerY - 28, width: 400, height: 20)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        contentView.addSubview(subtitleLabel)
        
        // === ANTHROPIC CARD ===
        anthropicPlaceholder = ApiKeyManager.ApiKeyType.anthropic.placeholder
        anthropicCard = createApiKeyCard(
            in: contentView,
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
            in: contentView,
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
        
        // === ACTION BUTTONS ===
        let buttonY: CGFloat = 24
        
        // Save button - styled like main app
        let saveButton = createStyledButton(
            title: "Save",
            frame: NSRect(x: 356, y: buttonY, width: 100, height: 36),
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
            frame: NSRect(x: 246, y: buttonY, width: 100, height: 36),
            backgroundColor: NSColor.white.withAlphaComponent(0.08),
            borderColor: NSColor.white.withAlphaComponent(0.15),
            textColor: NSColor.white.withAlphaComponent(0.8),
            action: #selector(cancelSettings)
        )
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
        
        // Load current values
        loadCurrentKeys()
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
            
            // Post notification so the app can reload keys
            NotificationCenter.default.post(name: .apiKeysUpdated, object: nil)
            
            // Brief delay to show status change, then close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.window?.close()
            }
        } catch {
            showValidationError("Failed to save API keys:\n\(error.localizedDescription)")
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
}

// MARK: - Notification Extension

extension Notification.Name {
    static let apiKeysUpdated = Notification.Name("apiKeysUpdated")
}
