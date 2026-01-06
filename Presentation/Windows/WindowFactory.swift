import Cocoa

/// Presentation: Window Factory
/// Creates and configures application windows
class WindowFactory {

    /// Create the main application window with privacy settings
    static func createMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // ⭐ CORE LOGIC: Hidden from screen sharing (DON'T TOUCH!)
        window.sharingType = .none

        // Glass effect settings
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "🔒 Interview Master"

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
        visualEffectView.material = .menu  // Balanced material - transparent but readable
        visualEffectView.alphaValue = 0.8  // More opaque for blur effect
        return visualEffectView
    }
}
