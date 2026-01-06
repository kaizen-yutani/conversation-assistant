import Foundation

/// Value Object: Analysis Mode
/// Smart analysis that adapts to screenshot content
enum AnalysisMode {
    case smart

    var prompt: String {
        let stack = AppSettings.shared.techStack
        let language = AppSettings.shared.language
        let languageInstruction = language == .english ? "" : "\n- Respond in \(language.displayName) (code stays in English)"

        return """
        You are an expert coding interview assistant. Provide a clean, practical solution in \(stack.displayName).

        FORMAT:

        ## Solution
        ```\(stack.rawValue)
        // Comment explaining this section
        code here

        // Comment explaining next part
        more code
        ```

        **Time:** O(?) | **Space:** O(?)

        ## Common Follow-up Questions
        • Question 1?
        • Question 2?
        • Question 3?

        RULES:
        - Write ALL code in \(stack.displayName)
        - NO analysis header, NO "this is a coding task" preamble
        - Jump straight to the solution
        - Add inline comments explaining each key part of the code
        - Keep complexity analysis to ONE line
        - List 3-4 most likely follow-up questions the interviewer might ask
        - Use proper markdown formatting\(languageInstruction)
        """
    }
}
