import Foundation
import Cocoa

/// Orchestrates tool execution by routing requests to appropriate handlers
class ToolExecutor {
    static let shared = ToolExecutor()

    /// Registered tool handlers keyed by tool name (written once during init, then read-only)
    private let toolQueue = DispatchQueue(label: "com.assistant.tool-registry", attributes: .concurrent)
    private var _tools: [String: Tool] = [:]
    private var tools: [String: Tool] {
        toolQueue.sync { _tools }
    }

    /// SF Symbol names for different tool types
    private let toolIcons: [String: String] = [
        "search_documentation": "book.fill",
        "search_jira": "ticket.fill",
        "search_codebase": "chevron.left.forwardslash.chevron.right",
        "list_repositories": "folder.fill",
        "get_pr_details": "arrow.triangle.branch",
        "get_issue_details": "ladybug.fill",
        "list_branches": "arrow.triangle.branch",
        "list_jira_projects": "list.clipboard.fill",
        "get_confluence_page": "doc.text.fill",
        "list_confluence_spaces": "square.stack.3d.up.fill",
        "create_jira_issue": "plus.rectangle.fill",
        "add_jira_comment": "text.bubble.fill",
        "create_confluence_page": "doc.badge.plus",
        "query_database": "cylinder.split.1x2.fill",
        "web_search": "globe"
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
        toolQueue.sync(flags: .barrier) {
            for toolName in tool.supportedToolNames {
                _tools[toolName] = tool
            }
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
    /// Get SF Symbol name for a tool
    func iconName(for toolName: String) -> String {
        return toolIcons[toolName] ?? "wrench.fill"
    }

    /// Get an attributed string with SF Symbol icon + tool display name for UI labels
    func attributedDisplay(for toolName: String, fontSize: CGFloat = 12, color: NSColor = .white) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let symbolName = iconName(for: toolName)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
            let tinted = image.copy() as! NSImage
            tinted.lockFocus()
            color.withAlphaComponent(0.8).set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let attachment = NSTextAttachment()
            attachment.image = tinted
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        let name = tools[toolName]?.displayName ?? toolName
        result.append(NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ]))
        return result
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

/// Pre-routing: local keyword matching to skip Claude's tool-decision round-trip
extension ToolExecutor {

    /// Matched tool with its input parameters, ready for immediate execution
    struct PreRoutedTool {
        let name: String
        let input: [String: Any]
    }

    /// Match question keywords to tools locally. Returns nil if no confident match.
    /// Only routes when keywords are unambiguous — falls back to Claude otherwise.
    func preRouteTools(for question: String) -> [PreRoutedTool]? {
        let q = question.lowercased()
        var matched: [PreRoutedTool] = []

        // Ticket key pattern: PROJ-123, ABC-45 etc. (always Jira)
        let ticketPattern = try? NSRegularExpression(pattern: "\\b[A-Z]{2,10}-\\d+\\b", options: [])
        let ticketMatches = ticketPattern?.matches(in: question, range: NSRange(question.startIndex..., in: question)) ?? []

        if !ticketMatches.isEmpty {
            let ticketKey = (question as NSString).substring(with: ticketMatches[0].range)
            matched.append(PreRoutedTool(name: "search_jira", input: ["query": ticketKey]))
            matched.append(PreRoutedTool(name: "search_codebase", input: ["query": ticketKey]))
            return matched
        }

        // Sprint keywords → search_jira directly (faster & more reliable than get_sprint_info which needs board IDs)
        let sprintKeywords = ["sprint", "sprint status", "sprint health", "sprint progress"]
        if sprintKeywords.contains(where: { q.contains($0) }) {
            matched.append(PreRoutedTool(name: "search_jira", input: ["query": "my sprint tickets"]))
            return matched
        }

        // Confluence / documentation keywords — extract topic from question
        let docKeywords = ["confluence", "documentation", "wiki", "docs"]
        if docKeywords.contains(where: { q.contains($0) }) {
            let searchQuery = extractSearchTerms(from: question, removing: ["what", "does", "our", "say", "about", "tell", "me", "find", "search", "look", "up", "the", "in", "for", "how", "to", "do", "we", "is", "there", "any", "can", "you", "please", "show", "confluence", "documentation", "wiki", "docs"])
            matched.append(PreRoutedTool(name: "search_documentation", input: ["query": searchQuery]))
            return matched
        }

        // GitHub / PR / code keywords — extract topic
        let codeKeywords = ["github", "pull request", " pr ", " prs ", "commit", "branch", "code review", "merge request"]
        if codeKeywords.contains(where: { q.contains($0) }) {
            let searchQuery = extractSearchTerms(from: question, removing: ["what", "are", "the", "any", "recent", "latest", "show", "me", "find", "search", "related", "to", "for", "in", "our", "from", "github", "can", "you", "please", "do", "we", "have"])
            matched.append(PreRoutedTool(name: "search_codebase", input: ["query": searchQuery]))
            return matched
        }

        // Jira / ticket keywords — build clean query for buildJqlQuery
        let jiraKeywords = ["jira", "ticket", "tickets", "issue", "issues", "bug", "bugs", "backlog", "blocked"]
        if jiraKeywords.contains(where: { q.contains($0) }) {
            // Extract intent keywords that buildJqlQuery understands
            let jiraQuery = extractJiraIntent(from: q)
            matched.append(PreRoutedTool(name: "search_jira", input: ["query": jiraQuery]))
            return matched
        }

        // No confident match — let Claude decide
        return nil
    }

    /// Extract meaningful search terms by removing filler/stop words
    private func extractSearchTerms(from question: String, removing stopWords: [String]) -> String {
        let words = question.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ",", with: "")
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) && $0.count > 1 }

        let result = words.joined(separator: " ")
        return result.isEmpty ? question : result
    }

    /// Extract Jira-friendly intent from natural language
    private func extractJiraIntent(from q: String) -> String {
        // Detect specific patterns that buildJqlQuery handles well
        if q.contains("my ticket") || q.contains("my issue") || q.contains("assigned to me") {
            if q.contains("open") { return "my open tickets" }
            if q.contains("closed") || q.contains("done") { return "my closed tickets" }
            return "my tickets"
        }
        if q.contains("open") && (q.contains("ticket") || q.contains("issue")) { return "my open tickets" }
        if q.contains("blocked") { return "my open tickets" } // blocked tickets are open
        if q.contains("backlog") { return "backlog" }
        if q.contains("in progress") { return "my tickets in progress" }
        if q.contains("bug") { return "open bugs" }
        // Default: pass through for text search but cleaned up
        return extractSearchTerms(from: q, removing: ["what", "are", "the", "still", "any", "is", "anything", "currently", "can", "you", "show", "me", "find", "please", "and", "or", "do", "we", "have", "how", "many"])
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
    /// Uses exponential backoff and enforces a total time budget
    private func executeWithRetry(toolName: String, input: [String: Any]) async -> ToolResult {
        let startTime = Date()
        let maxTotalTime: TimeInterval = 45 // Total time budget across all retries

        var lastResult: ToolResult = .failure(error: "Unknown error")
        for attempt in 0...maxRetries {
            // Check total time budget before each attempt
            if attempt > 0 && Date().timeIntervalSince(startTime) >= maxTotalTime {
                NSLog("  \u{26A0}\u{FE0F} \(toolName) exceeded total retry budget of \(Int(maxTotalTime))s")
                return lastResult
            }

            let result = await executeWithTimeout(toolName: toolName, input: input)
            lastResult = result

            if !result.success, let error = result.error, isRetryableError(error), attempt < maxRetries {
                let delay = pow(2.0, Double(attempt)) // Exponential backoff: 1s, 2s, 4s
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
