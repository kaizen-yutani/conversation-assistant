import Foundation

/// Value object representing a validated Anthropic API key
struct ApiKey {
    private let value: String

    /// Initialize with validation
    /// - Parameter value: Raw API key string
    /// - Returns: nil if invalid format
    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate Anthropic API key format
        guard trimmed.hasPrefix("sk-ant-") && trimmed.count > 20 else {
            return nil
        }

        self.value = trimmed
    }

    /// Get the raw API key value (use carefully!)
    var rawValue: String {
        return value
    }

    /// Masked version for display (e.g., "sk-ant-***XYZ")
    var masked: String {
        guard value.count > 10 else { return "sk-ant-***" }
        let prefix = String(value.prefix(7))  // "sk-ant-"
        let suffix = String(value.suffix(3))   // Last 3 chars
        return "\(prefix)***\(suffix)"
    }
}

// Make it Equatable
extension ApiKey: Equatable {
    static func == (lhs: ApiKey, rhs: ApiKey) -> Bool {
        return lhs.value == rhs.value
    }
}

// Make it Hashable
extension ApiKey: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
