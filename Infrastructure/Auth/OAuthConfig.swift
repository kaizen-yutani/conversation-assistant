import Foundation

/// OAuth provider configurations
enum OAuthProvider: String, CaseIterable {
    case atlassian
    case github

    /// Client ID loaded from ~/.conversation-assistant-oauth config file
    var clientId: String {
        switch self {
        case .atlassian:
            return OAuthConfig.credentials["ATLASSIAN_CLIENT_ID"] ?? ""
        case .github:
            return OAuthConfig.credentials["GITHUB_CLIENT_ID"] ?? ""
        }
    }

    /// Client Secret loaded from ~/.conversation-assistant-oauth config file
    var clientSecret: String {
        switch self {
        case .atlassian:
            return OAuthConfig.credentials["ATLASSIAN_CLIENT_SECRET"] ?? ""
        case .github:
            return OAuthConfig.credentials["GITHUB_CLIENT_SECRET"] ?? ""
        }
    }

    /// Authorization URL
    var authorizeURL: String {
        switch self {
        case .atlassian:
            return "https://auth.atlassian.com/authorize"
        case .github:
            return "https://github.com/login/oauth/authorize"
        }
    }

    /// Token exchange URL
    var tokenURL: String {
        switch self {
        case .atlassian:
            return "https://auth.atlassian.com/oauth/token"
        case .github:
            return "https://github.com/login/oauth/access_token"
        }
    }

    /// OAuth scopes to request
    var scopes: String {
        switch self {
        case .atlassian:
            let confluenceScopes = [
                // Classic scopes (v1 API — search)
                "read:confluence-content.all",
                "read:confluence-space.summary",
                "read:confluence-content.summary",
                "search:confluence",
                "read:confluence-user",
                // Granular scopes (v2 API — page content)
                "read:page:confluence",
                "read:space:confluence"
            ]
            let jiraScopes = [
                "read:jira-work",
                "read:jira-user"
            ]
            let userScopes = ["read:me"]
            let authScopes = ["offline_access"]
            return (confluenceScopes + jiraScopes + userScopes + authScopes).joined(separator: " ")
        case .github:
            // GitHub scopes for code search, PRs, issues
            return "repo read:org read:user"
        }
    }

    /// Callback URL for this provider
    var callbackURL: String {
        return "\(OAuthConfig.urlScheme)://oauth/\(self.rawValue)"
    }

    /// Maps to DataSourceType
    var dataSourceType: DataSourceType {
        switch self {
        case .atlassian:
            return .confluence
        case .github:
            return .github
        }
    }

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .atlassian:
            return "Atlassian"
        case .github:
            return "GitHub"
        }
    }

    /// Check if OAuth is configured (has client ID)
    var isConfigured: Bool {
        return !clientId.isEmpty
    }

    /// Whether this provider uses PKCE
    var usesPKCE: Bool {
        switch self {
        case .atlassian:
            return true
        case .github:
            return false  // GitHub doesn't require PKCE for OAuth Apps
        }
    }

    /// Whether this provider uses a local HTTP callback server (Claude Code plugin style)
    /// This provides a better UX with "you can close this page" message in the browser
    var usesLocalCallbackServer: Bool {
        switch self {
        case .atlassian:
            return true   // Use localhost callback (register http://localhost:9876/callback in Developer Console)
        case .github:
            return true   // GitHub allows localhost callbacks
        }
    }
}

/// Global OAuth configuration
enum OAuthConfig {
    /// Custom URL scheme for OAuth callbacks
    static let urlScheme = "conversationassistant"

    /// OAuth credentials loaded from ~/.conversation-assistant-oauth
    /// File format: KEY=VALUE (one per line, # for comments)
    /// Keys: ATLASSIAN_CLIENT_ID, ATLASSIAN_CLIENT_SECRET, GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET
    static let credentials: [String: String] = {
        let path = NSString("~/.conversation-assistant-oauth").expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            NSLog("OAuth: No credentials file at ~/.conversation-assistant-oauth — OAuth disabled")
            return [:]
        }

        // Enforce secure file permissions (owner read/write only)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let perms = attrs[.posixPermissions] as? Int, perms != 0o600 {
            NSLog("OAuth: Fixing insecure permissions on credentials file")
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }

        var config: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if let eq = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                config[key] = value
            }
        }
        NSLog("OAuth: Loaded \(config.count) credentials from config file")
        return config
    }()

    /// Parse callback URL to extract provider and authorization code
    static func parseCallback(_ url: URL) -> (provider: OAuthProvider, code: String)? {
        guard url.scheme == urlScheme,
              url.host == "oauth",
              let pathProvider = url.pathComponents.dropFirst().first,
              let provider = OAuthProvider(rawValue: pathProvider) else {
            return nil
        }

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }

        return (provider, code)
    }
}
