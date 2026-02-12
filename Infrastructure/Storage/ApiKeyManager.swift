import Foundation

extension Notification.Name {
    static let apiKeysUpdated = Notification.Name("apiKeysUpdated")
}

/// Manages API keys for Anthropic, Groq, and Deepgram services
/// Thread-safe with concurrent reader-writer pattern
final class ApiKeyManager {

    static let shared = ApiKeyManager()

    private let filePath: String
    private var keys: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.conversationassistant.apikeys", attributes: .concurrent)

    /// Keys stored in the config file
    enum ApiKeyType: String, CaseIterable {
        case anthropic = "ANTHROPIC_API_KEY"
        case groq = "GROQ_API_KEY"
        case deepgram = "DEEPGRAM_API_KEY"

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .groq: return "Groq"
            case .deepgram: return "Deepgram"
            }
        }

        var placeholder: String {
            switch self {
            case .anthropic: return "sk-ant-..."
            case .groq: return "gsk_..."
            case .deepgram: return "..."
            }
        }

        var helpURL: String {
            switch self {
            case .anthropic: return "https://console.anthropic.com/settings/keys"
            case .groq: return "https://console.groq.com/keys"
            case .deepgram: return "https://console.deepgram.com"
            }
        }
    }

    private init() {
        let newPath = NSString("~/.conversation-assistant-keys").expandingTildeInPath
        let oldPath = NSString("~/.interview-master-keys").expandingTildeInPath
        // Migrate from old filename if needed
        if !FileManager.default.fileExists(atPath: newPath) && FileManager.default.fileExists(atPath: oldPath) {
            try? FileManager.default.copyItem(atPath: oldPath, toPath: newPath)
        }
        self.filePath = newPath
        loadKeys()
    }

    /// Load all keys from disk into memory cache
    private func loadKeys() {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            NSLog("⚠️ ApiKeyManager: Could not read \(filePath)")
            return
        }

        var loaded: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                loaded[key] = value
            }
        }

        queue.async(flags: .barrier) {
            self.keys = loaded
            NSLog("✅ ApiKeyManager: Loaded \(loaded.count) keys from file")
        }
    }

    /// Write all keys to the config file
    private func writeAllKeys() {
        let currentKeys = queue.sync { self.keys }

        var lines: [String] = [
            "# Conversation Assistant API Keys",
            "# Get your keys from:",
            "# - Anthropic: https://console.anthropic.com/settings/keys",
            "# - Groq: https://console.groq.com/keys",
            "# - Deepgram: https://console.deepgram.com",
            ""
        ]

        for keyType in ApiKeyType.allCases {
            if let value = currentKeys[keyType.rawValue], !value.isEmpty {
                lines.append("\(keyType.rawValue)=\(value)")
            }
        }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: filePath
            )
        } catch {
            NSLog("❌ ApiKeyManager: Failed to write keys: \(error)")
        }
    }

    /// Get API key for a specific service
    func getKey(_ type: ApiKeyType) -> String? {
        return queue.sync {
            let value = keys[type.rawValue]
            return (value?.isEmpty ?? true) ? nil : value
        }
    }

    /// Set API key for a specific service
    func setKey(_ type: ApiKeyType, value: String?) throws {
        queue.async(flags: .barrier) {
            self.keys[type.rawValue] = value
        }
        writeAllKeys()
        NotificationCenter.default.post(name: .apiKeysUpdated, object: nil)
    }

    /// Check if a key exists and is not empty
    func hasKey(_ type: ApiKeyType) -> Bool {
        return getKey(type) != nil
    }

    /// Mask API key for display (show first and last 4 chars)
    func maskedKey(_ type: ApiKeyType) -> String? {
        guard let key = getKey(type), key.count > 12 else { return nil }
        let prefix = String(key.prefix(8))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    /// Validate API key format
    func validateKey(_ type: ApiKeyType, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch type {
        case .anthropic:
            return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
        case .groq:
            return trimmed.hasPrefix("gsk_") && trimmed.count > 20
        case .deepgram:
            return trimmed.count > 20
        }
    }
}
