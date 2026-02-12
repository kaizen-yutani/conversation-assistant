import Foundation

/// Client for web search using Tavily or similar APIs
class WebSearchClient: Tool {
    static let shared = WebSearchClient()

    let name = "web_search"
    let displayName = "Web Search"

    enum SearchProvider: String, CaseIterable {
        case tavily = "tavily"
        case serper = "serper"
        case brave = "brave"

        var displayName: String {
            switch self {
            case .tavily: return "Tavily"
            case .serper: return "Serper"
            case .brave: return "Brave Search"
            }
        }
    }

    private init() {}

    var isConfigured: Bool {
        return DataSourceConfig.shared.webSearchConfig != nil
    }

    func execute(input: [String: Any]) async throws -> ToolResult {
        guard let query = input["query"] as? String else {
            throw ToolError.missingParameter("query")
        }

        guard let config = DataSourceConfig.shared.webSearchConfig else {
            throw ToolError.notConfigured("Web Search")
        }

        let provider = SearchProvider(rawValue: config.provider.lowercased()) ?? .tavily

        switch provider {
        case .tavily:
            return try await searchWithTavily(query: query, apiKey: config.apiKey)
        case .serper:
            return try await searchWithSerper(query: query, apiKey: config.apiKey)
        case .brave:
            return try await searchWithBrave(query: query, apiKey: config.apiKey)
        }
    }

    // MARK: - Tavily Search

    private func searchWithTavily(query: String, apiKey: String) async throws -> ToolResult {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "search_depth": "basic",
            "max_results": 5
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response from Tavily")
        }
        guard httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed(parseSearchError(provider: "Tavily", statusCode: httpResponse.statusCode))
        }

        let result = try JSONDecoder().decode(TavilyResponse.self, from: data)

        if result.results.isEmpty {
            return .success(content: "No results found for: \(query)")
        }

        let content = result.results.map { item in
            """
            ## \(item.title)
            URL: \(item.url)
            \(item.content)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: content)
    }

    // MARK: - Serper Search

    private func searchWithSerper(query: String, apiKey: String) async throws -> ToolResult {
        guard let url = URL(string: "https://google.serper.dev/search") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")

        let body: [String: Any] = ["q": query, "num": 5]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response from Serper")
        }
        guard httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed(parseSearchError(provider: "Serper", statusCode: httpResponse.statusCode))
        }

        let result = try JSONDecoder().decode(SerperResponse.self, from: data)

        if result.organic.isEmpty {
            return .success(content: "No results found for: \(query)")
        }

        let content = result.organic.map { item in
            """
            ## \(item.title)
            URL: \(item.link)
            \(item.snippet)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: content)
    }

    // MARK: - Brave Search

    private func searchWithBrave(query: String, apiKey: String) async throws -> ToolResult {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encodedQuery)&count=5") else {
            throw ToolError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response from Brave")
        }
        guard httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed(parseSearchError(provider: "Brave", statusCode: httpResponse.statusCode))
        }

        let result = try JSONDecoder().decode(BraveResponse.self, from: data)

        guard let webResults = result.web?.results, !webResults.isEmpty else {
            return .success(content: "No results found for: \(query)")
        }

        let content = webResults.map { item in
            """
            ## \(item.title)
            URL: \(item.url)
            \(item.description)
            """
        }.joined(separator: "\n\n---\n\n")

        return .success(content: content)
    }

    // MARK: - Error Handling

    private func parseSearchError(provider: String, statusCode: Int) -> String {
        switch statusCode {
        case 401:
            return "\(provider) authentication failed. Please check your API key in Settings."
        case 403:
            return "\(provider) access denied. Your API key may lack permissions or quota is exceeded."
        case 429:
            return "\(provider) rate limited. Please wait a moment and try again."
        case 500...599:
            return "\(provider) server error (\(statusCode)). Please try again later."
        default:
            return "\(provider) request failed (HTTP \(statusCode))."
        }
    }
}

// MARK: - Response Models

private struct TavilyResponse: Codable {
    let results: [TavilyResult]
}

private struct TavilyResult: Codable {
    let title: String
    let url: String
    let content: String
}

private struct SerperResponse: Codable {
    let organic: [SerperResult]
}

private struct SerperResult: Codable {
    let title: String
    let link: String
    let snippet: String
}

private struct BraveResponse: Codable {
    let web: BraveWebResults?
}

private struct BraveWebResults: Codable {
    let results: [BraveResult]
}

private struct BraveResult: Codable {
    let title: String
    let url: String
    let description: String
}
