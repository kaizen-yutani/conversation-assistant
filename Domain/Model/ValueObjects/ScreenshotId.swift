import Foundation

/// Value object representing a unique screenshot identifier
struct ScreenshotId {
    private let value: UUID

    /// Create a new unique screenshot ID
    init() {
        self.value = UUID()
    }

    /// Recreate from existing UUID
    init(uuid: UUID) {
        self.value = uuid
    }

    /// Get the UUID value
    var uuid: UUID {
        return value
    }

    /// String representation
    var stringValue: String {
        return value.uuidString
    }
}

// Make it Equatable
extension ScreenshotId: Equatable {
    static func == (lhs: ScreenshotId, rhs: ScreenshotId) -> Bool {
        return lhs.value == rhs.value
    }
}

// Make it Hashable
extension ScreenshotId: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// Make it Codable
extension ScreenshotId: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
