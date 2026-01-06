import Foundation
import Cocoa

/// Domain Entity: Screenshot
/// Represents a captured screenshot with metadata
struct Screenshot {
    let id: UUID
    let image: NSImage
    let capturedAt: Date

    init(id: UUID = UUID(), image: NSImage, capturedAt: Date = Date()) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
    }

    /// Generate a thumbnail from the screenshot
    func generateThumbnail(size: NSSize) -> NSImage {
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height

        var thumbnailSize = size
        if aspectRatio > 1 {
            thumbnailSize.height = size.width / aspectRatio
        } else {
            thumbnailSize.width = size.height * aspectRatio
        }

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Convert image to base64 encoded PNG string
    func toBase64() -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}

// MARK: - Equatable
extension Screenshot: Equatable {
    static func == (lhs: Screenshot, rhs: Screenshot) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Identifiable
extension Screenshot: Identifiable {}
