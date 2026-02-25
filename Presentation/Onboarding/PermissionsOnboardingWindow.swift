import Cocoa
import ScreenCaptureKit

/// Mandatory permissions onboarding window - cannot be skipped
class PermissionsOnboardingWindow: NSWindow {

    private var grantButton: NSButton!
    private var statusLabel: NSTextField!
    private var checkTimer: Timer?
    private var onComplete: (() -> Void)?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Welcome to Conversation Assistant"
        self.center()
        self.isReleasedWhenClosed = false

        // Prevent closing without permission
        self.delegate = PermissionsWindowDelegate.shared

        setupUI()
        startPermissionCheck()
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor

        // App icon placeholder
        let iconView = NSImageView(frame: NSRect(x: 190, y: 290, width: 100, height: 100))
        iconView.image = NSImage(systemSymbolName: "message.badge.waveform.fill", accessibilityDescription: "App Icon")
        iconView.contentTintColor = .systemBlue
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Screen Recording Permission Required")
        titleLabel.frame = NSRect(x: 40, y: 240, width: 400, height: 30)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        container.addSubview(titleLabel)

        // Description
        let description = """
        Conversation Assistant needs Screen Recording permission to:

        • Capture screenshots for AI analysis
        • Listen to system audio (Zoom, Teams calls)

        This permission is required to use the app.
        """

        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.frame = NSRect(x: 40, y: 120, width: 400, height: 110)
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = NSColor(white: 0.8, alpha: 1.0)
        descLabel.alignment = .center
        container.addSubview(descLabel)

        // Status label
        statusLabel = NSTextField(labelWithString: "⏳ Waiting for permission...")
        statusLabel.frame = NSRect(x: 40, y: 85, width: 400, height: 20)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .systemYellow
        statusLabel.alignment = .center
        container.addSubview(statusLabel)

        // Grant button
        grantButton = NSButton(title: "Open System Preferences", target: self, action: #selector(openSystemPreferences))
        grantButton.frame = NSRect(x: 140, y: 35, width: 200, height: 40)
        grantButton.bezelStyle = .rounded
        grantButton.font = .systemFont(ofSize: 14, weight: .medium)
        grantButton.wantsLayer = true
        grantButton.layer?.cornerRadius = 8
        container.addSubview(grantButton)

        self.contentView = container
    }

    @objc private func openSystemPreferences() {
        // Open Screen Recording preferences
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private func startPermissionCheck() {
        // Check immediately
        checkPermission()

        // Then check every 1 second
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
    }

    private func checkPermission() {
        Task {
            let hasPermission = await checkScreenCapturePermission()

            await MainActor.run {
                if hasPermission {
                    self.permissionGranted()
                }
            }
        }
    }

    private func checkScreenCapturePermission() async -> Bool {
        do {
            // Try to get shareable content - this will fail if permission not granted
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    private func permissionGranted() {
        checkTimer?.invalidate()
        checkTimer = nil

        statusLabel.stringValue = "✅ Permission granted!"
        statusLabel.textColor = .systemGreen

        grantButton.title = "Get Started"
        grantButton.action = #selector(completeOnboarding)

        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    @objc private func completeOnboarding() {
        self.close()
        onComplete?()
    }

    deinit {
        checkTimer?.invalidate()
    }
}

// MARK: - Window Delegate to prevent closing

private class PermissionsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = PermissionsWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Only allow closing if permission is granted
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            return true
        }

        // Show alert
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = "You must grant Screen Recording permission to use Conversation Assistant."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Quit App")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open system preferences
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
            return false
        } else {
            // Quit app
            NSApp.terminate(nil)
            return true
        }
    }
}

// MARK: - Permission Check Helper

enum PermissionStatus {
    case granted
    case denied
    case unknown
}

class PermissionChecker {
    static func checkScreenRecordingPermission() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return .granted
        } catch {
            return .denied
        }
    }

    static func hasCompletedOnboarding() -> Bool {
        return UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }
}
