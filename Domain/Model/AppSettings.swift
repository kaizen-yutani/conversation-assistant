import Foundation

/// User role/position for context-aware responses
enum UserRole: String, CaseIterable {
    case softwareEngineer = "software_engineer"
    case seniorEngineer = "senior_engineer"
    case techLead = "tech_lead"
    case engineeringManager = "engineering_manager"
    case productManager = "product_manager"
    case qaEngineer = "qa_engineer"
    case devopsEngineer = "devops_engineer"
    case designer = "designer"
    case scrumMaster = "scrum_master"

    var displayName: String {
        switch self {
        case .softwareEngineer: return "Software Engineer"
        case .seniorEngineer: return "Senior Engineer"
        case .techLead: return "Tech Lead"
        case .engineeringManager: return "Engineering Manager"
        case .productManager: return "Product Manager"
        case .qaEngineer: return "QA Engineer"
        case .devopsEngineer: return "DevOps Engineer"
        case .designer: return "Designer"
        case .scrumMaster: return "Scrum Master"
        }
    }
}

/// Supported languages for the conversation assistant
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case bulgarian = "bg"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .bulgarian: return "Bulgarian"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }

    var llmInstruction: String {
        if self == .english {
            return ""
        }
        return "\n\nIMPORTANT: Respond in \(displayName) language."
    }
}

/// Global app settings with UserDefaults persistence
class AppSettings {
    static let shared = AppSettings()

    private let languageKey = "ConversationAssistant.Language"
    private let userRoleKey = "ConversationAssistant.UserRole"
    private let useStreamingSTTKey = "ConversationAssistant.UseStreamingSTT"

    private init() {}

    /// Enable Deepgram streaming STT (requires DEEPGRAM_API_KEY)
    var useStreamingSTT: Bool {
        get {
            // Default to true if Deepgram key is available
            if !UserDefaults.standard.bool(forKey: useStreamingSTTKey + ".set") {
                return ApiKeyManager.shared.hasKey(.deepgram)
            }
            return UserDefaults.standard.bool(forKey: useStreamingSTTKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useStreamingSTTKey)
            UserDefaults.standard.set(true, forKey: useStreamingSTTKey + ".set")
        }
    }

    var language: AppLanguage {
        get {
            guard let code = UserDefaults.standard.string(forKey: languageKey),
                  let lang = AppLanguage(rawValue: code) else {
                return .english
            }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
        }
    }

    var userRole: UserRole {
        get {
            guard let code = UserDefaults.standard.string(forKey: userRoleKey),
                  let role = UserRole(rawValue: code) else {
                return .softwareEngineer
            }
            return role
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userRoleKey)
        }
    }

    var languageCode: String {
        return language.rawValue
    }

    var llmLanguageInstruction: String {
        return language.llmInstruction
    }
}
