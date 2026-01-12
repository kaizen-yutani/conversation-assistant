import Foundation

/// OAuth provider configurations
enum OAuthProvider: String, CaseIterable {
    case atlassian
    case github

    /// Client ID (registered once by developer)
    var clientId: String {
        switch self {
        case .atlassian:
            return "ESn3aDRFOujV7xoQoEBt1ptXvIrci2uk"
        case .github:
            // GitHub OAuth App client ID - register at https://github.com/settings/developers
            return "Ov23li8H8nY8ufo1A4HS"
        }
    }

    /// Client Secret (registered once by developer)
    var clientSecret: String {
        switch self {
        case .atlassian:
            return "ATOA92GmXo9F4xxeON3VLVhbAkpDW7uVKrmIVrtRPNK8cMP_270_ZrZoMS5kP7mIQzOZ997C2094"
        case .github:
            // GitHub OAuth App client secret
            return "7169c36d0ad5b422ef9702a106a83b7856d07c32"
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
                "read:confluence-content.all",
                "read:confluence-space.summary",
                "read:confluence-content.summary",
                "search:confluence",
                "read:confluence-user"
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
            return false  // Atlassian requires registered redirect URIs
        case .github:
            return true   // GitHub allows localhost callbacks
        }
    }
}

/// Global OAuth configuration
enum OAuthConfig {
    /// Custom URL scheme for OAuth callbacks
    static let urlScheme = "conversationassistant"

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
