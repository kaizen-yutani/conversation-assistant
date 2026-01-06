import Cocoa
import CoreGraphics
import ScreenCaptureKit

/// Infrastructure service for capturing screenshots on macOS
@available(macOS 12.3, *)
class MacScreenCapture {

    enum CaptureError: Error {
        case noDisplay
        case captureFailed
        case imageConversionFailed
        case thumbnailGenerationFailed
        case permissionDenied
    }

    /// Capture the main display as PNG data (async)
    /// - Returns: PNG image data
    func captureMainDisplay() async -> Result<Data, CaptureError> {
        do {
            // Get shareable content
            let content = try await SCShareableContent.current

            guard let display = content.displays.first else {
                return .failure(.noDisplay)
            }

            // Configure capture
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.scalesToFit = false

            // Capture screenshot
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Convert CGImage to PNG data
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            guard let pngData = nsImage.pngData() else {
                return .failure(.imageConversionFailed)
            }

            return .success(pngData)
        } catch {
            return .failure(.captureFailed)
        }
    }

    /// Generate a thumbnail from image data
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - maxSize: Maximum size for thumbnail (default 120x120)
    /// - Returns: Thumbnail NSImage
    func generateThumbnail(from imageData: Data, maxSize: CGFloat = 120) -> Result<NSImage, CaptureError> {
        guard let originalImage = NSImage(data: imageData) else {
            return .failure(.thumbnailGenerationFailed)
        }

        let originalSize = originalImage.size
        let aspectRatio = originalSize.width / originalSize.height

        var thumbnailSize: NSSize
        if aspectRatio > 1 {
            // Landscape
            thumbnailSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            // Portrait or square
            thumbnailSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        originalImage.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                          from: NSRect(origin: .zero, size: originalSize),
                          operation: .copy,
                          fraction: 1.0)
        thumbnail.unlockFocus()

        return .success(thumbnail)
    }
}

// Helper extension to convert NSImage to PNG Data
extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        imageRep.size = self.size
        return imageRep.representation(using: .png, properties: [:])
    }
}
