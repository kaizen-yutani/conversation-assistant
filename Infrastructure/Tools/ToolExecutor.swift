import Foundation

/// Orchestrates tool execution by routing requests to appropriate handlers
class ToolExecutor {
    /// Singleton instance
    static let shared = ToolExecutor()
    
    /// Registered tool handlers
    private var tools: [String: Tool] = [:]
    
    /// Icons for different tool types
    private let toolIcons: [String: String] = [
        "search_documentation": "📚",
        "search_jira": "🎫",
        "search_codebase": "💻",
        "list_repositories": "📂",
        "get_pr_details": "🔀",
        "get_issue_details": "🐛",
        "list_branches": "🌿",
        "list_jira_projects": "📋",
        "get_sprint_info": "🏃",
        "list_jira_boards": "📊",
        "get_confluence_page": "📄",
        "list_confluence_spaces": "🗂️",
        "query_database": "🗄️",
        "web_search": "🌐"
    ]

    private init() {
        // Register available tools
        registerTool(ConfluenceClient.shared)
        registerTool(JiraClient.shared)
        registerTool(GitHubClient.shared)
        registerTool(DatabaseClient.shared)
        registerTool(WebSearchClient.shared)
    }
    
    /// Register a tool handler
    func registerTool(_ tool: Tool) {
        tools[tool.name] = tool
    }
    
    /// Execute a tool by name with given input
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - input: Input parameters for the tool
    /// - Returns: ToolResult containing output or error
    func execute(toolName: String, input: [String: Any]) async -> ToolResult {
        // GitHub tools - use GitHubClient directly
        let githubTools = ["list_repositories", "get_pr_details", "get_issue_details", "list_branches"]
        if githubTools.contains(toolName) {
            guard GitHubClient.shared.isConfigured else {
                return .failure(error: "GitHub is not configured. Please configure it in Settings.")
            }
            do {
                switch toolName {
                case "list_repositories":
                    return try await GitHubClient.shared.listRepositories(input: input)
                case "get_pr_details":
                    return try await GitHubClient.shared.getPRDetails(input: input)
                case "get_issue_details":
                    return try await GitHubClient.shared.getIssueDetails(input: input)
                case "list_branches":
                    return try await GitHubClient.shared.listBranches(input: input)
                default:
                    return .failure(error: "Unknown GitHub tool: \(toolName)")
                }
            } catch let error as ToolError {
                return .failure(error: error.localizedDescription)
            } catch {
                return .failure(error: error.localizedDescription)
            }
        }

        // Jira tools - use JiraClient directly
        let jiraTools = ["list_jira_projects", "get_sprint_info", "list_jira_boards"]
        if jiraTools.contains(toolName) {
            guard JiraClient.shared.isConfigured else {
                return .failure(error: "Jira is not configured. Please configure Atlassian in Settings.")
            }
            do {
                switch toolName {
                case "list_jira_projects":
                    return try await JiraClient.shared.listProjects(input: input)
                case "get_sprint_info":
                    return try await JiraClient.shared.getSprintInfo(input: input)
                case "list_jira_boards":
                    return try await JiraClient.shared.listBoards(input: input)
                default:
                    return .failure(error: "Unknown Jira tool: \(toolName)")
                }
            } catch let error as ToolError {
                return .failure(error: error.localizedDescription)
            } catch {
                return .failure(error: error.localizedDescription)
            }
        }

        // Confluence tools - use ConfluenceClient directly
        let confluenceTools = ["get_confluence_page", "list_confluence_spaces"]
        if confluenceTools.contains(toolName) {
            guard ConfluenceClient.shared.isConfigured else {
                return .failure(error: "Confluence is not configured. Please configure Atlassian in Settings.")
            }
            do {
                switch toolName {
                case "get_confluence_page":
                    return try await ConfluenceClient.shared.getPage(input: input)
                case "list_confluence_spaces":
                    return try await ConfluenceClient.shared.listSpaces(input: input)
                default:
                    return .failure(error: "Unknown Confluence tool: \(toolName)")
                }
            } catch let error as ToolError {
                return .failure(error: error.localizedDescription)
            } catch {
                return .failure(error: error.localizedDescription)
            }
        }

        guard let tool = tools[toolName] else {
            return .failure(error: "Unknown tool: \(toolName)")
        }

        guard tool.isConfigured else {
            return .failure(error: "\(tool.displayName) is not configured. Please configure it in Settings.")
        }

        do {
            return try await tool.execute(input: input)
        } catch let error as ToolError {
            return .failure(error: error.localizedDescription)
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }
    
    /// Get icon for a tool
    func icon(for toolName: String) -> String {
        return toolIcons[toolName] ?? "🔧"
    }
    
    /// Get human-readable name for a tool
    func displayName(for toolName: String) -> String {
        return tools[toolName]?.displayName ?? toolName
    }
    
    /// Get tool definitions for only configured tools
    var configuredToolDefinitions: [ToolDefinition] {
        let githubTools = ["list_repositories", "get_pr_details", "get_issue_details", "list_branches"]
        let jiraTools = ["list_jira_projects", "get_sprint_info", "list_jira_boards"]
        let confluenceTools = ["get_confluence_page", "list_confluence_spaces"]

        return AvailableTools.all.filter { definition in
            // GitHub tools
            if githubTools.contains(definition.name) {
                return GitHubClient.shared.isConfigured
            }
            // Jira tools
            if jiraTools.contains(definition.name) {
                return JiraClient.shared.isConfigured
            }
            // Confluence tools
            if confluenceTools.contains(definition.name) {
                return ConfluenceClient.shared.isConfigured
            }
            return tools[definition.name]?.isConfigured == true
        }
    }
    
    /// Get all tool definitions (even unconfigured)
    var allToolDefinitions: [ToolDefinition] {
        return AvailableTools.all
    }
    
    /// Check if any tools are configured
    var hasConfiguredTools: Bool {
        return tools.values.contains { $0.isConfigured }
    }
    
    /// Get status of all tools
    var toolStatus: [(name: String, displayName: String, isConfigured: Bool)] {
        return AvailableTools.all.map { definition in
            let tool = tools[definition.name]
            return (
                name: definition.name,
                displayName: tool?.displayName ?? definition.name,
                isConfigured: tool?.isConfigured ?? false
            )
        }
    }
}

/// Convenience extension for processing multiple tool calls
extension ToolExecutor {

    /// Process multiple tool use requests in parallel and return results in original order
    /// - Parameter requests: Array of tool use requests from Claude
    /// - Returns: Array of tool result messages ready for API (preserves original order)
    func processToolUses(_ requests: [ToolUseRequest]) async -> [ToolResultMessage] {
        let startTime = Date()
        let toolNames = requests.map { $0.name }.joined(separator: ", ")
        NSLog("⚡ Executing \(requests.count) tools in parallel: \(toolNames)")

        // Execute all tools concurrently, track index to preserve order
        let indexedResults = await withTaskGroup(of: (Int, ToolResultMessage).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    let toolStart = Date()
                    let result = await self.execute(toolName: request.name, input: request.input)
                    let toolMs = Date().timeIntervalSince(toolStart) * 1000
                    NSLog("  ✓ \(request.name) completed in %.0fms", toolMs)
                    return (index, ToolResultMessage(toolUseId: request.id, result: result))
                }
            }

            var results: [(Int, ToolResultMessage)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Sort by original index to preserve request order
        let results = indexedResults.sorted { $0.0 < $1.0 }.map { $0.1 }

        let totalMs = Date().timeIntervalSince(startTime) * 1000
        NSLog("⚡ All \(requests.count) tools completed in %.0fms (parallel)", totalMs)
        return results
    }
}
