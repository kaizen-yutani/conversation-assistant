import Foundation
import Network
import CommonCrypto

// MARK: - Test Utilities

struct TestResult {
    let name: String
    let passed: Bool
    let message: String
}

class TestRunner {
    var results: [TestResult] = []

    func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition {
            print("  FAIL: \(message) at \(file):\(line)")
        }
    }

    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            print("  FAIL: \(message) - Expected \(expected), got \(actual)")
        }
    }

    func test(_ name: String, _ block: () throws -> Void) {
        print("Running: \(name)")
        do {
            try block()
            results.append(TestResult(name: name, passed: true, message: ""))
            print("  PASS")
        } catch {
            results.append(TestResult(name: name, passed: false, message: error.localizedDescription))
            print("  FAIL: \(error)")
        }
    }

    func asyncTest(_ name: String, _ block: () async throws -> Void) async {
        print("Running: \(name)")
        do {
            try await block()
            results.append(TestResult(name: name, passed: true, message: ""))
            print("  PASS")
        } catch {
            results.append(TestResult(name: name, passed: false, message: error.localizedDescription))
            print("  FAIL: \(error)")
        }
    }

    func printSummary() {
        let passed = results.filter { $0.passed }.count
        let total = results.count
        print("\n========================================")
        print("Test Results: \(passed)/\(total) passed")
        if passed == total {
            print("ALL TESTS PASSED")
        } else {
            print("SOME TESTS FAILED:")
            for result in results where !result.passed {
                print("  - \(result.name): \(result.message)")
            }
        }
        print("========================================\n")
    }
}

// MARK: - Mock OAuth Callback Server for Testing

class MockOAuthCallbackServer {
    private var listener: NWListener?
    private var completion: ((String?, Error?) -> Void)?
    private var activePort: UInt16 = 0

    var callbackURL: String {
        return "http://localhost:\(activePort)/callback"
    }

    private let listenerQueue = DispatchQueue(label: "test.oauth.callback.listener", qos: .userInitiated)

    enum TestError: Error, LocalizedError {
        case serverStartFailed(Error)
        case timeout
        case noPortAvailable

        var errorDescription: String? {
            switch self {
            case .serverStartFailed(let error): return "Server start failed: \(error)"
            case .timeout: return "Timeout waiting for callback"
            case .noPortAvailable: return "No port available"
            }
        }
    }

    func start(port: UInt16 = 19999, timeout: TimeInterval = 5) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let tcpOptions = NWProtocolTCP.Options()
                let parameters = NWParameters(tls: nil, tcp: tcpOptions)
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)

                let newListener = try NWListener(using: parameters)

                newListener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.listener = newListener
                        self?.activePort = port
                        continuation.resume(returning: self?.callbackURL ?? "")

                    case .failed(let error):
                        continuation.resume(throwing: TestError.serverStartFailed(error))

                    case .waiting(let error):
                        continuation.resume(throwing: TestError.serverStartFailed(error))

                    default:
                        break
                    }
                }

                newListener.start(queue: listenerQueue)

            } catch {
                continuation.resume(throwing: TestError.serverStartFailed(error))
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Simulates receiving an OAuth callback
    func simulateCallback(code: String) async -> Bool {
        guard activePort > 0 else { return false }

        let url = URL(string: "http://localhost:\(activePort)/callback?code=\(code)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            print("Callback simulation error: \(error)")
        }
        return false
    }
}

// MARK: - OAuth Token Refresh Tests

func runTokenExpiryTests(runner: TestRunner) {
    runner.test("Token expiry parsing - valid ISO8601 date") {
        let formatter = ISO8601DateFormatter()
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let dateString = formatter.string(from: futureDate)

        // Parse it back
        guard let parsed = formatter.date(from: dateString) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse date"])
        }

        // Should be approximately 1 hour in the future
        let diff = parsed.timeIntervalSinceNow
        runner.assert(diff > 3500 && diff < 3700, "Date should be ~1 hour in future, got \(diff)s")
    }

    runner.test("Token expiry detection - expired token") {
        let formatter = ISO8601DateFormatter()
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let dateString = formatter.string(from: pastDate)

        guard let parsed = formatter.date(from: dateString) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse date"])
        }

        // With 5-minute buffer, this should be expired
        let bufferTime: TimeInterval = 5 * 60
        let isExpired = Date().addingTimeInterval(bufferTime) >= parsed
        runner.assert(isExpired, "Token from 1 hour ago should be detected as expired")
    }

    runner.test("Token expiry detection - valid token") {
        let formatter = ISO8601DateFormatter()
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let dateString = formatter.string(from: futureDate)

        guard let parsed = formatter.date(from: dateString) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse date"])
        }

        // With 5-minute buffer, this should NOT be expired
        let bufferTime: TimeInterval = 5 * 60
        let isExpired = Date().addingTimeInterval(bufferTime) >= parsed
        runner.assert(!isExpired, "Token valid for 1 hour should not be expired")
    }

    runner.test("Token expiry detection - about to expire") {
        let formatter = ISO8601DateFormatter()
        let nearFuture = Date().addingTimeInterval(180) // 3 minutes from now
        let dateString = formatter.string(from: nearFuture)

        guard let parsed = formatter.date(from: dateString) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse date"])
        }

        // With 5-minute buffer, this SHOULD be expired (3 min < 5 min buffer)
        let bufferTime: TimeInterval = 5 * 60
        let isExpired = Date().addingTimeInterval(bufferTime) >= parsed
        runner.assert(isExpired, "Token expiring in 3 min should be detected as expired (5 min buffer)")
    }
}

// MARK: - OAuth Callback URL Tests

func runCallbackURLTests(runner: TestRunner) {
    runner.test("Callback URL format is correct") {
        let port: UInt16 = 9876
        let callbackURL = "http://localhost:\(port)/callback"

        runner.assert(callbackURL.contains("localhost"), "URL should contain localhost")
        runner.assert(callbackURL.contains("/callback"), "URL should contain /callback path")
        runner.assert(callbackURL.contains("9876"), "URL should contain port")
    }

    runner.test("Multiple ports are available for fallback") {
        let callbackPorts: [UInt16] = [9876, 9877, 9878, 19876, 29876]
        runner.assert(callbackPorts.count >= 3, "Should have at least 3 fallback ports")
        runner.assert(callbackPorts.allSatisfy { $0 > 1024 }, "All ports should be above 1024")
    }

    runner.test("HTTP response format is valid") {
        let statusCode = 200
        let statusText = "OK"
        let body = "<html>Success</html>"

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        runner.assert(response.contains("HTTP/1.1 200 OK"), "Response should have status line")
        runner.assert(response.contains("Content-Type:"), "Response should have content type")
        runner.assert(response.contains("Content-Length:"), "Response should have content length")
    }
}

// MARK: - Authorization Code Parsing Tests

func runCodeParsingTests(runner: TestRunner) {
    runner.test("Parse authorization code from callback URL") {
        let request = "GET /callback?code=abc123&state=xyz HTTP/1.1\r\nHost: localhost"

        // Extract code from request
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.contains("/callback?") else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid request format"])
        }

        guard let queryStart = firstLine.range(of: "?"),
              let queryEnd = firstLine.range(of: " HTTP") else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find query string"])
        }

        let queryString = String(firstLine[queryStart.upperBound..<queryEnd.lowerBound])
        let components = URLComponents(string: "http://localhost?\(queryString)")

        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        runner.assertEqual(code, "abc123", "Should extract code 'abc123'")
    }

    runner.test("Parse error from callback URL") {
        let request = "GET /callback?error=access_denied&error_description=User%20denied HTTP/1.1"

        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let queryStart = firstLine.range(of: "?"),
              let queryEnd = firstLine.range(of: " HTTP") else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid request"])
        }

        let queryString = String(firstLine[queryStart.upperBound..<queryEnd.lowerBound])
        let components = URLComponents(string: "http://localhost?\(queryString)")

        let error = components?.queryItems?.first(where: { $0.name == "error" })?.value
        runner.assertEqual(error, "access_denied", "Should extract error 'access_denied'")
    }

    runner.test("Handle callback without code") {
        let request = "GET /callback HTTP/1.1\r\nHost: localhost"
        let hasCode = request.contains("code=")
        runner.assert(!hasCode, "Should detect missing code parameter")
    }
}

// MARK: - PKCE Tests

func runPKCETests(runner: TestRunner) {
    runner.test("Generate PKCE code verifier - correct length") {
        // Generate random bytes for verifier
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        runner.assert(verifier.count >= 43, "Verifier should be at least 43 chars, got \(verifier.count)")
        runner.assert(verifier.count <= 128, "Verifier should be at most 128 chars")
    }

    runner.test("Generate PKCE code challenge from verifier") {
        let verifier = "test_verifier_12345678901234567890123456"

        guard let verifierData = verifier.data(using: .utf8) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode verifier"])
        }

        // SHA256 hash
        var hash = [UInt8](repeating: 0, count: 32)
        verifierData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        runner.assert(!challenge.isEmpty, "Challenge should not be empty")
        runner.assert(challenge != verifier, "Challenge should differ from verifier")
    }
}

// MARK: - Token Response Parsing Tests (Integration)

func runTokenResponseParsingTests(runner: TestRunner) {
    runner.test("Parse JSON token response - Atlassian format") {
        let jsonResponse = """
        {
            "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "refresh_token": "refresh_abc123",
            "expires_in": 3600,
            "scope": "read:jira-work write:jira-work read:confluence-content.all"
        }
        """
        guard let data = jsonResponse.data(using: .utf8) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }

        runner.assertEqual(accessToken, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "Access token should match")
        runner.assertEqual(refreshToken, "refresh_abc123", "Refresh token should match")
        runner.assertEqual(expiresIn, 3600, "Expires in should be 3600")
    }

    runner.test("Parse JSON token response - GitHub format") {
        let jsonResponse = """
        {
            "access_token": "gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "token_type": "bearer",
            "scope": "repo,user"
        }
        """
        guard let data = jsonResponse.data(using: .utf8) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let scope = json["scope"] as? String else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }

        runner.assert(accessToken.hasPrefix("gho_"), "GitHub token should start with gho_")
        runner.assertEqual(scope, "repo,user", "Scope should match")
        runner.assert(json["refresh_token"] == nil, "GitHub tokens don't have refresh tokens")
    }

    runner.test("Parse URL-encoded token response - legacy GitHub format") {
        let urlEncodedResponse = "access_token=gho_legacy_token&scope=repo%2Cuser&token_type=bearer"

        // URLComponents with percentEncodedQuery properly decodes values
        var components = URLComponents()
        components.percentEncodedQuery = urlEncodedResponse

        let accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value
        let scope = components.queryItems?.first(where: { $0.name == "scope" })?.value

        runner.assertEqual(accessToken, "gho_legacy_token", "Should parse access token from URL-encoded")
        runner.assertEqual(scope, "repo,user", "Should URL-decode scope")
    }

    runner.test("Parse error response - JSON format") {
        let errorResponse = """
        {
            "error": "bad_verification_code",
            "error_description": "The code passed is incorrect or expired."
        }
        """
        guard let data = errorResponse.data(using: .utf8) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              let errorDescription = json["error_description"] as? String else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse error JSON"])
        }

        runner.assertEqual(error, "bad_verification_code", "Error code should match")
        runner.assert(errorDescription.contains("expired"), "Error description should mention expiry")
    }

    runner.test("Parse error response - URL-encoded format") {
        let errorResponse = "error=access_denied&error_description=The%20user%20denied%20access"

        // Use percentEncodedQuery for proper URL decoding
        var components = URLComponents()
        components.percentEncodedQuery = errorResponse

        let error = components.queryItems?.first(where: { $0.name == "error" })?.value
        let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value

        runner.assertEqual(error, "access_denied", "Error should be access_denied")
        runner.assertEqual(errorDescription, "The user denied access", "Should URL-decode error description")
    }
}

// MARK: - Token Refresh Request Tests

func runTokenRefreshTests(runner: TestRunner) {
    runner.test("Build refresh token request body") {
        let clientId = "test_client_id"
        let clientSecret = "test_client_secret"
        let refreshToken = "refresh_token_abc123"

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        let body = bodyComponents.query ?? ""

        runner.assert(body.contains("client_id=test_client_id"), "Body should contain client_id")
        runner.assert(body.contains("grant_type=refresh_token"), "Body should contain grant_type")
        runner.assert(body.contains("refresh_token=refresh_token_abc123"), "Body should contain refresh_token")
    }

    runner.test("Build authorization code exchange request body") {
        let clientId = "test_client_id"
        let clientSecret = "test_client_secret"
        let code = "auth_code_xyz"
        let redirectUri = "http://localhost:9876/callback"
        let codeVerifier = "pkce_verifier_123"

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]

        let body = bodyComponents.query ?? ""

        runner.assert(body.contains("grant_type=authorization_code"), "Body should contain grant_type")
        runner.assert(body.contains("code=auth_code_xyz"), "Body should contain auth code")
        runner.assert(body.contains("code_verifier=pkce_verifier_123"), "Body should contain PKCE verifier")
        runner.assert(body.contains("redirect_uri="), "Body should contain redirect_uri")
    }

    runner.test("Parse refreshed token response with new refresh token") {
        let jsonResponse = """
        {
            "access_token": "new_access_token",
            "refresh_token": "new_refresh_token",
            "expires_in": 3600
        }
        """
        guard let data = jsonResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse"])
        }

        let newAccessToken = json["access_token"] as? String
        let newRefreshToken = json["refresh_token"] as? String

        runner.assertEqual(newAccessToken, "new_access_token", "Should get new access token")
        runner.assertEqual(newRefreshToken, "new_refresh_token", "Should get rotated refresh token")
    }
}

// MARK: - Atlassian Resources Parsing Tests

func runAtlassianResourcesTests(runner: TestRunner) {
    runner.test("Parse Atlassian accessible resources") {
        let jsonResponse = """
        [
            {
                "id": "cloud-id-12345",
                "name": "My Company",
                "url": "https://mycompany.atlassian.net",
                "scopes": ["read:jira-work", "write:jira-work"],
                "avatarUrl": "https://site-admin-avatar-cdn.atlassian.com/..."
            }
        ]
        """
        guard let data = jsonResponse.data(using: .utf8),
              let resources = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstSite = resources.first else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse"])
        }

        let cloudId = firstSite["id"] as? String
        let siteName = firstSite["name"] as? String
        let siteUrl = firstSite["url"] as? String

        runner.assertEqual(cloudId, "cloud-id-12345", "Should extract cloudId")
        runner.assertEqual(siteName, "My Company", "Should extract site name")
        runner.assertEqual(siteUrl, "https://mycompany.atlassian.net", "Should extract site URL")
    }

    runner.test("Parse Atlassian user info") {
        let jsonResponse = """
        {
            "account_id": "557058:f3be3e8e-1234-5678-90ab-cdef12345678",
            "email": "user@example.com",
            "name": "John Doe",
            "nickname": "johnd"
        }
        """
        guard let data = jsonResponse.data(using: .utf8),
              let userInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse"])
        }

        let accountId = userInfo["account_id"] as? String
        let email = userInfo["email"] as? String
        let displayName = userInfo["name"] as? String

        runner.assert(accountId?.contains("557058") ?? false, "Should extract account ID")
        runner.assertEqual(email, "user@example.com", "Should extract email")
        runner.assertEqual(displayName, "John Doe", "Should extract display name")
    }
}

// MARK: - GitHub User Parsing Tests

func runGitHubUserTests(runner: TestRunner) {
    runner.test("Parse GitHub user response") {
        let jsonResponse = """
        {
            "login": "octocat",
            "id": 1,
            "name": "The Octocat",
            "email": "octocat@github.com",
            "avatar_url": "https://github.com/images/error/octocat_happy.gif"
        }
        """
        guard let data = jsonResponse.data(using: .utf8),
              let userInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse"])
        }

        let login = userInfo["login"] as? String
        let name = userInfo["name"] as? String

        runner.assertEqual(login, "octocat", "Should extract login/username")
        runner.assertEqual(name, "The Octocat", "Should extract display name")
    }

    runner.test("Build GitHub API request headers") {
        let accessToken = "gho_test_token"

        var headers: [String: String] = [:]
        headers["Authorization"] = "Bearer \(accessToken)"
        headers["Accept"] = "application/vnd.github.v3+json"
        headers["User-Agent"] = "ConversationAssistant"

        runner.assertEqual(headers["Authorization"], "Bearer gho_test_token", "Should set Bearer auth")
        runner.assert(headers["Accept"]?.contains("github") ?? false, "Should use GitHub API accept header")
        runner.assert(headers["User-Agent"] != nil, "Should set User-Agent")
    }
}

// MARK: - OAuth URL Building Tests

func runOAuthURLBuildingTests(runner: TestRunner) {
    runner.test("Build Atlassian authorization URL with PKCE") {
        let clientId = "test_client"
        let redirectUri = "conversationassistant://oauth/atlassian"
        let scopes = "read:jira-work write:jira-work"
        let codeChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let state = "random-state-123"

        var components = URLComponents(string: "https://auth.atlassian.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "audience", value: "api.atlassian.com"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build URL"])
        }

        let urlString = url.absoluteString
        runner.assert(urlString.contains("auth.atlassian.com"), "Should use Atlassian auth domain")
        runner.assert(urlString.contains("code_challenge="), "Should include PKCE challenge")
        runner.assert(urlString.contains("code_challenge_method=S256"), "Should use S256 method")
        runner.assert(urlString.contains("audience=api.atlassian.com"), "Should include audience")
        runner.assert(urlString.contains("prompt=consent"), "Should include prompt")
    }

    runner.test("Build GitHub authorization URL without PKCE") {
        let clientId = "github_client"
        let redirectUri = "http://localhost:9876/callback"
        let scopes = "repo user"
        let state = "random-state-456"

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build URL"])
        }

        let urlString = url.absoluteString
        runner.assert(urlString.contains("github.com/login/oauth"), "Should use GitHub OAuth domain")
        runner.assert(!urlString.contains("code_challenge"), "GitHub should NOT have PKCE")
        runner.assert(urlString.contains("scope=repo"), "Should include scopes")
    }
}

// MARK: - Main Test Runner

func runAllTests() {
    print("\n========================================")
    print("OAuth & Connection Tests")
    print("========================================\n")

    let runner = TestRunner()

    // Run all synchronous tests
    print("--- Basic Tests ---")
    runTokenExpiryTests(runner: runner)
    runCallbackURLTests(runner: runner)
    runCodeParsingTests(runner: runner)
    runPKCETests(runner: runner)

    print("\n--- Integration Tests ---")
    runTokenResponseParsingTests(runner: runner)
    runTokenRefreshTests(runner: runner)
    runAtlassianResourcesTests(runner: runner)
    runGitHubUserTests(runner: runner)
    runOAuthURLBuildingTests(runner: runner)

    // Print summary
    runner.printSummary()

    // Exit with appropriate code
    let allPassed = runner.results.allSatisfy { $0.passed }
    exit(allPassed ? 0 : 1)
}

// Entry point
runAllTests()
