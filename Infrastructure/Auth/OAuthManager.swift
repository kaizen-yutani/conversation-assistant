import Foundation
import CommonCrypto
import AppKit

/// Notification posted when OAuth completes
extension Notification.Name {
    static let oauthCompleted = Notification.Name("OAuthCompleted")
    static let oauthFailed = Notification.Name("OAuthFailed")
}

/// Manages OAuth authentication flows with PKCE
class OAuthManager {
    static let shared = OAuthManager()

    /// Active OAuth state (provider + PKCE verifier)
    private var pendingAuth: (provider: OAuthProvider, codeVerifier: String, state: String)?

    /// Local callback server for providers that use localhost redirect (like GitHub)
    private var callbackServer: OAuthCallbackServer?

    /// Deduplicates concurrent token refresh requests per provider
    private var refreshTasks: [OAuthProvider: Task<Bool, Never>] = [:]

    private init() {}

    // MARK: - Start OAuth Flow

    /// Initiates OAuth flow for the given provider
    func startOAuthFlow(for provider: OAuthProvider) {
        print("[OAuthManager] startOAuthFlow called for \(provider.rawValue)")
        print("[OAuthManager] clientId present: \(!provider.clientId.isEmpty), clientSecret present: \(!provider.clientSecret.isEmpty)")
        print("[OAuthManager] Loaded credentials count: \(OAuthConfig.credentials.count)")
        guard provider.isConfigured else {
            print("[OAuthManager] Provider \(provider.rawValue) is NOT configured — check ~/.conversation-assistant-oauth")
            NSLog("OAuth: Provider \(provider.rawValue) is not configured")
            NotificationCenter.default.post(
                name: .oauthFailed,
                object: nil,
                userInfo: ["provider": provider, "error": "Provider not configured"]
            )
            return
        }
        print("[OAuthManager] Provider \(provider.rawValue) is configured")

        // Use local callback server for GitHub (shows "you can close this page" in browser)
        if provider.usesLocalCallbackServer {
            print("[OAuthManager] Using local callback server for \(provider.rawValue)")
            startOAuthFlowWithLocalServer(for: provider)
            return
        }

        // Generate PKCE code verifier and challenge (only for providers that use PKCE)
        let codeVerifier = provider.usesPKCE ? generateCodeVerifier() : ""
        let codeChallenge = provider.usesPKCE ? generateCodeChallenge(from: codeVerifier) : ""

        // Generate state parameter for CSRF protection
        let state = UUID().uuidString

        // Store pending auth state (including state for validation on callback)
        pendingAuth = (provider, codeVerifier, state)

        // Build authorization URL
        var components = URLComponents(string: provider.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: provider.clientId),
            URLQueryItem(name: "redirect_uri", value: provider.callbackURL),
            URLQueryItem(name: "scope", value: provider.scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]

        // Add PKCE parameters only for providers that use it
        if provider.usesPKCE {
            components.queryItems?.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
            components.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }

        // Atlassian requires additional parameters
        if provider == .atlassian {
            components.queryItems?.append(URLQueryItem(name: "audience", value: "api.atlassian.com"))
            components.queryItems?.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        guard let url = components.url else {
            NSLog("OAuth: Failed to build authorization URL")
            return
        }

        NSLog("OAuth: Opening authorization URL for \(provider.rawValue): \(url.absoluteString.prefix(200))...")
        print("[OAuthManager] Opening URL: \(url.absoluteString)")
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            NSLog("OAuth: Failed to open browser for authorization URL")
            NotificationCenter.default.post(
                name: .oauthFailed,
                object: nil,
                userInfo: ["provider": provider, "error": "Could not open browser. Please check your default browser settings."]
            )
        }
    }

    /// Starts OAuth flow using local HTTP callback server (Claude Code plugin style)
    private func startOAuthFlowWithLocalServer(for provider: OAuthProvider) {
        print("[OAuthManager] startOAuthFlowWithLocalServer called for \(provider.rawValue)")
        NSLog("OAuth: Starting local server flow for \(provider.rawValue)")

        // Stop any existing server
        callbackServer?.stop()
        print("[OAuthManager] Stopped any existing server")

        // Create and start new callback server
        let server = OAuthCallbackServer()
        callbackServer = server

        // Generate state parameter for CSRF protection
        let state = UUID().uuidString
        server.expectedState = state
        pendingAuth = (provider, "", state)

        print("[OAuthManager] Created OAuthCallbackServer, calling start()...")
        NSLog("OAuth: Starting callback server...")

        server.start(
            onReady: { [weak self] callbackURL in
                print("[OAuthManager] onReady callback fired with URL: \(callbackURL)")
                NSLog("OAuth: onReady callback fired with URL: \(callbackURL)")
                // Server is ready - now open the browser
                guard self != nil else {
                    NSLog("OAuth: self is nil in onReady")
                    return
                }

                var components = URLComponents(string: provider.authorizeURL)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: provider.clientId),
                    URLQueryItem(name: "redirect_uri", value: callbackURL),
                    URLQueryItem(name: "scope", value: provider.scopes),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "state", value: state)
                ]

                guard let url = components.url else {
                    NSLog("OAuth: Failed to build authorization URL")
                    return
                }

                NSLog("OAuth: Server ready on \(callbackURL), opening browser...")
                print("[OAuthManager] Opening URL: \(url.absoluteString)")
                let opened = NSWorkspace.shared.open(url)
                if !opened {
                    NSLog("OAuth: Failed to open browser for authorization URL")
                }
            },
            completion: { [weak self] code, error in
                guard let self = self else { return }

                if let error = error {
                    NSLog("OAuth: Local server error: \(error.localizedDescription)")
                    NotificationCenter.default.post(
                        name: .oauthFailed,
                        object: nil,
                        userInfo: ["provider": provider, "error": error.localizedDescription]
                    )
                    return
                }

                guard let code = code else {
                    NSLog("OAuth: No authorization code received")
                    NotificationCenter.default.post(
                        name: .oauthFailed,
                        object: nil,
                        userInfo: ["provider": provider, "error": "No authorization code received"]
                    )
                    return
                }

                NSLog("OAuth: Got authorization code from local server, exchanging for token...")

                // Exchange code for token
                Task {
                    await self.exchangeCodeForToken(
                        provider: provider,
                        code: code,
                        codeVerifier: "",  // GitHub doesn't use PKCE
                        redirectUri: server.callbackURL
                    )
                }
            }
        )
    }

    // MARK: - Handle Callback

    /// Handles OAuth callback URL
    func handleCallback(_ url: URL) {
        NSLog("OAuth: Received callback URL: \(url)")
        NSLog("OAuth: URL components - scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil"), path: \(url.path)")

        guard let (provider, code) = OAuthConfig.parseCallback(url) else {
            NSLog("OAuth: Failed to parse callback URL - scheme: \(url.scheme ?? "nil"), expected: \(OAuthConfig.urlScheme)")
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                NSLog("OAuth: Query items: \(components.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", ") ?? "none")")
            }
            return
        }

        NSLog("OAuth: Parsed provider: \(provider.rawValue), code length: \(code.count)")

        guard let pending = pendingAuth, pending.provider == provider else {
            NSLog("OAuth: No pending auth for provider \(provider.rawValue). pendingAuth: \(pendingAuth?.provider.rawValue ?? "nil")")
            return
        }

        // Validate state parameter to prevent CSRF attacks (REQUIRED)
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let returnedState = urlComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let returnedState = returnedState, returnedState == pending.state else {
            NSLog("OAuth: State parameter missing or mismatched — possible CSRF attack")
            NotificationCenter.default.post(
                name: .oauthFailed,
                object: nil,
                userInfo: ["provider": provider, "error": "Authentication failed: security validation error"]
            )
            pendingAuth = nil
            return
        }

        NSLog("OAuth: Exchanging code for token...")

        // Exchange code for token
        Task {
            await exchangeCodeForToken(
                provider: provider,
                code: code,
                codeVerifier: pending.codeVerifier
            )
        }
    }

    // MARK: - Token Exchange

    private func exchangeCodeForToken(provider: OAuthProvider, code: String, codeVerifier: String, redirectUri: String? = nil) async {
        var request = URLRequest(url: URL(string: provider.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Use provided redirect URI or fall back to provider's default
        let callbackURL = redirectUri ?? provider.callbackURL

        // Build request body
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: provider.clientId),
            URLQueryItem(name: "client_secret", value: provider.clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: callbackURL),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]

        // Add code_verifier only for PKCE providers
        if provider.usesPKCE {
            bodyComponents.queryItems?.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
        }

        let bodyString = bodyComponents.query ?? ""
        request.httpBody = bodyString.data(using: .utf8)

        // Log request details (mask sensitive data)
        let maskedBody = bodyString
            .replacingOccurrences(of: code, with: "CODE_REDACTED")
            .replacingOccurrences(of: codeVerifier, with: "VERIFIER_REDACTED")
            .replacingOccurrences(of: provider.clientSecret, with: "SECRET_REDACTED")
        NSLog("OAuth: Token request body: \(maskedBody)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("OAuth: Token exchange failed: \(errorBody)")
                throw OAuthError.tokenExchangeFailed(errorBody)
            }

            // Parse response based on provider
            let tokenResponse = try parseTokenResponse(data: data, provider: provider)

            // Store token and fetch resources
            await storeToken(provider: provider, token: tokenResponse)

            // Clear pending auth
            pendingAuth = nil

            NSLog("OAuth: Successfully authenticated with \(provider.rawValue)")

        } catch {
            NSLog("OAuth: Token exchange error: \(error)")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .oauthFailed,
                    object: nil,
                    userInfo: ["provider": provider, "error": error.localizedDescription]
                )
            }
        }
    }

    private func parseTokenResponse(data: Data, provider: OAuthProvider) throws -> TokenResponse {
        let responseString = String(data: data, encoding: .utf8) ?? "(binary data)"
        NSLog("OAuth: Token response length: \(responseString.count) bytes")

        // Try JSON first (GitHub returns JSON when Accept: application/json is set)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for error response first - GitHub returns 200 even for errors!
            if let error = json["error"] as? String {
                let errorDescription = json["error_description"] as? String ?? "Unknown error"
                NSLog("OAuth: GitHub returned error: \(error) - \(errorDescription)")
                throw OAuthError.tokenExchangeFailed("\(error): \(errorDescription)")
            }

            // Parse successful response
            if let accessToken = json["access_token"] as? String {
                let refreshToken = json["refresh_token"] as? String
                let expiresIn = json["expires_in"] as? Int
                let scope = json["scope"] as? String
                NSLog("OAuth: Successfully parsed access token (scope: \(scope ?? "none"))")
                return TokenResponse(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresIn: expiresIn,
                    scope: scope
                )
            }
        }

        // Try URL-encoded format (GitHub's default without Accept header)
        var components = URLComponents()
        components.query = responseString

        // Check for error in URL-encoded format
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? "Unknown error"
            NSLog("OAuth: GitHub returned error (URL-encoded): \(error) - \(errorDescription)")
            throw OAuthError.tokenExchangeFailed("\(error): \(errorDescription)")
        }

        // Parse successful URL-encoded response
        if let accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value {
            let refreshToken = components.queryItems?.first(where: { $0.name == "refresh_token" })?.value
            let scope = components.queryItems?.first(where: { $0.name == "scope" })?.value
            NSLog("OAuth: Successfully parsed access token from URL-encoded (scope: \(scope ?? "none"))")
            return TokenResponse(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: nil,
                scope: scope
            )
        }

        NSLog("OAuth: Could not parse response - no access_token or error found")
        throw OAuthError.invalidTokenResponse
    }

    private func storeToken(provider: OAuthProvider, token: TokenResponse) async {
        let dataSource = provider.dataSourceType

        // Store access token
        DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_access_token", value: token.accessToken)

        // Store refresh token if available
        if let refreshToken = token.refreshToken {
            DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_refresh_token", value: refreshToken)
        }

        // Store expiry if available
        if let expiresIn = token.expiresIn {
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_token_expiry", value: ISO8601DateFormatter().string(from: expiryDate))
        }

        // Mark as OAuth authenticated
        DataSourceConfig.shared.setValue(for: dataSource, field: "auth_method", value: "oauth")

        // Provider-specific post-auth setup
        switch provider {
        case .atlassian:
            await fetchAtlassianResources(accessToken: token.accessToken)
        case .github:
            await fetchGitHubUser(accessToken: token.accessToken)
        }

        // Enable the data source
        DataSourceConfig.shared.setEnabled(dataSource, enabled: true)

        // Post success notification
        await MainActor.run {
            NotificationCenter.default.post(
                name: .oauthCompleted,
                object: nil,
                userInfo: ["provider": provider]
            )
        }
    }

    /// Fetch Atlassian accessible resources to get cloudId and site URL
    private func fetchAtlassianResources(accessToken: String) async {
        guard let url = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let resources = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstSite = resources.first,
               let cloudId = firstSite["id"] as? String,
               let siteName = firstSite["name"] as? String,
               let siteUrl = firstSite["url"] as? String {

                NSLog("OAuth: Found Atlassian site: \(siteName) (cloudId: \(cloudId))")

                // Store cloudId and site URL for API calls
                DataSourceConfig.shared.setValue(for: .confluence, field: "cloudId", value: cloudId)
                DataSourceConfig.shared.setValue(for: .confluence, field: "siteUrl", value: siteUrl)
                DataSourceConfig.shared.setValue(for: .confluence, field: "siteName", value: siteName)
                
                // Fetch current user info
                await fetchCurrentUser(accessToken: accessToken)
            }
        } catch {
            NSLog("OAuth: Failed to fetch accessible resources: \(error)")
        }
    }
    
    /// Fetches the current user's info from Atlassian API
    private func fetchCurrentUser(accessToken: String) async {
        guard let url = URL(string: "https://api.atlassian.com/me") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let userInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Extract user details
                let accountId = userInfo["account_id"] as? String
                let email = userInfo["email"] as? String
                let displayName = userInfo["name"] as? String ?? userInfo["display_name"] as? String
                let nickname = userInfo["nickname"] as? String
                
                NSLog("OAuth: Current user - \(displayName ?? "unknown") (\(email ?? accountId ?? "no id"))")
                
                // Store user info for JQL queries
                if let accountId = accountId {
                    DataSourceConfig.shared.setValue(for: .confluence, field: "userAccountId", value: accountId)
                }
                if let email = email {
                    DataSourceConfig.shared.setValue(for: .confluence, field: "userEmail", value: email)
                }
                if let displayName = displayName {
                    DataSourceConfig.shared.setValue(for: .confluence, field: "userDisplayName", value: displayName)
                }
                if let nickname = nickname {
                    DataSourceConfig.shared.setValue(for: .confluence, field: "userNickname", value: nickname)
                }
            }
        } catch {
            NSLog("OAuth: Failed to fetch current user: \(error)")
        }
    }

    /// Fetches GitHub user info to get the username (owner) for API calls
    private func fetchGitHubUser(accessToken: String) async {
        guard let url = URL(string: "https://api.github.com/user") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("ConversationAssistant", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let userInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let login = userInfo["login"] as? String
                let name = userInfo["name"] as? String

                NSLog("OAuth: GitHub user - \(name ?? "unknown") (@\(login ?? "unknown"))")

                // Store username as owner for GitHubClient
                if let login = login {
                    DataSourceConfig.shared.setValue(for: .github, field: "owner", value: login)
                }

                // Set empty repo - will use org: search by default
                DataSourceConfig.shared.setValue(for: .github, field: "repo", value: "")
            }
        } catch {
            NSLog("OAuth: Failed to fetch GitHub user: \(error)")
        }
    }

    // MARK: - PKCE Helpers

    /// Generates a random code verifier (43-128 characters)
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncodedString()
    }

    /// Generates code challenge from verifier using SHA256
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Disconnect

    /// Removes OAuth tokens for a provider
    func disconnect(provider: OAuthProvider) {
        let dataSource = provider.dataSourceType
        DataSourceConfig.shared.clearValue(for: dataSource, field: "oauth_access_token")
        DataSourceConfig.shared.clearValue(for: dataSource, field: "oauth_refresh_token")
        DataSourceConfig.shared.clearValue(for: dataSource, field: "oauth_token_expiry")
        DataSourceConfig.shared.clearValue(for: dataSource, field: "auth_method")
        DataSourceConfig.shared.setEnabled(dataSource, enabled: false)

        NotificationCenter.default.post(name: .dataSourcesUpdated, object: nil)
    }

    // MARK: - Check Connection Status

    /// Returns true if provider is connected via OAuth
    func isConnected(provider: OAuthProvider) -> Bool {
        let dataSource = provider.dataSourceType
        guard let authMethod = DataSourceConfig.shared.getValue(for: dataSource, field: "auth_method"),
              authMethod == "oauth",
              let token = DataSourceConfig.shared.getValue(for: dataSource, field: "oauth_access_token"),
              !token.isEmpty else {
            return false
        }
        return true
    }

    /// Gets the access token for a provider (for API calls)
    func getAccessToken(for provider: OAuthProvider) -> String? {
        let dataSource = provider.dataSourceType
        return DataSourceConfig.shared.getValue(for: dataSource, field: "oauth_access_token")
    }

    // MARK: - Token Expiry & Refresh

    /// Check if token is expired or about to expire (within 5 minutes)
    func isTokenExpired(for provider: OAuthProvider) -> Bool {
        let dataSource = provider.dataSourceType

        guard let expiryString = DataSourceConfig.shared.getValue(for: dataSource, field: "oauth_token_expiry"),
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            // No expiry stored - GitHub tokens don't expire, Atlassian should have expiry
            // If no expiry for Atlassian, assume it might be expired
            return provider == .atlassian
        }

        // Consider token expired if less than 5 minutes remaining
        let bufferTime: TimeInterval = 5 * 60
        return Date().addingTimeInterval(bufferTime) >= expiryDate
    }

    /// Check if we have a refresh token for this provider
    func hasRefreshToken(for provider: OAuthProvider) -> Bool {
        let dataSource = provider.dataSourceType
        guard let refreshToken = DataSourceConfig.shared.getValue(for: dataSource, field: "oauth_refresh_token"),
              !refreshToken.isEmpty else {
            return false
        }
        return true
    }

    /// Get a valid access token, refreshing if necessary
    /// Returns nil if not connected or refresh fails
    /// Deduplicates concurrent refresh requests to prevent token race conditions
    func getValidAccessToken(for provider: OAuthProvider) async -> String? {
        guard isConnected(provider: provider) else {
            return nil
        }

        // If token is not expired, return it
        if !isTokenExpired(for: provider) {
            return getAccessToken(for: provider)
        }

        // Token is expired - try to refresh
        NSLog("OAuth: Token expired for \(provider.displayName), attempting refresh...")

        guard hasRefreshToken(for: provider) else {
            NSLog("OAuth: No refresh token available for \(provider.displayName)")
            return nil
        }

        // Deduplicate: if a refresh is already in progress, wait for it
        if let existingTask = refreshTasks[provider] {
            NSLog("OAuth: Reusing in-flight refresh for \(provider.displayName)")
            let success = await existingTask.value
            return success ? getAccessToken(for: provider) : nil
        }

        // Start new refresh task
        let task = Task { await refreshToken(for: provider) }
        refreshTasks[provider] = task
        let success = await task.value
        refreshTasks[provider] = nil

        return success ? getAccessToken(for: provider) : nil
    }

    /// Refresh the access token using the refresh token
    func refreshToken(for provider: OAuthProvider) async -> Bool {
        let dataSource = provider.dataSourceType

        guard let refreshToken = DataSourceConfig.shared.getValue(for: dataSource, field: "oauth_refresh_token"),
              !refreshToken.isEmpty else {
            NSLog("OAuth: No refresh token for \(provider.displayName)")
            return false
        }

        var request = URLRequest(url: URL(string: provider.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: provider.clientId),
            URLQueryItem(name: "client_secret", value: provider.clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        let bodyString = bodyComponents.query ?? ""
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("OAuth: Token refresh failed (\(httpResponse.statusCode)): \(errorBody)")
                throw OAuthError.tokenExchangeFailed(errorBody)
            }

            // Parse response
            let tokenResponse = try parseTokenResponse(data: data, provider: provider)

            // Store new tokens
            DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_access_token", value: tokenResponse.accessToken)

            if let newRefreshToken = tokenResponse.refreshToken {
                DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_refresh_token", value: newRefreshToken)
            }

            if let expiresIn = tokenResponse.expiresIn {
                let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                DataSourceConfig.shared.setValue(for: dataSource, field: "oauth_token_expiry", value: ISO8601DateFormatter().string(from: expiryDate))
            }

            NSLog("OAuth: Successfully refreshed token for \(provider.displayName)")
            return true

        } catch {
            NSLog("OAuth: Token refresh error for \(provider.displayName): \(error)")
            return false
        }
    }
}

// MARK: - Supporting Types

struct TokenResponse {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?
}

enum OAuthError: Error, LocalizedError {
    case invalidResponse
    case tokenExchangeFailed(String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .invalidTokenResponse:
            return "Could not parse token response"
        }
    }
}

// MARK: - Base64 URL Encoding

extension Data {
    /// Base64 URL encoding (no padding, URL-safe characters)
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
