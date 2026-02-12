import Foundation

/// Orchestrates tool execution by routing requests to appropriate handlers
class ToolExecutor {
    static let shared = ToolExecutor()

    /// Registered tool handlers keyed by tool name
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
        "create_jira_issue": "📝",
        "add_jira_comment": "💬",
        "create_confluence_page": "📄",
        "query_database": "🗄️",
        "web_search": "🌐"
    ]

    /// Per-tool timeout in seconds (default 30s)
    private let toolTimeout: TimeInterval = 30

    /// Max retries for transient failures
    private let maxRetries = 2

    private init() {
        registerTool(ConfluenceClient.shared)
        registerTool(JiraClient.shared)
        registerTool(GitHubClient.shared)
        registerTool(DatabaseClient.shared)
        registerTool(WebSearchClient.shared)
    }

    /// Register a tool handler for all its supported tool names
    func registerTool(_ tool: Tool) {
        for toolName in tool.supportedToolNames {
            tools[toolName] = tool
        }
    }

    /// Execute a tool by name with given input — uses registry lookup
    func execute(toolName: String, input: [String: Any]) async -> ToolResult {
        guard let tool = tools[toolName] else {
            return .failure(error: "Unknown tool: \(toolName)")
        }

        guard tool.isConfigured else {
            return .failure(error: "\(tool.displayName) is not configured. Please configure it in Settings (⌘,).")
        }

        do {
            return try await tool.execute(toolName: toolName, input: input)
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
        return AvailableTools.all.filter { definition in
            tools[definition.name]?.isConfigured == true
        }
    }

    /// Get all tool definitions (even unconfigured)
    var allToolDefinitions: [ToolDefinition] {
        return AvailableTools.all
    }

    /// Check if any tools are configured
    var hasConfiguredTools: Bool {
        let uniqueTools = Set(tools.values.map { ObjectIdentifier($0 as AnyObject) })
        return uniqueTools.contains { id in
            tools.values.first { ObjectIdentifier($0 as AnyObject) == id }?.isConfigured == true
        }
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

    /// Test connection for a specific tool
    func testConnection(toolName: String) async -> ToolResult {
        guard let tool = tools[toolName] else {
            return .failure(error: "Unknown tool: \(toolName)")
        }
        return await tool.testConnection()
    }
}

/// Convenience extension for processing multiple tool calls
extension ToolExecutor {

    /// Process multiple tool use requests in parallel with timeout and return results in original order
    func processToolUses(_ requests: [ToolUseRequest]) async -> [ToolResultMessage] {
        let startTime = Date()
        let toolNames = requests.map { $0.name }.joined(separator: ", ")
        NSLog("⚡ Executing \(requests.count) tools in parallel: \(toolNames)")

        let indexedResults = await withTaskGroup(of: (Int, ToolResultMessage).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    let toolStart = Date()
                    let result = await self.executeWithRetry(toolName: request.name, input: request.input)
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

        let results = indexedResults.sorted { $0.0 < $1.0 }.map { $0.1 }

        let totalMs = Date().timeIntervalSince(startTime) * 1000
        NSLog("⚡ All \(requests.count) tools completed in %.0fms (parallel)", totalMs)
        return results
    }

    /// Execute with retry for transient failures (429, 5xx)
    private func executeWithRetry(toolName: String, input: [String: Any]) async -> ToolResult {
        var lastResult: ToolResult = .failure(error: "Unknown error")
        for attempt in 0...maxRetries {
            let result = await executeWithTimeout(toolName: toolName, input: input)
            lastResult = result

            if !result.success, let error = result.error, isRetryableError(error), attempt < maxRetries {
                let delay = Double(attempt + 1) * 1.0
                NSLog("  \u{26A0}\u{FE0F} \(toolName) retryable error, retry \(attempt + 1)/\(maxRetries) in \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            return result
        }
        return lastResult
    }

    private func isRetryableError(_ error: String) -> Bool {
        let patterns = ["429", "Rate limit", "rate limit", "500", "502", "503", "504", "timed out", "timeout", "server error"]
        return patterns.contains { error.contains($0) }
    }

    /// Execute with timeout protection
    private func executeWithTimeout(toolName: String, input: [String: Any]) async -> ToolResult {
        do {
            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask {
                    return await self.execute(toolName: toolName, input: input)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.toolTimeout * 1_000_000_000))
                    throw ToolError.timeout(toolName)
                }

                // Return first result, cancel the other
                guard let result = try await group.next() else {
                    return .failure(error: "Tool execution failed")
                }
                group.cancelAll()
                return result
            }
        } catch let error as ToolError {
            return .failure(error: error.localizedDescription)
        } catch {
            return .failure(error: "Tool \(toolName) timed out after \(Int(toolTimeout))s")
        }
    }
}
