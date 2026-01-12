import Foundation

/// Tool definition for Claude API tool use
struct ToolDefinition: Codable {
    let name: String
    let description: String
    let input_schema: JSONSchema
    
    func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "input_schema": input_schema.toDictionary()
        ]
    }
}

/// JSON Schema representation for tool parameters
struct JSONSchema: Codable {
    let type: String
    let properties: [String: PropertySchema]?
    let required: [String]?
    
    static func object(_ properties: [String: PropertySchema], required: [String] = []) -> JSONSchema {
        JSONSchema(type: "object", properties: properties, required: required.isEmpty ? nil : required)
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let props = properties {
            dict["properties"] = props.mapValues { $0.toDictionary() }
        }
        if let req = required {
            dict["required"] = req
        }
        return dict
    }
}

/// Property schema for individual tool parameters
struct PropertySchema: Codable {
    let type: String
    let description: String
    let `enum`: [String]?
    
    static func string(_ description: String) -> PropertySchema {
        PropertySchema(type: "string", description: description, enum: nil)
    }
    
    static func string(_ description: String, enum values: [String]) -> PropertySchema {
        PropertySchema(type: "string", description: description, enum: values)
    }
    
    static func boolean(_ description: String) -> PropertySchema {
        PropertySchema(type: "boolean", description: description, enum: nil)
    }
    
    static func integer(_ description: String) -> PropertySchema {
        PropertySchema(type: "integer", description: description, enum: nil)
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "description": description
        ]
        if let enumValues = self.enum {
            dict["enum"] = enumValues
        }
        return dict
    }
}

/// Available tools for the Conversation Assistant
enum AvailableTools {

    /// Search documentation (Confluence, Notion, etc.)
    static let searchDocumentation = ToolDefinition(
        name: "search_documentation",
        description: """
            Search Confluence/company docs. USE THIS for:
            - Process questions: "how do we deploy", "onboarding steps"
            - Technical docs: "API documentation", "architecture overview"
            - Team knowledge: "coding standards", "best practices"
            Returns page titles, excerpts, and clickable URLs.
            TIP: Combine with search_jira to link docs to related tickets.
            """,
        input_schema: .object([
            "query": .string("Search query (e.g., 'deployment process', 'API authentication docs')"),
            "space": .string("Optional: Confluence space key to narrow search")
        ], required: ["query"])
    )

    /// Search Jira issues
    static let searchJira = ToolDefinition(
        name: "search_jira",
        description: """
            Search Jira tickets/issues. USE THIS for:
            - Specific ticket: "PROJ-123" → returns full ticket details with URL
            - My work: "my tickets", "my open issues", "assigned to me"
            - Sprint: "current sprint", "what's left", "sprint backlog"
            - Status: "in progress", "done this week", "blocked tickets"
            - Search: "authentication bug", "API error" → text search
            - Assignee: "tickets for John", "Sarah's tasks"
            Returns ticket key, status, assignee, and clickable URL.
            TIP: Use with search_codebase to find related PRs/code.
            """,
        input_schema: .object([
            "query": .string("Ticket key (PROJ-123) OR search query ('my sprint', 'open bugs')"),
            "project": .string("Optional: Jira project key (e.g., 'PROJ', 'AUTH')")
        ], required: ["query"])
    )

    /// Search codebase (GitHub, GitLab, etc.)
    static let searchCodebase = ToolDefinition(
        name: "search_codebase",
        description: """
            Search GitHub code, PRs, and issues. USE THIS for:
            - Code search: "AuthService implementation", "handleLogin function"
            - Pull requests: "open PRs", "my PRs", "auth feature PR"
            - Issues: "open issues", "bug reports", "authentication issue"
            - File patterns: use file_pattern for "*.swift", "*.ts"
            Returns file paths, PR/issue titles, and clickable GitHub URLs.
            TIP: Use ticket number from Jira to find related PRs.
            """,
        input_schema: .object([
            "query": .string("Code/PR/issue search (e.g., 'UserService', 'open PRs', 'auth bug issue')"),
            "repo": .string("Optional: repository name or owner/repo"),
            "file_pattern": .string("Optional: file filter (e.g., '*.swift', '*.ts')")
        ], required: ["query"])
    )

    /// List GitHub repositories
    static let listRepositories = ToolDefinition(
        name: "list_repositories",
        description: """
            List GitHub repositories. USE THIS for:
            - "list my repos", "show repositories", "what repos do I have"
            - "organization repos", "team repositories"
            Returns repository names, descriptions, and URLs.
            """,
        input_schema: .object([
            "type": .string("Type of repos: 'user' (your repos), 'org' (organization repos), or 'all'", enum: ["user", "org", "all"]),
            "limit": .string("Optional: max number of repos to return (default 20)")
        ], required: [])
    )

    /// Get PR details
    static let getPRDetails = ToolDefinition(
        name: "get_pr_details",
        description: """
            Get full details of a specific pull request. USE THIS for:
            - "show PR #123", "details of PR 456"
            - "what's in this PR", "PR description"
            Returns title, description, status, files changed, comments, reviews.
            """,
        input_schema: .object([
            "pr_number": .string("The pull request number"),
            "repo": .string("Optional: repository name or owner/repo (uses default if not specified)")
        ], required: ["pr_number"])
    )

    /// Get issue details
    static let getIssueDetails = ToolDefinition(
        name: "get_issue_details",
        description: """
            Get full details of a specific GitHub issue. USE THIS for:
            - "show issue #123", "issue details"
            - "what's this issue about"
            Returns title, description, status, labels, comments, assignees.
            """,
        input_schema: .object([
            "issue_number": .string("The issue number"),
            "repo": .string("Optional: repository name or owner/repo (uses default if not specified)")
        ], required: ["issue_number"])
    )

    /// List branches
    static let listBranches = ToolDefinition(
        name: "list_branches",
        description: """
            List branches in a repository. USE THIS for:
            - "list branches", "show branches"
            - "what branches exist", "feature branches"
            Returns branch names and last commit info.
            """,
        input_schema: .object([
            "repo": .string("Optional: repository name or owner/repo (uses default if not specified)"),
            "limit": .string("Optional: max number of branches to return (default 20)")
        ], required: [])
    )

    /// List Jira projects
    static let listJiraProjects = ToolDefinition(
        name: "list_jira_projects",
        description: """
            List all Jira projects you have access to. USE THIS for:
            - "list projects", "show Jira projects", "what projects are there"
            - "available projects"
            Returns project names, keys, and descriptions.
            """,
        input_schema: .object([
            "limit": .string("Optional: max number of projects to return (default 20)")
        ], required: [])
    )

    /// Get sprint info
    static let getSprintInfo = ToolDefinition(
        name: "get_sprint_info",
        description: """
            Get current sprint information and issues. USE THIS for:
            - "current sprint", "sprint status", "sprint progress"
            - "what's in this sprint", "sprint issues"
            Returns sprint name, dates, goals, and all sprint issues with status.
            """,
        input_schema: .object([
            "board_id": .string("Optional: Jira board ID (uses default board if not specified)"),
            "sprint_state": .string("Optional: 'active', 'future', or 'closed' (default: active)", enum: ["active", "future", "closed"])
        ], required: [])
    )

    /// List Jira boards
    static let listJiraBoards = ToolDefinition(
        name: "list_jira_boards",
        description: """
            List Jira boards (Scrum/Kanban). USE THIS for:
            - "list boards", "show boards", "what boards are there"
            - "scrum boards", "kanban boards"
            Returns board names, types, and associated projects.
            """,
        input_schema: .object([
            "project": .string("Optional: filter boards by project key"),
            "type": .string("Optional: 'scrum' or 'kanban'", enum: ["scrum", "kanban"])
        ], required: [])
    )

    /// Get Confluence page
    static let getConfluencePage = ToolDefinition(
        name: "get_confluence_page",
        description: """
            Get full content of a specific Confluence page. USE THIS for:
            - "show page X", "get page content"
            - "read this documentation page"
            Returns full page content in readable format.
            """,
        input_schema: .object([
            "page_id": .string("Confluence page ID"),
            "title": .string("Optional: page title to search for (if page_id not known)")
        ], required: [])
    )

    /// List Confluence spaces
    static let listConfluenceSpaces = ToolDefinition(
        name: "list_confluence_spaces",
        description: """
            List Confluence spaces. USE THIS for:
            - "list spaces", "show confluence spaces"
            - "what documentation spaces exist"
            Returns space names, keys, and descriptions.
            """,
        input_schema: .object([
            "limit": .string("Optional: max number of spaces to return (default 20)")
        ], required: [])
    )

    /// Query database
    static let queryDatabase = ToolDefinition(
        name: "query_database",
        description: """
            Query databases using natural language. USE THIS for:
            - Data lookups: "how many users signed up today"
            - Metrics: "average response time last week"
            - Records: "find user with email X"
            Converts natural language to SQL automatically.
            """,
        input_schema: .object([
            "question": .string("Natural language question about the data"),
            "database": .string("Database name to query")
        ], required: ["question", "database"])
    )

    /// Web search
    static let webSearch = ToolDefinition(
        name: "web_search",
        description: """
            Search the web for external information. USE THIS for:
            - Library docs: "React hooks documentation"
            - Error solutions: "Swift async/await error handling"
            - Best practices: "Kubernetes deployment patterns"
            - Current info: "latest Swift version"
            Use ONLY when internal tools don't have the answer.
            """,
        input_schema: .object([
            "query": .string("Web search query")
        ], required: ["query"])
    )

    /// All available tools
    static let all: [ToolDefinition] = [
        searchDocumentation,
        searchJira,
        searchCodebase,
        listRepositories,
        getPRDetails,
        getIssueDetails,
        listBranches,
        listJiraProjects,
        getSprintInfo,
        listJiraBoards,
        getConfluencePage,
        listConfluenceSpaces,
        queryDatabase,
        webSearch
    ]
}
