import Cocoa

/// Presentation: Window Factory
/// Creates and configures application windows
class WindowFactory {

    /// Create the main application window with privacy settings
    static func createMainWindow() -> NSWindow {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth = screenFrame.width * 0.7
        let windowHeight = screenFrame.height * 0.85

        let windowX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let windowY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2

        let window = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.sharingType = .readOnly

        // Glass effect settings
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Conversation Assistant"

        // Transparent background for glass effect
        window.backgroundColor = .clear
        window.isOpaque = false

        // Start as floating window
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return window
    }

    /// Create a glass background view
    static func createGlassBackground(for view: NSView) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView(frame: view.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.alphaValue = 0.85
        return visualEffectView
    }
}
