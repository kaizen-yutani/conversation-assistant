import Foundation
import Cocoa
import ScreenCaptureKit

/// Infrastructure: Screen Capture Service
/// Handles screenshot capture using ScreenCaptureKit
class ScreenCaptureService {

    enum CaptureError: Error {
        case noDisplayFound
        case captureFailed(Error)
    }

    /// Capture a screenshot of the main display
    func captureScreen() async -> Result<Screenshot, CaptureError> {
        do {
            // Use ScreenCaptureKit
            let content = try await SCShareableContent.current

            guard let display = content.displays.first else {
                return .failure(.noDisplayFound)
            }

            // Configure capture
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.scalesToFit = false

            // Capture screenshot
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Convert to NSImage
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            // Create Screenshot entity
            let screenshot = Screenshot(image: nsImage)

            return .success(screenshot)

        } catch {
            return .failure(.captureFailed(error))
        }
    }
}
