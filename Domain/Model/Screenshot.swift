import Foundation
import Cocoa

/// Domain entity representing a captured screenshot
class Screenshot {
    let id: ScreenshotId
    let imageData: Data
    let thumbnail: NSImage
    let capturedAt: Date

    init(id: ScreenshotId, imageData: Data, thumbnail: NSImage, capturedAt: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.thumbnail = thumbnail
        self.capturedAt = capturedAt
    }

    /// Convert image data to base64 string for API
    var base64String: String {
        return imageData.base64EncodedString()
    }

    /// Get file size in KB
    var sizeInKB: Double {
        return Double(imageData.count) / 1024.0
    }
}

// Make it Equatable (by ID)
extension Screenshot: Equatable {
    static func == (lhs: Screenshot, rhs: Screenshot) -> Bool {
        return lhs.id == rhs.id
    }
}

// Make it Hashable (by ID)
extension Screenshot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
