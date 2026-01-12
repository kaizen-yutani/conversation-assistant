import Cocoa

/// Atlassian onboarding - API token flow (simplest happy path, no OAuth config needed)
class AtlassianOnboardingWindow: NSWindow {

    private var getTokenButton: NSButton!
    private var tokenField: NSSecureTextField!
    private var emailField: NSTextField!
    private var urlField: NSTextField!
    private var connectButton: NSButton!
    private var skipButton: NSButton!
    private var statusLabel: NSTextField!
    private var onComplete: (() -> Void)?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Connect Your Workspace"
        self.center()
        self.isReleasedWhenClosed = false

        setupUI()
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor

        // Atlassian icon
        let iconView = NSImageView(frame: NSRect(x: 190, y: 310, width: 100, height: 100))
        iconView.image = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: "Connect")
        iconView.contentTintColor = NSColor.systemBlue
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Connect Confluence & Jira")
        titleLabel.frame = NSRect(x: 40, y: 270, width: 400, height: 30)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        container.addSubview(titleLabel)

        // Step 1: Get token button
        getTokenButton = NSButton(title: "1. Get API Token from Atlassian →", target: self, action: #selector(openTokenPage))
        getTokenButton.frame = NSRect(x: 90, y: 225, width: 300, height: 32)
        getTokenButton.bezelStyle = .rounded
        getTokenButton.font = .systemFont(ofSize: 13, weight: .medium)
        getTokenButton.contentTintColor = .systemBlue
        container.addSubview(getTokenButton)

        // URL field
        let urlLabel = NSTextField(labelWithString: "Atlassian URL:")
        urlLabel.frame = NSRect(x: 40, y: 188, width: 100, height: 20)
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(urlLabel)

        urlField = NSTextField(frame: NSRect(x: 40, y: 163, width: 400, height: 24))
        urlField.placeholderString = "https://your-company.atlassian.net"
        urlField.font = .systemFont(ofSize: 13)
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 6
        urlField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        container.addSubview(urlField)

        // Email field
        let emailLabel = NSTextField(labelWithString: "Your Email:")
        emailLabel.frame = NSRect(x: 40, y: 133, width: 100, height: 20)
        emailLabel.font = .systemFont(ofSize: 12)
        emailLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(emailLabel)

        emailField = NSTextField(frame: NSRect(x: 40, y: 108, width: 400, height: 24))
        emailField.placeholderString = "you@company.com"
        emailField.font = .systemFont(ofSize: 13)
        emailField.wantsLayer = true
        emailField.layer?.cornerRadius = 6
        emailField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        container.addSubview(emailField)

        // Token field
        let tokenLabel = NSTextField(labelWithString: "API Token:")
        tokenLabel.frame = NSRect(x: 40, y: 78, width: 100, height: 20)
        tokenLabel.font = .systemFont(ofSize: 12)
        tokenLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(tokenLabel)

        tokenField = NSSecureTextField(frame: NSRect(x: 40, y: 53, width: 400, height: 24))
        tokenField.placeholderString = "Paste your API token here"
        tokenField.font = .systemFont(ofSize: 13)
        tokenField.wantsLayer = true
        tokenField.layer?.cornerRadius = 6
        tokenField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        container.addSubview(tokenField)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 40, y: 28, width: 240, height: 20)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemGreen
        statusLabel.isHidden = true
        container.addSubview(statusLabel)

        // Connect button
        connectButton = NSButton(title: "Connect", target: self, action: #selector(connectWithToken))
        connectButton.frame = NSRect(x: 290, y: 8, width: 100, height: 36)
        connectButton.bezelStyle = .rounded
        connectButton.font = .systemFont(ofSize: 14, weight: .semibold)
        connectButton.wantsLayer = true
        connectButton.layer?.cornerRadius = 8
        connectButton.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        connectButton.contentTintColor = .white
        container.addSubview(connectButton)

        // Skip link
        skipButton = NSButton(title: "Skip", target: self, action: #selector(skipOnboarding))
        skipButton.frame = NSRect(x: 395, y: 8, width: 50, height: 36)
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.font = .systemFont(ofSize: 12)
        skipButton.contentTintColor = NSColor(white: 0.5, alpha: 1.0)
        container.addSubview(skipButton)

        self.contentView = container
    }

    @objc private func openTokenPage() {
        NSWorkspace.shared.open(URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
    }

    @objc private func connectWithToken() {
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !url.isEmpty, !email.isEmpty, !token.isEmpty else {
            statusLabel.stringValue = "❌ Please fill all fields"
            statusLabel.textColor = .systemRed
            statusLabel.isHidden = false
            return
        }

        // Save to DataSourceConfig for Confluence
        let baseUrl = url.hasSuffix("/") ? String(url.dropLast()) : url
        DataSourceConfig.shared.setValue(for: .confluence, field: "baseUrl", value: baseUrl + "/wiki")
        DataSourceConfig.shared.setValue(for: .confluence, field: "username", value: email)
        DataSourceConfig.shared.setValue(for: .confluence, field: "apiToken", value: token)
        DataSourceConfig.shared.setEnabled(.confluence, enabled: true)

        statusLabel.stringValue = "✅ Connected!"
        statusLabel.textColor = .systemGreen
        statusLabel.isHidden = false

        UserDefaults.standard.set(true, forKey: "hasCompletedAtlassianOnboarding")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.completeOnboarding()
        }
    }

    @objc private func skipOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSkippedAtlassianOnboarding")
        completeOnboarding()
    }

    @objc private func completeOnboarding() {
        self.close()
        onComplete?()
    }

    // MARK: - Static Helpers

    /// Should we show Atlassian onboarding?
    static func shouldShow() -> Bool {
        // Don't show if already configured
        if DataSourceConfig.shared.isConfigured(.confluence) {
            return false
        }
        // Don't show if already completed or explicitly skipped
        if UserDefaults.standard.bool(forKey: "hasCompletedAtlassianOnboarding") {
            return false
        }
        if UserDefaults.standard.bool(forKey: "hasSkippedAtlassianOnboarding") {
            return false
        }
        return true
    }

    /// Reset to show onboarding again
    static func reset() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedAtlassianOnboarding")
        UserDefaults.standard.removeObject(forKey: "hasSkippedAtlassianOnboarding")
    }
}
