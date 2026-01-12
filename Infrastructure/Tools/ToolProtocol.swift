import Foundation

/// Protocol for tool implementations
protocol Tool {
    /// Unique name of the tool (must match ToolDefinition.name)
    var name: String { get }
    
    /// Human-readable display name
    var displayName: String { get }
    
    /// Whether this tool is properly configured and ready to use
    var isConfigured: Bool { get }
    
    /// Execute the tool with the given input parameters
    /// - Parameter input: Dictionary of input parameters from Claude's tool use request
    /// - Returns: ToolResult containing the output or error
    func execute(input: [String: Any]) async throws -> ToolResult
}

/// Result from executing a tool
struct ToolResult {
    /// Whether the tool execution was successful
    let success: Bool
    
    /// Content to send back to Claude for processing
    let content: String
    
    /// Optional URL to the source of the information
    let sourceUrl: String?
    
    /// Optional error message if execution failed
    let error: String?
    
    /// Create a successful result
    static func success(content: String, sourceUrl: String? = nil) -> ToolResult {
        ToolResult(success: true, content: content, sourceUrl: sourceUrl, error: nil)
    }
    
    /// Create a failure result
    static func failure(error: String) -> ToolResult {
        ToolResult(success: false, content: "", sourceUrl: nil, error: error)
    }
    
    /// Convert to dictionary format for Claude API
    func toAPIContent() -> [[String: Any]] {
        if success {
            return [["type": "text", "text": content]]
        } else {
            return [["type": "text", "text": "Error: \(error ?? "Unknown error")"]]
        }
    }
}

/// Tool use request from Claude API
struct ToolUseRequest {
    let id: String
    let name: String
    let input: [String: Any]
}

/// Tool result to send back to Claude API
struct ToolResultMessage {
    let toolUseId: String
    let content: [[String: Any]]
    
    init(toolUseId: String, result: ToolResult) {
        self.toolUseId = toolUseId
        self.content = result.toAPIContent()
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "type": "tool_result",
            "tool_use_id": toolUseId,
            "content": content
        ]
    }
}

/// Errors that can occur during tool execution
enum ToolError: Error, LocalizedError {
    case missingParameter(String)
    case notConfigured(String)
    case executionFailed(String)
    case unknownTool(String)
    
    var errorDescription: String? {
        switch self {
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .notConfigured(let tool):
            return "Tool not configured: \(tool)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        }
    }
}
