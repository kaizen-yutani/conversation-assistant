import Foundation
import Security

/// Configuration for each data source type
enum DataSourceType: String, CaseIterable {
    case confluence = "confluence"
    case github = "github"
    case database = "database"
    case webSearch = "webSearch"
    
    var displayName: String {
        switch self {
        case .confluence: return "Confluence"
        case .github: return "GitHub"
        case .database: return "Database"
        case .webSearch: return "Web Search"
        }
    }
    
    var icon: String {
        switch self {
        case .confluence: return "📚"
        case .github: return "💻"
        case .database: return "🗄️"
        case .webSearch: return "🌐"
        }
    }
    
    var requiredFields: [ConfigField] {
        switch self {
        case .confluence:
            return [
                ConfigField(key: "baseUrl", label: "Base URL", placeholder: "https://your-domain.atlassian.net/wiki", isSecret: false),
                ConfigField(key: "username", label: "Username/Email", placeholder: "user@example.com", isSecret: false),
                ConfigField(key: "apiToken", label: "API Token", placeholder: "Your Confluence API token", isSecret: true)
            ]
        case .github:
            return [
                ConfigField(key: "owner", label: "Owner/Org", placeholder: "organization or username", isSecret: false),
                ConfigField(key: "repo", label: "Repository", placeholder: "repository-name", isSecret: false),
                ConfigField(key: "token", label: "Personal Access Token", placeholder: "ghp_...", isSecret: true)
            ]
        case .database:
            return [
                ConfigField(key: "connectionString", label: "Connection String", placeholder: "postgresql://user:pass@host:5432/db", isSecret: true),
                ConfigField(key: "schemaDescription", label: "Schema Description", placeholder: "Describe your tables for text-to-SQL", isSecret: false)
            ]
        case .webSearch:
            return [
                ConfigField(key: "provider", label: "Provider", placeholder: "tavily, serper, or brave", isSecret: false),
                ConfigField(key: "apiKey", label: "API Key", placeholder: "Your search API key", isSecret: true)
            ]
        }
    }
}

/// A configuration field descriptor
struct ConfigField {
    let key: String
    let label: String
    let placeholder: String
    let isSecret: Bool
}

/// Data source configuration manager with Keychain storage for secrets
class DataSourceConfig {
    static let shared = DataSourceConfig()
    
    private let keychainService = "com.conversationassistant.datasources"
    private let enabledKey = "DataSource.Enabled"
    
    private init() {}
    
    // MARK: - Enable/Disable Data Sources
    
    func isEnabled(_ source: DataSourceType) -> Bool {
        let key = "\(enabledKey).\(source.rawValue)"
        return UserDefaults.standard.bool(forKey: key)
    }
    
    func setEnabled(_ source: DataSourceType, enabled: Bool) {
        let key = "\(enabledKey).\(source.rawValue)"
        UserDefaults.standard.set(enabled, forKey: key)
        NotificationCenter.default.post(name: .dataSourcesUpdated, object: nil)
    }
    
    // MARK: - Get/Set Configuration Values

    /// OAuth fields that should be stored securely in Keychain
    private static let oauthSecretFields = ["oauth_access_token", "oauth_refresh_token"]

    /// Determines if a field should be stored in Keychain
    private func isSecretField(for source: DataSourceType, field: String) -> Bool {
        // OAuth tokens are always secrets
        if Self.oauthSecretFields.contains(field) {
            return true
        }
        // Check if it's a defined secret field
        return source.requiredFields.first { $0.key == field }?.isSecret == true
    }

    func getValue(for source: DataSourceType, field: String) -> String? {
        let fullKey = "\(source.rawValue).\(field)"

        if isSecretField(for: source, field: field) {
            return getFromKeychain(key: fullKey)
        } else {
            return UserDefaults.standard.string(forKey: fullKey)
        }
    }

    func setValue(for source: DataSourceType, field: String, value: String) {
        let fullKey = "\(source.rawValue).\(field)"

        if isSecretField(for: source, field: field) {
            saveToKeychain(key: fullKey, value: value)
        } else {
            UserDefaults.standard.set(value, forKey: fullKey)
        }
        NotificationCenter.default.post(name: .dataSourcesUpdated, object: nil)
    }

    func clearValue(for source: DataSourceType, field: String) {
        let fullKey = "\(source.rawValue).\(field)"

        if isSecretField(for: source, field: field) {
            deleteFromKeychain(key: fullKey)
        } else {
            UserDefaults.standard.removeObject(forKey: fullKey)
        }
        NotificationCenter.default.post(name: .dataSourcesUpdated, object: nil)
    }
    
    // MARK: - Configuration Status

    /// Check if source is authenticated via OAuth
    func isOAuthAuthenticated(_ source: DataSourceType) -> Bool {
        guard let authMethod = getValue(for: source, field: "auth_method"),
              authMethod == "oauth",
              let token = getValue(for: source, field: "oauth_access_token"),
              !token.isEmpty else {
            return false
        }
        return true
    }

    func isConfigured(_ source: DataSourceType) -> Bool {
        // OAuth authentication counts as configured
        if isOAuthAuthenticated(source) {
            return true
        }

        // Check if all required fields have values (manual configuration)
        for field in source.requiredFields {
            guard let value = getValue(for: source, field: field.key), !value.isEmpty else {
                return false
            }
        }
        return true
    }

    func configurationStatus(_ source: DataSourceType) -> String {
        if !isEnabled(source) {
            return "Disabled"
        } else if isOAuthAuthenticated(source) {
            return "Connected via OAuth"
        } else if isConfigured(source) {
            return "Connected"
        } else {
            return "Not configured"
        }
    }
    
    // MARK: - Convenience Accessors for Tool Clients
    
    var confluenceConfig: (baseUrl: String, username: String, apiToken: String)? {
        guard isEnabled(.confluence),
              let baseUrl = getValue(for: .confluence, field: "baseUrl"),
              let username = getValue(for: .confluence, field: "username"),
              let apiToken = getValue(for: .confluence, field: "apiToken") else {
            return nil
        }
        return (baseUrl, username, apiToken)
    }
    
    var githubConfig: (owner: String, repo: String, token: String)? {
        guard isEnabled(.github) else { return nil }

        // Use OAuth token if available, otherwise use manual token
        let token: String
        if isOAuthAuthenticated(.github),
           let oauthToken = getValue(for: .github, field: "oauth_access_token") {
            token = oauthToken
        } else if let manualToken = getValue(for: .github, field: "token"), !manualToken.isEmpty {
            token = manualToken
        } else {
            return nil
        }

        // Owner and repo are still needed even with OAuth
        guard let owner = getValue(for: .github, field: "owner"),
              let repo = getValue(for: .github, field: "repo") else {
            return nil
        }

        return (owner, repo, token)
    }
    
    var databaseConfig: (connectionString: String, schemaDescription: String)? {
        guard isEnabled(.database),
              let connectionString = getValue(for: .database, field: "connectionString") else {
            return nil
        }
        let schemaDescription = getValue(for: .database, field: "schemaDescription") ?? ""
        return (connectionString, schemaDescription)
    }
    
    var webSearchConfig: (provider: String, apiKey: String)? {
        guard isEnabled(.webSearch),
              let provider = getValue(for: .webSearch, field: "provider"),
              let apiKey = getValue(for: .webSearch, field: "apiKey") else {
            return nil
        }
        return (provider, apiKey)
    }
    
    // MARK: - Keychain Operations
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing item first
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("❌ Keychain save failed for \(key): \(status)")
        }
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let dataSourcesUpdated = Notification.Name("DataSourcesUpdated")
}
