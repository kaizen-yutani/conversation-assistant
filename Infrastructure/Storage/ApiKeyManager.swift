import Foundation

/// Manages API keys for Anthropic and Groq services
/// Stores keys in ~/.interview-master-keys file with KEY=value format
final class ApiKeyManager {
    
    static let shared = ApiKeyManager()
    
    private let filePath: String
    
    /// Keys stored in the config file
    enum ApiKeyType: String, CaseIterable {
        case anthropic = "ANTHROPIC_API_KEY"
        case groq = "GROQ_API_KEY"
        
        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .groq: return "Groq"
            }
        }
        
        var placeholder: String {
            switch self {
            case .anthropic: return "sk-ant-..."
            case .groq: return "gsk_..."
            }
        }
        
        var helpURL: String {
            switch self {
            case .anthropic: return "https://console.anthropic.com/settings/keys"
            case .groq: return "https://console.groq.com/keys"
            }
        }
    }
    
    private init() {
        self.filePath = NSString("~/.interview-master-keys").expandingTildeInPath
    }
    
    /// Read all keys from the config file
    private func readAllKeys() -> [String: String] {
        var keys: [String: String] = [:]
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return keys
        }
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                keys[key] = value
            }
        }
        return keys
    }
    
    /// Write all keys to the config file
    private func writeAllKeys(_ keys: [String: String]) throws {
        var lines: [String] = [
            "# Interview Master API Keys",
            "# Get your keys from:",
            "# - Anthropic: https://console.anthropic.com/settings/keys",
            "# - Groq: https://console.groq.com/keys",
            ""
        ]
        
        for keyType in ApiKeyType.allCases {
            if let value = keys[keyType.rawValue], !value.isEmpty {
                lines.append("\(keyType.rawValue)=\(value)")
            }
        }
        
        let content = lines.joined(separator: "\n")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        
        // Set file permissions to user-only (600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: filePath
        )
    }
    
    /// Get API key for a specific service
    func getKey(_ type: ApiKeyType) -> String? {
        let keys = readAllKeys()
        let value = keys[type.rawValue]
        return (value?.isEmpty ?? true) ? nil : value
    }
    
    /// Set API key for a specific service
    func setKey(_ type: ApiKeyType, value: String?) throws {
        var keys = readAllKeys()
        keys[type.rawValue] = value
        try writeAllKeys(keys)
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
        }
    }
}
