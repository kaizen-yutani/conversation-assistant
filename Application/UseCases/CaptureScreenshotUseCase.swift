import Foundation
import Cocoa

/// Use case for capturing a screenshot and adding it to the session
@available(macOS 12.3, *)
class CaptureScreenshotUseCase {

    private let screenCapture: MacScreenCapture
    private let session: CodingSession

    enum CaptureError: Error, LocalizedError {
        case captureFailed(String)
        case thumbnailFailed(String)

        var errorDescription: String? {
            switch self {
            case .captureFailed(let message):
                return "Screenshot capture failed: \(message)"
            case .thumbnailFailed(let message):
                return "Thumbnail generation failed: \(message)"
            }
        }
    }

    init(screenCapture: MacScreenCapture, session: CodingSession) {
        self.screenCapture = screenCapture
        self.session = session
    }

    /// Execute the use case
    /// - Returns: The captured screenshot
    func execute() async -> Result<Screenshot, CaptureError> {
        // Capture screen
        let captureResult = await screenCapture.captureMainDisplay()

        guard case .success(let imageData) = captureResult else {
            if case .failure(let error) = captureResult {
                return .failure(.captureFailed(error.localizedDescription))
            }
            return .failure(.captureFailed("Unknown error"))
        }

        // Generate thumbnail
        let thumbnailResult = screenCapture.generateThumbnail(from: imageData)

        guard case .success(let thumbnail) = thumbnailResult else {
            if case .failure(let error) = thumbnailResult {
                return .failure(.thumbnailFailed(error.localizedDescription))
            }
            return .failure(.thumbnailFailed("Unknown error"))
        }

        // Create screenshot entity
        let screenshot = Screenshot(
            id: ScreenshotId(),
            imageData: imageData,
            thumbnail: thumbnail
        )

        // Add to session
        session.addScreenshot(screenshot)

        return .success(screenshot)
    }
}
