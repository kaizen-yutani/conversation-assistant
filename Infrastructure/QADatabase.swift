import Foundation

/// Simple JSON-based Q&A database for instant answers
class QADatabase {
    static let shared = QADatabase()

    private var database: [String: QAEntry] = [:]

    struct QAEntry: Codable {
        let question: String
        let answer: String
    }

    private init() {
        loadDatabase()
    }

    private func loadDatabase() {
        // Try to load from bundle first, then from Resources folder
        let possiblePaths = [
            Bundle.main.path(forResource: "qa_database", ofType: "json"),
            FileManager.default.currentDirectoryPath + "/Resources/qa_database.json",
            (FileManager.default.currentDirectoryPath as NSString).deletingLastPathComponent + "/Resources/qa_database.json"
        ].compactMap { $0 }

        for path in possiblePaths {
            if let data = FileManager.default.contents(atPath: path) {
                do {
                    database = try JSONDecoder().decode([String: QAEntry].self, from: data)
                    print("📚 QA Database loaded: \(database.count) topics from \(path)")
                    return
                } catch {
                    print("❌ Failed to decode QA database: \(error)")
                }
            }
        }

        print("⚠️ QA Database not found, will use LLM for all answers")
    }

    /// Get answer for a topic. Returns nil if not found (use LLM fallback)
    func getAnswer(for topic: String) -> String? {
        // Try exact match first
        if let entry = database[topic] {
            return entry.answer
        }

        // Try case-insensitive match
        let lowerTopic = topic.lowercased()
        for (key, entry) in database {
            if key.lowercased() == lowerTopic {
                return entry.answer
            }
        }

        return nil
    }

    /// Check if topic exists in database
    func hasTopic(_ topic: String) -> Bool {
        return getAnswer(for: topic) != nil
    }

    /// Get all available topics
    var topics: [String] {
        return Array(database.keys).sorted()
    }
}
