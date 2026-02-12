import Foundation

/// Client for searching Jira issues (shares Atlassian OAuth with Confluence)
class JiraClient: Tool {
    static let shared = JiraClient()

    let name = "search_jira"
    let displayName = "Jira"

    var supportedToolNames: [String] {
        ["search_jira", "list_jira_projects", "get_sprint_info", "list_jira_boards", "create_jira_issue", "add_jira_comment"]
    }

    private init() {}

    func execute(toolName: String, input: [String: Any]) async throws -> ToolResult {
        switch toolName {
        case "list_jira_projects":
            return try await listProjects(input: input)
        case "get_sprint_info":
            return try await getSprintInfo(input: input)
        case "list_jira_boards":
            return try await listBoards(input: input)
        case "create_jira_issue":
            return try await createIssue(input: input)
        case "add_jira_comment":
            return try await addComment(input: input)
        default:
            return try await execute(input: input)
        }
    }

    func testConnection() async -> ToolResult {
        do {
            let result = try await listProjects(input: ["limit": "1"])
            if result.success {
                return .success(content: "Jira connected")
            }
            return result
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    /// Get a specific ticket by key (e.g., PROJ-123)
    func getTicket(key: String) async throws -> ToolResult {
        let (apiUrl, siteUrl) = try await getTicketApiUrl(key: key)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseJiraError(statusCode: httpResponse.statusCode, data: data)
            return .success(content: errorMessage)
        }

        let issue = try JSONDecoder().decode(JiraIssueDetail.self, from: data)

        let status = issue.fields.status?.name ?? "Unknown"
        let priority = issue.fields.priority?.name ?? "None"
        let assignee = issue.fields.assignee?.displayName ?? "Unassigned"
        let reporter = issue.fields.reporter?.displayName ?? "Unknown"
        let created = issue.fields.created ?? ""
        let updated = issue.fields.updated ?? ""
        let issueType = issue.fields.issuetype?.name ?? "Unknown"
        let description = issue.fields.description?.content?.first?.content?.first?.text ?? "No description"
        let parent = issue.fields.parent.map { "Parent: \($0.key) - \($0.fields.summary)" } ?? ""
        let labels = issue.fields.labels?.joined(separator: ", ") ?? ""
        let sprint = issue.fields.sprint?.name ?? ""

        let content = """
        # \(issue.key): \(issue.fields.summary)

        **Type:** \(issueType) | **Status:** \(status) | **Priority:** \(priority)
        **Assignee:** \(assignee) | **Reporter:** \(reporter)
        **Created:** \(created.prefix(10)) | **Updated:** \(updated.prefix(10))
        \(sprint.isEmpty ? "" : "**Sprint:** \(sprint)")
        \(labels.isEmpty ? "" : "**Labels:** \(labels)")
        \(parent)

        **URL:** \(siteUrl)/browse/\(issue.key)

        ## Description
        \(description)
        """

        return .success(content: content)
    }

    private func getTicketApiUrl(key: String) async throws -> (apiUrl: URL, siteUrl: String) {
        // OAuth: Use Atlassian API with cloudId (with automatic token refresh)
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
                throw ToolError.executionFailed("Could not determine Jira site. Please reconnect in Settings.")
            }

            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3/issue/\(key)?expand=names"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid OAuth API URL")
            }
            return (url, siteUrl)
        }

        // Basic Auth: Use direct Jira URL
        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let jiraBaseUrl = baseUrl.replacingOccurrences(of: "/wiki", with: "")

        let urlString = "\(jiraBaseUrl)/rest/api/3/issue/\(key)?expand=names"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, jiraBaseUrl)
    }

    var isConfigured: Bool {
        // Check OAuth first (shares Atlassian token with Confluence), then Basic Auth
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence) {
            return true
        }
        return DataSourceConfig.shared.confluenceConfig != nil
    }

    /// Get auth header with automatic token refresh for OAuth
    private func getAuthHeader() async -> String {
        // Use OAuth if available (shared with Confluence) - with automatic token refresh
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence) {
            if let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
                return "Bearer \(token)"
            }
            // Token refresh failed - fall through to try basic auth
            NSLog("Jira: OAuth token refresh failed, trying basic auth...")
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

        // Check if query is a specific ticket key (e.g., PROJ-123, ABC-1)
        let ticketPattern = "^[A-Z]{2,10}-\\d+$"
        if let regex = try? NSRegularExpression(pattern: ticketPattern, options: .caseInsensitive),
           regex.firstMatch(in: query, options: [], range: NSRange(query.startIndex..., in: query)) != nil {
            // Fetch specific ticket directly
            return try await getTicket(key: query.uppercased())
        }

        // Determine base URL and API URL based on auth method
        let (apiUrl, siteUrl) = try await getApiUrl(query: query, project: input["project"] as? String)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ToolError.executionFailed("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                NSLog("📋 Jira API error - Status: \(httpResponse.statusCode), Body: \(rawBody.prefix(500))")
                let errorMessage = parseJiraError(statusCode: httpResponse.statusCode, data: data)
                return .success(content: errorMessage)  // Return as success so Claude can inform user
            }

            let results = try JSONDecoder().decode(JiraSearchResponse.self, from: data)

            if results.issues.isEmpty {
                return .success(content: "No Jira issues found for: \(query)")
            }

            // Format results
            let content = results.issues.map { issue in
                let status = issue.fields.status?.name ?? "Unknown"
                let priority = issue.fields.priority?.name ?? "None"
                let assignee = issue.fields.assignee?.displayName ?? "Unassigned"
                let description = issue.fields.description?.content?.first?.content?.first?.text ?? ""
                let truncatedDesc = description.prefix(200)

                return """
                ## \(issue.key): \(issue.fields.summary)
                **Status:** \(status) | **Priority:** \(priority) | **Assignee:** \(assignee)
                URL: \(siteUrl)/browse/\(issue.key)
                \(truncatedDesc)\(description.count > 200 ? "..." : "")
                """
            }.joined(separator: "\n\n---\n\n")

            return .success(content: content)

        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed(error.localizedDescription)
        }
    }

    /// Build smart JQL query - detects user/assignee searches vs text searches
    private func buildJqlQuery(from query: String, project: String?) -> String {
        let lowercased = query.lowercased()
        var jql: String

        // Detect "my tickets" patterns - use currentUser() or stored account ID
        let myPatterns = ["my tickets", "my issues", "my tasks", "my jira", "assigned to me", "my open", "my closed", "list my"]
        let sprintPatterns = ["sprint", "current sprint", "active sprint", "this sprint", "what's left", "whats left", "remaining", "left in sprint"]
        let assigneePatterns = ["assigned to", "assignee", "tickets for", "issues for", "tasks for", "open tickets of", "tickets of"]
        let reporterPatterns = ["reported by", "created by", "reporter"]
        let statusPatterns = ["open", "in progress", "done", "closed", "to do"]

        // Check for sprint-related queries
        var isSprintSearch = false
        for pattern in sprintPatterns {
            if lowercased.contains(pattern) {
                isSprintSearch = true
                break
            }
        }

        // Check for "my tickets" pattern
        var isMySearch = false
        for pattern in myPatterns {
            if lowercased.contains(pattern) {
                isMySearch = true
                break
            }
        }

        if isMySearch || isSprintSearch {
            // Use currentUser() JQL function (works with OAuth)
            // Or fall back to stored account ID if available
            if let accountId = DataSourceConfig.shared.getValue(for: .confluence, field: "userAccountId") {
                jql = "assignee = \"\(accountId)\""
                NSLog("📋 Using stored accountId: \(accountId)")
            } else {
                // currentUser() works with OAuth tokens
                jql = "assignee = currentUser()"
                NSLog("📋 Using currentUser() function")
            }

            // Add sprint filter if sprint-related query
            if isSprintSearch {
                jql += " AND sprint in openSprints()"
                NSLog("📋 Adding sprint filter: openSprints()")
            }

            // Check for status keywords
            var statusFound = false
            for status in statusPatterns {
                if lowercased.contains(status) {
                    if status == "open" {
                        jql += " AND status != Done AND status != Closed"
                    } else {
                        jql += " AND status = \"\(status.capitalized)\""
                    }
                    statusFound = true
                    break
                }
            }

            // For sprint queries asking "what's left", default to open issues
            if isSprintSearch && !statusFound && (lowercased.contains("left") || lowercased.contains("remaining")) {
                jql += " AND status != Done AND status != Closed"
            }

            // Add project filter if specified
            if let project = project {
                jql += " AND project = \"\(escapeJql(project))\""
            }

            jql += " ORDER BY updated DESC"
            NSLog("📋 Jira JQL: \(jql)")
            return jql
        }
        
        // Check if this looks like a user search
        var isUserSearch = false
        var userName: String = query
        var searchField = "assignee"
        
        for pattern in assigneePatterns {
            if lowercased.contains(pattern) {
                isUserSearch = true
                // Extract the name after the pattern
                if let range = lowercased.range(of: pattern) {
                    userName = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }
        
        for pattern in reporterPatterns {
            if lowercased.contains(pattern) {
                isUserSearch = true
                searchField = "reporter"
                if let range = lowercased.range(of: pattern) {
                    userName = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }
        
        // If query is just a name (single word or two words like "John Smith"), treat as assignee search
        let words = query.split(separator: " ")
        if words.count <= 3 && words.allSatisfy({ $0.first?.isUppercase == true || $0.first?.isLetter == true }) {
            // Looks like a name - search both assignee and reporter
            isUserSearch = true
            userName = query
        }
        
        if isUserSearch {
            // Search by assignee name (using ~ for partial match)
            jql = "\(searchField) ~ \"\(escapeJql(userName))\""
            
            // Check for status keywords
            for status in statusPatterns {
                if lowercased.contains(status) {
                    if status == "open" {
                        jql += " AND status != Done AND status != Closed"
                    } else {
                        jql += " AND status = \"\(status.capitalized)\""
                    }
                    break
                }
            }
        } else {
            // Default to text search
            jql = "text ~ \"\(escapeJql(query))\""
        }
        
        // Add project filter if specified
        if let project = project {
            jql += " AND project = \"\(escapeJql(project))\""
        }
        
        jql += " ORDER BY updated DESC"
        
        NSLog("📋 Jira JQL: \(jql)")
        return jql
    }

    /// Get API URL based on auth method (OAuth uses Atlassian API, Basic Auth uses direct URL)
    private func getApiUrl(query: String, project: String?) async throws -> (apiUrl: URL, siteUrl: String) {
        // Build JQL query - detect if searching for a user/assignee
        let jql = buildJqlQuery(from: query, project: project)

        guard let encodedJql = jql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ToolError.executionFailed("Invalid JQL query")
        }

        // OAuth: Use Atlassian API with cloudId (shared with Confluence, with automatic token refresh)
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            var siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")

            if cloudId == nil || siteUrl == nil {
                // Try to fetch accessible resources
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
                siteUrl = DataSourceConfig.shared.getValue(for: .confluence, field: "siteUrl")
            }

            guard let cloudId = cloudId, let siteUrl = siteUrl else {
                throw ToolError.executionFailed("Could not determine Jira site. Please reconnect in Settings.")
            }

            // Jira API endpoint via Atlassian API (using new /search/jql endpoint)
            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3/search/jql?jql=\(encodedJql)&maxResults=5&fields=summary,status,priority,assignee,description"
            NSLog("📋 Jira API URL: \(urlString.prefix(150))...")
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid OAuth API URL")
            }
            return (url, siteUrl)
        }

        // Basic Auth: Use direct Jira URL
        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Remove /wiki suffix if present (Confluence URL vs Jira URL)
        let jiraBaseUrl = baseUrl.replacingOccurrences(of: "/wiki", with: "")

        let urlString = "\(jiraBaseUrl)/rest/api/3/search/jql?jql=\(encodedJql)&maxResults=5&fields=summary,status,priority,assignee,description"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, jiraBaseUrl)
    }

    /// Fetch accessible resources from Atlassian API (reuses Confluence's fetch logic)
    private func fetchAccessibleResources(token: String) async throws {
        guard let url = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed("Failed to fetch Atlassian sites")
        }

        guard let resources = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstSite = resources.first,
              let cloudId = firstSite["id"] as? String,
              let siteUrl = firstSite["url"] as? String else {
            throw ToolError.executionFailed("No Atlassian sites found")
        }

        let siteName = firstSite["name"] as? String ?? "Unknown"
        NSLog("Jira: Found site \(siteName) (cloudId: \(cloudId))")

        DataSourceConfig.shared.setValue(for: .confluence, field: "cloudId", value: cloudId)
        DataSourceConfig.shared.setValue(for: .confluence, field: "siteUrl", value: siteUrl)
        DataSourceConfig.shared.setValue(for: .confluence, field: "siteName", value: siteName)
    }

    // MARK: - List Projects

    /// List all Jira projects the user has access to
    func listProjects(input: [String: Any]) async throws -> ToolResult {
        let limitStr = (input["limit"] as? String) ?? "20"
        let limit = Int(limitStr) ?? 20

        let (apiUrl, siteUrl) = try await getProjectsApiUrl(limit: limit)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = parseJiraError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            return .success(content: errorMessage)
        }

        let results = try JSONDecoder().decode(JiraProjectsResponse.self, from: data)

        if results.values.isEmpty {
            return .success(content: "No Jira projects found.")
        }

        let content = results.values.prefix(limit).map { project in
            let projectType = project.projectTypeKey ?? "Unknown"
            return """
            ## \(project.name) (\(project.key))
            **Type:** \(projectType.capitalized)
            URL: \(siteUrl)/browse/\(project.key)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(results.values.count) projects:\n\n\(content)")
    }

    private func getProjectsApiUrl(limit: Int) async throws -> (apiUrl: URL, siteUrl: String) {
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
                throw ToolError.executionFailed("Could not determine Jira site.")
            }

            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3/project/search?maxResults=\(limit)"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        let urlString = "\(baseUrl)/rest/api/3/project/search?maxResults=\(limit)"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    // MARK: - List Boards

    /// List Jira boards (Scrum/Kanban)
    func listBoards(input: [String: Any]) async throws -> ToolResult {
        let project = input["project"] as? String
        let boardType = input["type"] as? String

        let (apiUrl, siteUrl) = try await getBoardsApiUrl(project: project, type: boardType)

        var request = URLRequest(url: apiUrl)
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = parseJiraError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            return .success(content: errorMessage)
        }

        let results = try JSONDecoder().decode(JiraBoardsResponse.self, from: data)

        if results.values.isEmpty {
            return .success(content: "No Jira boards found.")
        }

        let content = results.values.map { board in
            let projectInfo = board.location?.projectKey ?? board.location?.displayName ?? "Unknown"
            return """
            ## \(board.name)
            **ID:** \(board.id) | **Type:** \(board.type.capitalized) | **Project:** \(projectInfo)
            URL: \(siteUrl)/jira/software/c/projects/\(board.location?.projectKey ?? "")/boards/\(board.id)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(results.values.count) boards:\n\n\(content)")
    }

    private func getBoardsApiUrl(project: String?, type: String?) async throws -> (apiUrl: URL, siteUrl: String) {
        var queryParams = "maxResults=20"
        if let project = project {
            queryParams += "&projectKeyOrId=\(project)"
        }
        if let type = type {
            queryParams += "&type=\(type)"
        }

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
                throw ToolError.executionFailed("Could not determine Jira site.")
            }

            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/agile/1.0/board?\(queryParams)"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        let urlString = "\(baseUrl)/rest/agile/1.0/board?\(queryParams)"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    // MARK: - Get Sprint Info

    /// Get current sprint information and issues
    func getSprintInfo(input: [String: Any]) async throws -> ToolResult {
        let boardIdStr = input["board_id"] as? String
        let sprintState = (input["sprint_state"] as? String) ?? "active"

        // First, get a board if not specified
        var boardId: Int
        var siteUrl: String

        if let idStr = boardIdStr, let id = Int(idStr) {
            boardId = id
            (_, siteUrl) = try await getBoardsApiUrl(project: nil, type: nil)
        } else {
            // Get the first available board
            let (boardsUrl, site) = try await getBoardsApiUrl(project: nil, type: nil)
            siteUrl = site

            var request = URLRequest(url: boardsUrl)
            request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return .success(content: "⚠️ Could not fetch boards to find sprints.")
            }

            let boards = try JSONDecoder().decode(JiraBoardsResponse.self, from: data)
            guard let firstBoard = boards.values.first else {
                return .success(content: "No boards found. Create a Scrum board to use sprints.")
            }
            boardId = firstBoard.id
        }

        // Get sprints for the board
        let (sprintsUrl, _) = try await getSprintsApiUrl(boardId: boardId, state: sprintState)

        var sprintRequest = URLRequest(url: sprintsUrl)
        sprintRequest.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        sprintRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (sprintData, sprintResponse) = try await URLSession.shared.data(for: sprintRequest)

        guard let httpResponse = sprintResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return .success(content: "⚠️ Could not fetch sprints. This board may not support sprints (Kanban boards don't have sprints).")
        }

        let sprints = try JSONDecoder().decode(JiraSprintsResponse.self, from: sprintData)

        if sprints.values.isEmpty {
            return .success(content: "No \(sprintState) sprints found for board \(boardId).")
        }

        var content = ""
        for sprint in sprints.values.prefix(3) {
            let startDate = sprint.startDate?.prefix(10) ?? "Not started"
            let endDate = sprint.endDate?.prefix(10) ?? "Not set"
            let goal = sprint.goal ?? "No goal set"

            content += """
            ## \(sprint.name)
            **ID:** \(sprint.id) | **State:** \(sprint.state.capitalized)
            **Dates:** \(startDate) → \(endDate)
            **Goal:** \(goal)

            """

            // Fetch sprint issues
            let (issuesUrl, _) = try await getSprintIssuesApiUrl(sprintId: sprint.id)
            var issuesRequest = URLRequest(url: issuesUrl)
            issuesRequest.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
            issuesRequest.setValue("application/json", forHTTPHeaderField: "Accept")

            if let (issuesData, issuesResponse) = try? await URLSession.shared.data(for: issuesRequest),
               let issuesHttp = issuesResponse as? HTTPURLResponse,
               issuesHttp.statusCode == 200,
               let issues = try? JSONDecoder().decode(JiraSearchResponse.self, from: issuesData) {

                if !issues.issues.isEmpty {
                    content += "### Issues (\(issues.issues.count)):\n"
                    for issue in issues.issues.prefix(10) {
                        let status = issue.fields.status?.name ?? "Unknown"
                        let assignee = issue.fields.assignee?.displayName ?? "Unassigned"
                        content += "- **\(issue.key)**: \(issue.fields.summary) [\(status)] @\(assignee)\n"
                    }
                }
            }
            content += "\n---\n\n"
        }

        return .success(content: content)
    }

    private func getSprintsApiUrl(boardId: Int, state: String) async throws -> (apiUrl: URL, siteUrl: String) {
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
                throw ToolError.executionFailed("Could not determine Jira site.")
            }

            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/agile/1.0/board/\(boardId)/sprint?state=\(state)"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        let urlString = "\(baseUrl)/rest/agile/1.0/board/\(boardId)/sprint?state=\(state)"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    private func getSprintIssuesApiUrl(sprintId: Int) async throws -> (apiUrl: URL, siteUrl: String) {
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
                throw ToolError.executionFailed("Could not determine Jira site.")
            }

            let urlString = "https://api.atlassian.com/ex/jira/\(cloudId)/rest/agile/1.0/sprint/\(sprintId)/issue?maxResults=20&fields=summary,status,assignee,priority"
            guard let url = URL(string: urlString) else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return (url, siteUrl)
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }

        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        let urlString = "\(baseUrl)/rest/agile/1.0/sprint/\(sprintId)/issue?maxResults=20&fields=summary,status,assignee,priority"
        guard let url = URL(string: urlString) else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return (url, baseUrl)
    }

    /// Escape user input for safe embedding in JQL queries
    private func escapeJql(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Create Issue

    func createIssue(input: [String: Any]) async throws -> ToolResult {
        guard let project = input["project"] as? String else {
            throw ToolError.missingParameter("project")
        }
        guard let summary = input["summary"] as? String else {
            throw ToolError.missingParameter("summary")
        }
        let description = input["description"] as? String
        let issueType = (input["issue_type"] as? String) ?? "Task"
        let priority = input["priority"] as? String

        var fields: [String: Any] = [
            "project": ["key": project],
            "summary": summary,
            "issuetype": ["name": issueType]
        ]

        if let description = description {
            fields["description"] = [
                "version": 1,
                "type": "doc",
                "content": [
                    ["type": "paragraph", "content": [
                        ["type": "text", "text": description]
                    ]]
                ]
            ] as [String: Any]
        }

        if let priority = priority {
            fields["priority"] = ["name": priority]
        }

        let body: [String: Any] = ["fields": fields]
        let url = try await getCreateIssueApiUrl()

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

        guard httpResponse.statusCode == 201 else {
            let errorMessage = parseJiraError(statusCode: httpResponse.statusCode, data: data)
            return .success(content: errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else {
            return .success(content: "Issue created but could not parse response.")
        }

        let (_, siteUrl) = try await getBoardsApiUrl(project: nil, type: nil)
        return .success(content: "Created **\(key)**: \(summary)\nURL: \(siteUrl)/browse/\(key)")
    }

    private func getCreateIssueApiUrl() async throws -> URL {
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            if cloudId == nil {
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            }
            guard let cloudId = cloudId else {
                throw ToolError.executionFailed("Could not determine Jira site.")
            }
            guard let url = URL(string: "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3/issue") else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return url
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }
        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        guard let url = URL(string: "\(baseUrl)/rest/api/3/issue") else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return url
    }

    // MARK: - Add Comment

    func addComment(input: [String: Any]) async throws -> ToolResult {
        guard let issueKey = input["issue_key"] as? String else {
            throw ToolError.missingParameter("issue_key")
        }
        guard let comment = input["comment"] as? String else {
            throw ToolError.missingParameter("comment")
        }

        let body: [String: Any] = [
            "body": [
                "version": 1,
                "type": "doc",
                "content": [
                    ["type": "paragraph", "content": [
                        ["type": "text", "text": comment]
                    ]]
                ]
            ] as [String: Any]
        ]

        let url = try await getCommentApiUrl(issueKey: issueKey)

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

        guard httpResponse.statusCode == 201 else {
            let errorMessage = parseJiraError(statusCode: httpResponse.statusCode, data: data)
            return .success(content: errorMessage)
        }

        return .success(content: "Comment added to \(issueKey)")
    }

    private func getCommentApiUrl(issueKey: String) async throws -> URL {
        if DataSourceConfig.shared.isOAuthAuthenticated(.confluence),
           let token = await OAuthManager.shared.getValidAccessToken(for: .atlassian) {
            var cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            if cloudId == nil {
                try await fetchAccessibleResources(token: token)
                cloudId = DataSourceConfig.shared.getValue(for: .confluence, field: "cloudId")
            }
            guard let cloudId = cloudId else {
                throw ToolError.executionFailed("Could not determine Jira site.")
            }
            guard let url = URL(string: "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3/issue/\(issueKey)/comment") else {
                throw ToolError.executionFailed("Invalid URL")
            }
            return url
        }

        guard let config = DataSourceConfig.shared.confluenceConfig else {
            throw ToolError.notConfigured("Jira")
        }
        let baseUrl = config.baseUrl.replacingOccurrences(of: "/wiki", with: "")
        guard let url = URL(string: "\(baseUrl)/rest/api/3/issue/\(issueKey)/comment") else {
            throw ToolError.executionFailed("Invalid URL")
        }
        return url
    }

    /// Parse Jira API errors into user-friendly messages
    private func parseJiraError(statusCode: Int, data: Data) -> String {
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        
        switch statusCode {
        case 400:
            if rawBody.contains("does not exist") || rawBody.contains("not found") {
                return "⚠️ Jira Search: No matching issues found. The project or search term may not exist."
            }
            return "⚠️ Jira Search: Invalid search query. Try a simpler search term."
        case 401:
            return "⚠️ Jira Search: Authentication failed. Please reconnect Atlassian in Settings (⌘,)."
        case 403:
            return "⚠️ Jira Search: Access denied. You may not have permission to search this project."
        case 404:
            return "⚠️ Jira Search: No results found. The project or issue doesn't exist in your Jira instance."
        case 410:
            return "⚠️ Jira Search: Connection expired. Please reconnect Atlassian in Settings (⌘,) to refresh your credentials."
        case 429:
            return "⚠️ Jira Search: Rate limited. Please wait a moment and try again."
        case 500...599:
            return "⚠️ Jira Search: Atlassian server error. Please try again later."
        default:
            NSLog("Jira API error \(statusCode): \(rawBody)")
            return "⚠️ Jira Search: Unable to complete search (error \(statusCode)). Please check your connection."
        }
    }
}

// MARK: - Response Models

private struct JiraSearchResponse: Codable {
    let issues: [JiraIssue]
}

private struct JiraIssue: Codable {
    let id: String
    let key: String
    let fields: JiraFields
}

private struct JiraFields: Codable {
    let summary: String
    let status: JiraStatus?
    let priority: JiraPriority?
    let assignee: JiraUser?
    let description: JiraDescription?
}

private struct JiraStatus: Codable {
    let name: String
}

private struct JiraPriority: Codable {
    let name: String
}

private struct JiraUser: Codable {
    let displayName: String
}

private struct JiraDescription: Codable {
    let content: [JiraContent]?
}

private struct JiraContent: Codable {
    let content: [JiraTextContent]?
}

private struct JiraTextContent: Codable {
    let text: String?
}

// MARK: - Detailed Issue Models (for get_jira_ticket)

private struct JiraIssueDetail: Codable {
    let id: String
    let key: String
    let fields: JiraFieldsDetail
}

private struct JiraFieldsDetail: Codable {
    let summary: String
    let status: JiraStatus?
    let priority: JiraPriority?
    let assignee: JiraUser?
    let reporter: JiraUser?
    let description: JiraDescription?
    let issuetype: JiraIssueType?
    let created: String?
    let updated: String?
    let labels: [String]?
    let parent: JiraParent?
    let sprint: JiraSprint?
}

private struct JiraIssueType: Codable {
    let name: String
}

private struct JiraParent: Codable {
    let key: String
    let fields: JiraParentFields
}

private struct JiraParentFields: Codable {
    let summary: String
}

private struct JiraSprint: Codable {
    let name: String
}

// MARK: - Project/Board/Sprint Models

private struct JiraProjectsResponse: Codable {
    let values: [JiraProject]
}

private struct JiraProject: Codable {
    let id: String
    let key: String
    let name: String
    let projectTypeKey: String?
    let avatarUrls: [String: String]?
}

private struct JiraBoardsResponse: Codable {
    let values: [JiraBoard]
}

private struct JiraBoard: Codable {
    let id: Int
    let name: String
    let type: String
    let location: JiraBoardLocation?
}

private struct JiraBoardLocation: Codable {
    let projectKey: String?
    let displayName: String?
}

private struct JiraSprintsResponse: Codable {
    let values: [JiraSprintDetail]
}

private struct JiraSprintDetail: Codable {
    let id: Int
    let name: String
    let state: String
    let startDate: String?
    let endDate: String?
    let goal: String?
}
