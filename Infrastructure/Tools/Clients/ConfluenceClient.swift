import Foundation

/// Client for searching Confluence documentation
class ConfluenceClient: Tool {
    static let shared = ConfluenceClient()

    let name = "search_documentation"
    let displayName = "Confluence"

    var supportedToolNames: [String] {
        ["search_documentation", "get_confluence_page", "list_confluence_spaces", "create_confluence_page"]
    }

    private init() {}

    func execute(toolName: String, input: [String: Any]) async throws -> ToolResult {
        switch toolName {
        case "get_confluence_page":
            return try await getPage(input: input)
        case "list_confluence_spaces":
            return try await listSpaces(input: input)
        case "create_confluence_page":
            return try await createPage(input: input)
        default:
            return try await execute(input: input)
        }
    }

    func testConnection() async -> ToolResult {
        do {
            let result = try await listSpaces(input: ["limit": "1"])
            if result.success {
                return .success(content: "Confluence connected")
            }
            return result
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    var isConfigured: Bool {
        // Check OAuth first (with cloudId), then Basic Auth
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence) {
            // OAuth requires cloudId - if missing, we can still try to fetch it
            return true
        }
        return DataSourceConfig.shared.confluenceConfig != nil
    }

    /// Get auth header with automatic token refresh for OAuth
    private func getAuthHeader() async -> String {
        // Use OAuth if available - with automatic token refresh
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence) {
            if let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
                return "Bearer \(token)"
            }
            // Token refresh failed - fall through to try basic auth
            NSLog("Confluence: OAuth token refresh failed, trying basic auth...")
        }

        // Fall back to Basic Auth
        guard let config = DataSourceConfig.shared.confluenceConfig else { return "" }
        let credentials = "\(config.username):\(config.apiToken)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    func execute(input: [String: Any]) async throws -> ToolResult {
        guard let query = input["query"] as? String else {
            throw ToolError.missingParameter("query")
        }

        let space = input["space"] as? String

        // Build CQL query (escape quotes to prevent injection)
        let escapedQuery = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var cql = "text ~ \"\(escapedQuery)\""
        if let space = space {
            let escapedSpace = space.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            cql += " AND space = \"\(escapedSpace)\""
        }
        cql += " ORDER BY lastModified DESC"

        // Determine API URL based on auth method
        let (apiUrl, siteUrl) = try await getApiUrl(cql: cql)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ToolError.executionFailed("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = parseConfluenceError(statusCode: httpResponse.statusCode, data: data)
                return .success(content: errorMessage)  // Return as success so Claude can inform user
            }

            let results = try JSONDecoder().decode(ConfluenceSearchResponse.self, from: data)

            if results.results.isEmpty {
                return .success(content: "No results found for: \(query)")
            }

            // Format results for Claude
            let content = results.results.map { page in
                """
                ## \(page.title)
                URL: \(siteUrl)/wiki\(page._links.webui)
                \(page.excerpt ?? "No excerpt available")
                """
            }.joined(separator: "\n\n---\n\n")

            return .success(content: content)

        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed(error.localizedDescription)
        }
    }

    private func getApiUrl(cql: String) async throws -> (apiUrl: URL, siteUrl: String) {
        guard let encodedCql = cql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ToolError.executionFailed("Invalid CQL query")
        }

        // OAuth: Use Atlassian API with cloudId (with automatic token refresh)
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {

            // Fetch cloudId if missing
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            var siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")

            if cloudId == nil || siteUrl == nil {
                NSLog("Confluence: cloudId missing, fetching accessible resources...")
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
                siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")
            }

            guard let cloudId = cloudId, let siteUrl = siteUrl else {
                throw ToolError.executionFailed("Could not determine Confluence site. Please reconnect in Settings.")
            }

            let urlString = "https://api.atlassian.com/ex/confluence/\(cloudId)/wiki/rest/api/content/search?cql=\(encodedCql)&limit=5&expand=body.excerpt"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid OAuth API URL")
            }
            return (url, siteUrl)
        }

        // Basic Auth: Use direct Confluence URL
        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Confluence")
        }

        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseUrl)/wiki/rest/api/content/search?cql=\(encodedCql)&limit=5&expand=body.excerpt"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    /// Fetch accessible resources from Atlassian API
    private func fetchAccessibleResources(token: String) async throws {
        guard let url = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed("Failed to fetch Confluence sites")
        }

        guard let resources = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstSite = resources.first,
              let cloudId = firstSite["id"] as? String,
              let siteUrl = firstSite["url"] as? String else {
            throw ToolError.executionFailed("No Confluence sites found")
        }

        let siteName = firstSite["name"] as? String ?? "Unknown"
        NSLog("Confluence: Found site \(siteName) (cloudId: \(cloudId))")

        DataSourceConfig.shared.setValue(for: .confluence, field: "cloudId", value: cloudId)
        DataSourceConfig.shared.setValue(for: .confluence, field: "siteUrl", value: siteUrl)
        DataSourceConfig.shared.setValue(for: .confluence, field: "siteName", value: siteName)
    }

    // MARK: - List Spaces

    /// List Confluence spaces
    func listSpaces(input: [String: Any]) async throws -> ToolResult {
        let limitStr = (input["limit"] as? String) ?? "20"
        let limit = Int(limitStr) ?? 20

        let (apiUrl, siteUrl) = try await getSpacesApiUrl(limit: limit)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = parseConfluenceError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            return .success(content: errorMessage)
        }

        let results = try JSONDecoder().decode(ConfluenceSpacesResponse.self, from: data)

        if results.results.isEmpty {
            return .success(content: "No Confluence spaces found.")
        }

        let content = results.results.prefix(limit).map { space in
            """
            ## \(space.name) (\(space.key))
            **Type:** \(space.type.capitalized)
            URL: \(siteUrl)/wiki\(space._links.webui)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(results.results.count) spaces:\n\n\(content)")
    }

    private func getSpacesApiUrl(limit: Int) async throws -> (apiUrl: URL, siteUrl: String) {
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            var siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")

            if cloudId == nil || siteUrl == nil {
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
                siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")
            }

            guard let cloudId = cloudId, let siteUrl = siteUrl else {
                throw ToolError.executionFailed("Could not determine Confluence site.")
            }

            let urlString = "https://api.atlassian.com/ex/confluence/\(cloudId)/wiki/rest/api/space?limit=\(limit)"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Confluence")
        }

        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseUrl)/wiki/rest/api/space?limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    // MARK: - Get Page

    /// Get full Confluence page content
    func getPage(input: [String: Any]) async throws -> ToolResult {
        let pageId = input["page_id"] as? String
        let title = input["title"] as? String

        // If we have a title but no page ID, search for the page
        if let title = title, pageId == nil {
            // Search for the page by title
            let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let cql = "title = \"\(escapedTitle)\""
            guard let encodedCql = cql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw ToolError.executionFailed("Invalid search query")
            }

            let (searchUrl, siteUrl) = try await getApiUrl(cql: encodedCql)

            var searchRequest = URLRequest(url: searchUrl)
            searchRequest.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
            searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")

            let (searchData, searchResponse) = try await URLSession.shared.data(for: searchRequest)

            guard let httpResponse = searchResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return .success(content: "⚠️ Could not find page with title: \(title)")
            }

            let results = try JSONDecoder().decode(ConfluenceSearchResponse.self, from: searchData)

            guard let firstPage = results.results.first else {
                return .success(content: "No page found with title: \(title)")
            }

            // Fetch the full page content
            return try await fetchPageContent(pageId: firstPage.id, siteUrl: siteUrl)
        }

        guard let pageId = pageId else {
            throw ToolError.missingParameter("page_id or title")
        }

        let (_, siteUrl) = try await getSpacesApiUrl(limit: 1)
        return try await fetchPageContent(pageId: pageId, siteUrl: siteUrl)
    }

    private func fetchPageContent(pageId: String, siteUrl: String) async throws -> ToolResult {
        let (apiUrl, _) = try await getPageApiUrl(pageId: pageId)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = parseConfluenceError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            return .success(content: errorMessage)
        }

        let page = try JSONDecoder().decode(ConfluencePageResponse.self, from: data)

        // Convert HTML to plain text (basic cleanup)
        var content = page.body?.view?.value ?? page.body?.storage?.value ?? "No content"
        content = stripHtml(content)

        return .success(content: """
            # \(page.title)

            URL: \(siteUrl)/wiki\(page._links.webui)

            ---

            \(content)
            """)
    }

    private func getPageApiUrl(pageId: String) async throws -> (apiUrl: URL, siteUrl: String) {
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            var siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")

            if cloudId == nil || siteUrl == nil {
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
                siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")
            }

            guard let cloudId = cloudId, let siteUrl = siteUrl else {
                throw ToolError.executionFailed("Could not determine Confluence site.")
            }

            let urlString = "https://api.atlassian.com/ex/confluence/\(cloudId)/wiki/rest/api/content/\(pageId)?expand=body.view,body.storage"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Confluence")
        }

        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseUrl)/wiki/rest/api/content/\(pageId)?expand=body.view,body.storage"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    // MARK: - Create Page

    func createPage(input: [String: Any]) async throws -> ToolResult {
        guard let space = input["space"] as? String else {
            throw ToolError.missingParameter("space")
        }
        guard let title = input["title"] as? String else {
            throw ToolError.missingParameter("title")
        }
        guard let content = input["content"] as? String else {
            throw ToolError.missingParameter("content")
        }

        let body: [String: Any] = [
            "type": "page",
            "title": title,
            "space": ["key": space],
            "body": [
                "storage": [
                    "value": content,
                    "representation": "storage"
                ]
            ]
        ]

        let url = try await getCreatePageApiUrl()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseConfluenceError(statusCode: httpResponse.statusCode, data: data)
            return .success(content: errorMessage)
        }

        let page = try JSONDecoder().decode(ConfluencePageResponse.self, from: data)
        let (_, siteUrl) = try await getSpacesApiUrl(limit: 1)
        return .success(content: "Created page: **\(page.title)**\nURL: \(siteUrl)/wiki\(page._links.webui)")
    }

    private func getCreatePageApiUrl() async throws -> URL {
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            if cloudId == nil {
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            }
            guard let cloudId = cloudId else {
                throw ToolError.executionFailed("Could not determine Confluence site.")
            }
            guard let url = URL(string: "https://api.atlassian.com/ex/confluence/\(cloudId)/wiki/rest/api/content") else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return url
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Confluence")
        }
        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseUrl)/wiki/rest/api/content") else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return url
    }

    /// Strip HTML tags from content (basic)
    private func stripHtml(_ html: String) -> String {
        var result = html
        // Remove common HTML tags
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        // Clean up extra whitespace
        result = result.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse Confluence API errors into user-friendly messages
    private func parseConfluenceError(statusCode: Int, data: Data) -> String {
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        
        switch statusCode {
        case 400:
            if rawBody.contains("does not exist") || rawBody.contains("not found") {
                return "⚠️ Confluence Search: No matching pages found. Try a different search term."
            }
            return "⚠️ Confluence Search: Invalid search query. Try a simpler search term."
        case 401:
            return "⚠️ Confluence Search: Authentication failed. Please reconnect Atlassian in Settings (⌘,)."
        case 403:
            return "⚠️ Confluence Search: Access denied. You may not have permission to search this space."
        case 404:
            return "⚠️ Confluence Search: No results found. The page or space doesn't exist."
        case 410:
            return "⚠️ Confluence Search: Connection expired. Please reconnect Atlassian in Settings (⌘,) to refresh your credentials."
        case 429:
            return "⚠️ Confluence Search: Rate limited. Please wait a moment and try again."
        case 500...599:
            return "⚠️ Confluence Search: Atlassian server error. Please try again later."
        default:
            NSLog("Confluence API error \(statusCode): \(rawBody)")
            return "⚠️ Confluence Search: Unable to complete search (error \(statusCode)). Please check your connection."
        }
    }
}

// MARK: - Response Models

private struct ConfluenceSearchResponse: Codable {
    let results: [ConfluencePage]
}

private struct ConfluencePage: Codable {
    let id: String
    let title: String
    let excerpt: String?
    let _links: ConfluenceLinks
}

private struct ConfluenceLinks: Codable {
    let webui: String
}

// MARK: - Space Models

private struct ConfluenceSpacesResponse: Codable {
    let results: [ConfluenceSpace]
}

private struct ConfluenceSpace: Codable {
    let id: Int
    let key: String
    let name: String
    let type: String
    let _links: ConfluenceLinks
}

// MARK: - Page Content Models

private struct ConfluencePageResponse: Codable {
    let id: String
    let title: String
    let body: ConfluenceBody?
    let _links: ConfluenceLinks
}

private struct ConfluenceBody: Codable {
    let storage: ConfluenceStorage?
    let view: ConfluenceStorage?
}

private struct ConfluenceStorage: Codable {
    let value: String
}
