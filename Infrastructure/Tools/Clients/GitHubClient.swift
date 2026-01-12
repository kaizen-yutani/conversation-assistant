import Foundation

/// Client for searching GitHub repositories, PRs, and issues
class GitHubClient: Tool {
    static let shared = GitHubClient()

    let name = "search_codebase"
    let displayName = "GitHub"

    private init() {}

    var isConfigured: Bool {
        return DataSourceConfig.shared.githubConfig != nil
    }

    func execute(input: [String: Any]) async throws -> ToolResult {
        guard let query = input["query"] as? String else {
            throw ToolError.missingParameter("query")
        }

        guard let config = DataSourceConfig.shared.githubConfig else {
            throw ToolError.notConfigured("GitHub")
        }

        let repo = input["repo"] as? String
        let filePattern = input["file_pattern"] as? String
        let lowercased = query.lowercased()

        // Detect PR/Issue searches
        let prPatterns = ["pr", "pull request", "merge request", "open pr", "my pr", "prs"]
        let issuePatterns = ["issue", "bug", "open issue", "my issue", "issues"]

        let isPrSearch = prPatterns.contains { lowercased.contains($0) }
        let isIssueSearch = issuePatterns.contains { lowercased.contains($0) }

        if isPrSearch {
            return try await searchPullRequests(query: query, repo: repo, config: config)
        } else if isIssueSearch {
            return try await searchIssues(query: query, repo: repo, config: config)
        } else {
            return try await searchCode(query: query, repo: repo, filePattern: filePattern, config: config)
        }
    }

    /// List repositories for the authenticated user or organization
    func listRepositories(input: [String: Any]) async throws -> ToolResult {
        guard let config = DataSourceConfig.shared.githubConfig else {
            throw ToolError.notConfigured("GitHub")
        }

        let repoType = (input["type"] as? String) ?? "all"
        let limitStr = (input["limit"] as? String) ?? "20"
        let limit = Int(limitStr) ?? 20

        var url: URL?

        switch repoType {
        case "user":
            // User's own repos
            url = URL(string: "https://api.github.com/user/repos?per_page=\(limit)&sort=updated")
        case "org":
            // Organization repos
            url = URL(string: "https://api.github.com/orgs/\(config.owner)/repos?per_page=\(limit)&sort=updated")
        default:
            // All repos user has access to
            url = URL(string: "https://api.github.com/user/repos?per_page=\(limit)&sort=updated&affiliation=owner,collaborator,organization_member")
        }

        guard let requestUrl = url else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let repos: [GitHubRepoItem] = try await makeRequest(url: requestUrl, token: config.token)

        if repos.isEmpty {
            return .success(content: "No repositories found.")
        }

        let content = repos.prefix(limit).map { repo in
            let visibility = repo.private ? "Private" : "Public"
            let desc = repo.description ?? "No description"
            let stars = repo.stargazers_count > 0 ? " | ⭐ \(repo.stargazers_count)" : ""
            return """
            ## \(repo.full_name)
            **\(visibility)**\(stars) | Updated: \(String(repo.updated_at.prefix(10)))
            \(desc)
            URL: \(repo.html_url)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(repos.count) repositories:\n\n\(content)")
    }

    // MARK: - Code Search

    private func searchCode(query: String, repo: String?, filePattern: String?, config: (owner: String, repo: String, token: String)) async throws -> ToolResult {
        var searchQuery = query

        if let repo = repo {
            if repo.contains("/") {
                searchQuery += " repo:\(repo)"
            } else {
                searchQuery += " repo:\(config.owner)/\(repo)"
            }
        } else if !config.repo.isEmpty {
            searchQuery += " repo:\(config.owner)/\(config.repo)"
        } else {
            searchQuery += " org:\(config.owner)"
        }

        if let pattern = filePattern {
            let pathFilter = pattern.replacingOccurrences(of: "*", with: "")
            if !pathFilter.isEmpty {
                searchQuery += " path:\(pathFilter)"
            }
        }

        guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.github.com/search/code?q=\(encodedQuery)&per_page=10") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let results: GitHubSearchResponse = try await makeRequest(url: url, token: config.token)

        if results.items.isEmpty {
            return .success(content: "No code results found for: \(query)")
        }

        let content = results.items.prefix(10).map { item in
            """
            ## \(item.path)
            Repository: \(item.repository.full_name)
            URL: \(item.html_url)
            """
        }.joined(separator: "\n\n")

        return .success(content: "Found \(results.total_count) code results:\n\n\(content)")
    }

    // MARK: - PR Search

    private func searchPullRequests(query: String, repo: String?, config: (owner: String, repo: String, token: String)) async throws -> ToolResult {
        // Clean query for PR search
        let cleanQuery = query.lowercased()
            .replacingOccurrences(of: "pull request", with: "")
            .replacingOccurrences(of: "my prs", with: "")
            .replacingOccurrences(of: "open prs", with: "")
            .replacingOccurrences(of: "prs", with: "")
            .replacingOccurrences(of: "pr", with: "")
            .trimmingCharacters(in: .whitespaces)

        var searchQuery = cleanQuery.isEmpty ? "" : "\(cleanQuery) "
        searchQuery += "is:pr"

        // Add state filter
        if query.lowercased().contains("open") {
            searchQuery += " is:open"
        } else if query.lowercased().contains("closed") || query.lowercased().contains("merged") {
            searchQuery += " is:closed"
        }

        // Add repo filter
        if let repo = repo {
            if repo.contains("/") {
                searchQuery += " repo:\(repo)"
            } else {
                searchQuery += " repo:\(config.owner)/\(repo)"
            }
        } else if !config.repo.isEmpty {
            searchQuery += " repo:\(config.owner)/\(config.repo)"
        } else {
            searchQuery += " org:\(config.owner)"
        }

        guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.github.com/search/issues?q=\(encodedQuery)&per_page=10&sort=updated") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let results: GitHubIssueSearchResponse = try await makeRequest(url: url, token: config.token)

        if results.items.isEmpty {
            return .success(content: "No pull requests found for: \(query)")
        }

        let content = results.items.prefix(10).map { pr in
            let state = pr.state.capitalized
            let user = pr.user.login
            return """
            ## #\(pr.number): \(pr.title)
            **Status:** \(state) | **Author:** \(user) | **Updated:** \(String(pr.updated_at.prefix(10)))
            URL: \(pr.html_url)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(results.total_count) pull requests:\n\n\(content)")
    }

    // MARK: - Issue Search

    private func searchIssues(query: String, repo: String?, config: (owner: String, repo: String, token: String)) async throws -> ToolResult {
        // Clean query for issue search
        let cleanQuery = query.lowercased()
            .replacingOccurrences(of: "open issues", with: "")
            .replacingOccurrences(of: "my issues", with: "")
            .replacingOccurrences(of: "issues", with: "")
            .replacingOccurrences(of: "issue", with: "")
            .replacingOccurrences(of: "bug", with: "")
            .trimmingCharacters(in: .whitespaces)

        var searchQuery = cleanQuery.isEmpty ? "" : "\(cleanQuery) "
        searchQuery += "is:issue"

        // Add state filter
        if query.lowercased().contains("open") {
            searchQuery += " is:open"
        } else if query.lowercased().contains("closed") {
            searchQuery += " is:closed"
        }

        // Add repo filter
        if let repo = repo {
            if repo.contains("/") {
                searchQuery += " repo:\(repo)"
            } else {
                searchQuery += " repo:\(config.owner)/\(repo)"
            }
        } else if !config.repo.isEmpty {
            searchQuery += " repo:\(config.owner)/\(config.repo)"
        } else {
            searchQuery += " org:\(config.owner)"
        }

        guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.github.com/search/issues?q=\(encodedQuery)&per_page=10&sort=updated") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let results: GitHubIssueSearchResponse = try await makeRequest(url: url, token: config.token)

        if results.items.isEmpty {
            return .success(content: "No issues found for: \(query)")
        }

        let content = results.items.prefix(10).map { issue in
            let state = issue.state.capitalized
            let user = issue.user.login
            let labels = issue.labels.map { $0.name }.joined(separator: ", ")
            return """
            ## #\(issue.number): \(issue.title)
            **Status:** \(state) | **Author:** \(user)\(labels.isEmpty ? "" : " | **Labels:** \(labels)")
            URL: \(issue.html_url)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: "Found \(results.total_count) issues:\n\n\(content)")
    }

    // MARK: - Get PR Details

    /// Get full details of a specific pull request
    func getPRDetails(input: [String: Any]) async throws -> ToolResult {
        guard let prNumberStr = input["pr_number"] as? String,
              let prNumber = Int(prNumberStr) else {
            throw ToolError.missingParameter("pr_number")
        }

        guard let config = DataSourceConfig.shared.githubConfig else {
            throw ToolError.notConfigured("GitHub")
        }

        let repo = input["repo"] as? String
        let repoPath: String

        if let repo = repo {
            repoPath = repo.contains("/") ? repo : "\(config.owner)/\(repo)"
        } else if !config.repo.isEmpty {
            repoPath = "\(config.owner)/\(config.repo)"
        } else {
            throw ToolError.missingParameter("repo")
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoPath)/pulls/\(prNumber)") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let pr: GitHubPRDetail = try await makeRequest(url: url, token: config.token)

        let status = pr.merged == true ? "Merged" : pr.state.capitalized
        let additions = pr.additions ?? 0
        let deletions = pr.deletions ?? 0
        let changedFiles = pr.changed_files ?? 0
        let body = pr.body ?? "No description"

        let content = """
        # PR #\(pr.number): \(pr.title)

        **Status:** \(status) | **Author:** \(pr.user.login)
        **Branch:** \(pr.head.ref) → \(pr.base.ref)
        **Created:** \(String(pr.created_at.prefix(10))) | **Updated:** \(String(pr.updated_at.prefix(10)))
        \(pr.merged_at.map { "**Merged:** \(String($0.prefix(10)))" } ?? "")

        **Changes:** +\(additions) -\(deletions) in \(changedFiles) files

        URL: \(pr.html_url)

        ---

        ## Description
        \(body)
        """

        return .success(content: content)
    }

    // MARK: - Get Issue Details

    /// Get full details of a specific GitHub issue
    func getIssueDetails(input: [String: Any]) async throws -> ToolResult {
        guard let issueNumberStr = input["issue_number"] as? String,
              let issueNumber = Int(issueNumberStr) else {
            throw ToolError.missingParameter("issue_number")
        }

        guard let config = DataSourceConfig.shared.githubConfig else {
            throw ToolError.notConfigured("GitHub")
        }

        let repo = input["repo"] as? String
        let repoPath: String

        if let repo = repo {
            repoPath = repo.contains("/") ? repo : "\(config.owner)/\(repo)"
        } else if !config.repo.isEmpty {
            repoPath = "\(config.owner)/\(config.repo)"
        } else {
            throw ToolError.missingParameter("repo")
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoPath)/issues/\(issueNumber)") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let issue: GitHubIssueDetail = try await makeRequest(url: url, token: config.token)

        let labels = issue.labels.map { $0.name }.joined(separator: ", ")
        let assignees = issue.assignees?.map { $0.login }.joined(separator: ", ") ?? "Unassigned"
        let body = issue.body ?? "No description"

        let content = """
        # Issue #\(issue.number): \(issue.title)

        **Status:** \(issue.state.capitalized) | **Author:** \(issue.user.login)
        **Assignees:** \(assignees)
        \(labels.isEmpty ? "" : "**Labels:** \(labels)")
        **Created:** \(String(issue.created_at.prefix(10))) | **Updated:** \(String(issue.updated_at.prefix(10)))
        \(issue.closed_at.map { "**Closed:** \(String($0.prefix(10)))" } ?? "")
        **Comments:** \(issue.comments)

        URL: \(issue.html_url)

        ---

        ## Description
        \(body)
        """

        return .success(content: content)
    }

    // MARK: - List Branches

    /// List branches in a repository
    func listBranches(input: [String: Any]) async throws -> ToolResult {
        guard let config = DataSourceConfig.shared.githubConfig else {
            throw ToolError.notConfigured("GitHub")
        }

        let repo = input["repo"] as? String
        let limitStr = (input["limit"] as? String) ?? "20"
        let limit = Int(limitStr) ?? 20

        let repoPath: String

        if let repo = repo {
            repoPath = repo.contains("/") ? repo : "\(config.owner)/\(repo)"
        } else if !config.repo.isEmpty {
            repoPath = "\(config.owner)/\(config.repo)"
        } else {
            throw ToolError.missingParameter("repo")
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoPath)/branches?per_page=\(limit)") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        let branches: [GitHubBranch] = try await makeRequest(url: url, token: config.token)

        if branches.isEmpty {
            return .success(content: "No branches found in \(repoPath).")
        }

        let content = branches.prefix(limit).map { branch in
            let protection = branch.protected == true ? "🔒 Protected" : ""
            return """
            - **\(branch.name)** \(protection)
              Commit: \(String(branch.commit.sha.prefix(7)))
            """
        }.joined(separator: "\n")

        return .success(content: "Branches in \(repoPath):\n\n\(content)")
    }

    // MARK: - Helper

    private func makeRequest<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("ConversationAssistant", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ToolError.executionFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response Models

private struct GitHubSearchResponse: Codable {
    let total_count: Int
    let items: [GitHubCodeItem]
}

private struct GitHubCodeItem: Codable {
    let name: String
    let path: String
    let html_url: String
    let repository: GitHubRepository
}

private struct GitHubRepository: Codable {
    let full_name: String
}

// MARK: - PR/Issue Response Models

private struct GitHubIssueSearchResponse: Codable {
    let total_count: Int
    let items: [GitHubIssueItem]
}

private struct GitHubIssueItem: Codable {
    let number: Int
    let title: String
    let state: String
    let html_url: String
    let user: GitHubUser
    let labels: [GitHubLabel]
    let updated_at: String
}

private struct GitHubUser: Codable {
    let login: String
}

private struct GitHubLabel: Codable {
    let name: String
}

// MARK: - Repository Model

private struct GitHubRepoItem: Codable {
    let name: String
    let full_name: String
    let description: String?
    let html_url: String
    let `private`: Bool
    let stargazers_count: Int
    let updated_at: String
}

// MARK: - PR Detail Models

private struct GitHubPRDetail: Codable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let html_url: String
    let user: GitHubUser
    let head: GitHubBranchRef
    let base: GitHubBranchRef
    let merged: Bool?
    let mergeable: Bool?
    let additions: Int?
    let deletions: Int?
    let changed_files: Int?
    let created_at: String
    let updated_at: String
    let merged_at: String?
}

private struct GitHubBranchRef: Codable {
    let ref: String
    let sha: String
}

// MARK: - Issue Detail Models

private struct GitHubIssueDetail: Codable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let html_url: String
    let user: GitHubUser
    let labels: [GitHubLabel]
    let assignees: [GitHubUser]?
    let comments: Int
    let created_at: String
    let updated_at: String
    let closed_at: String?
}

// MARK: - Branch Models

private struct GitHubBranch: Codable {
    let name: String
    let commit: GitHubBranchCommit
    let protected: Bool?
}

private struct GitHubBranchCommit: Codable {
    let sha: String
}
