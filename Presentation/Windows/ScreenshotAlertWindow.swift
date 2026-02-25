import Cocoa

/// Presentation: Screenshot Alert Window
/// Creates and manages the floating screenshot alert window
class ScreenshotAlertWindow {

    private let alertWidth: CGFloat = 400
    private let alertHeight: CGFloat = 120

    /// Create a screenshot alert window at the top-right corner
    /// Returns (window, thumbnailContainer)
    func createWindow() -> (window: NSWindow, container: NSView)? {
        // Position at top-right of screen
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.visibleFrame
        let alertX = screenFrame.maxX - alertWidth - 20
        let alertY = screenFrame.maxY - alertHeight - 20

        let window = NSWindow(
            contentRect: NSRect(x: alertX, y: alertY, width: alertWidth, height: alertHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ⭐ CRITICAL: Hide from screen sharing
        window.sharingType = .none

        // Floating window settings
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        let container = setupContent(for: window)

        return (window, container)
    }

    /// Show the window with animation (without activating the app)
    func show(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()  // Show without activating app
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        })
    }

    /// Hide the window with animation
    func hide(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    /// Create thumbnail image views for screenshots
    func createThumbnails(for screenshots: [Screenshot], in container: NSView) {
        // Clear existing thumbnails
        container.subviews.forEach { $0.removeFromSuperview() }

        let thumbnailHeight: CGFloat = 40
        let thumbnailWidth: CGFloat = 70
        let spacing: CGFloat = 8

        for (index, screenshot) in screenshots.enumerated() {
            let xOffset = CGFloat(index) * (thumbnailWidth + spacing)

            let thumbnail = screenshot.generateThumbnail(size: NSSize(width: thumbnailWidth, height: thumbnailHeight))

            let imageView = NSImageView(frame: NSRect(x: xOffset, y: 0, width: thumbnailWidth, height: thumbnailHeight))
            imageView.image = thumbnail
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.borderWidth = 1
            imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
            imageView.layer?.masksToBounds = true

            container.addSubview(imageView)
        }

        // Update container width
        container.frame.size.width = max(100, CGFloat(screenshots.count) * (thumbnailWidth + spacing))
    }

    // MARK: - Private Setup

    private func setupContent(for window: NSWindow) -> NSView {
        guard let contentView = window.contentView else { return NSView() }

        // Glass background
        let backgroundView = NSVisualEffectView(frame: contentView.bounds)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.material = .hudWindow
        backgroundView.alphaValue = 0.95
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 16
        backgroundView.layer?.borderWidth = 2.0
        backgroundView.layer?.borderColor = NSColor.systemPurple.cgColor
        contentView.addSubview(backgroundView, positioned: .below, relativeTo: nil)

        // Title
        let titleLabel = NSTextField(frame: NSRect(x: 20, y: alertHeight - 35, width: alertWidth - 40, height: 24))
        titleLabel.stringValue = "📸 Screenshot Captured!"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        // Shortcuts label
        let shortcutsLabel = NSTextField(frame: NSRect(x: 20, y: alertHeight - 58, width: alertWidth - 40, height: 18))
        shortcutsLabel.stringValue = "⌘L Show App  •  ⌘↩ Analyze  •  ⌘G Clear"
        shortcutsLabel.isEditable = false
        shortcutsLabel.isBordered = false
        shortcutsLabel.backgroundColor = .clear
        shortcutsLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        shortcutsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutsLabel.alignment = .center
        contentView.addSubview(shortcutsLabel)

        // Thumbnails scroll view
        let thumbnailsScrollView = NSScrollView(frame: NSRect(x: 15, y: 15, width: alertWidth - 30, height: 40))
        thumbnailsScrollView.hasHorizontalScroller = true
        thumbnailsScrollView.hasVerticalScroller = false
        thumbnailsScrollView.borderType = .noBorder
        thumbnailsScrollView.drawsBackground = false
        thumbnailsScrollView.backgroundColor = .clear

        let thumbnailsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        thumbnailsScrollView.documentView = thumbnailsContainer
        contentView.addSubview(thumbnailsScrollView)

        return thumbnailsContainer
    }
}
