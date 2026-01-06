import Foundation

/// Value object representing a unique coding session identifier
struct SessionId {
    private let value: UUID

    /// Create a new unique session ID
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
extension SessionId: Equatable {
    static func == (lhs: SessionId, rhs: SessionId) -> Bool {
        return lhs.value == rhs.value
    }
}

// Make it Hashable
extension SessionId: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// Make it Codable
extension SessionId: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
