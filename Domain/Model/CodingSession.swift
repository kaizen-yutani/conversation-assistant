import Foundation

/// Aggregate root representing a coding session with screenshots and analysis
class CodingSession {
    let sessionId: SessionId
    private(set) var screenshots: [Screenshot] = []
    private(set) var analysis: Analysis?

    init(sessionId: SessionId = SessionId()) {
        self.sessionId = sessionId
    }

    // MARK: - Business Logic

    /// Add a screenshot to the session
    /// - Parameter screenshot: The screenshot to add
    func addScreenshot(_ screenshot: Screenshot) {
        screenshots.append(screenshot)
    }

    /// Remove a screenshot by ID
    /// - Parameter screenshotId: The ID of the screenshot to remove
    /// - Returns: true if removed, false if not found
    @discardableResult
    func removeScreenshot(withId screenshotId: ScreenshotId) -> Bool {
        if let index = screenshots.firstIndex(where: { $0.id == screenshotId }) {
            screenshots.remove(at: index)
            return true
        }
        return false
    }

    /// Set the analysis result
    /// - Parameter analysis: The analysis to set
    func setAnalysis(_ analysis: Analysis) {
        self.analysis = analysis
    }

    /// Clear the entire session
    func clear() {
        screenshots.removeAll()
        analysis = nil
    }

    /// Clear only the analysis, keeping screenshots
    func clearAnalysis() {
        analysis = nil
    }

    // MARK: - Query Methods

    /// Check if session has screenshots
    var hasScreenshots: Bool {
        return !screenshots.isEmpty
    }

    /// Check if session has analysis
    var hasAnalysis: Bool {
        return analysis != nil
    }

    /// Get total number of screenshots
    var screenshotCount: Int {
        return screenshots.count
    }

    /// Get total size of all screenshots in KB
    var totalSizeInKB: Double {
        return screenshots.reduce(0) { $0 + $1.sizeInKB }
    }

    /// Check if session is ready for analysis (has at least one screenshot)
    var isReadyForAnalysis: Bool {
        return hasScreenshots
    }

    /// Get all screenshots as base64 strings for API
    var screenshotsAsBase64: [String] {
        return screenshots.map { $0.base64String }
    }
}
