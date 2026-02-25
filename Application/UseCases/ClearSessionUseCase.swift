import Foundation

/// Use case for clearing the coding session
class ClearSessionUseCase {

    private let session: CodingSession

    init(session: CodingSession) {
        self.session = session
    }

    /// Clear all screenshots and analysis
    func clearAll() {
        session.clear()
    }

    /// Clear only analysis, keep screenshots
    func clearAnalysisOnly() {
        session.clearAnalysis()
    }

    /// Remove a specific screenshot
    /// - Parameter screenshotId: ID of screenshot to remove
    /// - Returns: true if removed, false if not found
    @discardableResult
    func removeScreenshot(_ screenshotId: ScreenshotId) -> Bool {
        return session.removeScreenshot(withId: screenshotId)
    }
}
