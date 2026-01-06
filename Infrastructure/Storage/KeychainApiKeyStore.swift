import Foundation
import Security

/// Secure storage for API key using macOS Keychain
class KeychainApiKeyStore {

    private let service: String
    private let account: String

    init(service: String = "com.interviewmaster.apikey", account: String = "default") {
        self.service = service
        self.account = account
    }

    enum KeychainError: Error, LocalizedError {
        case saveFailed(OSStatus)
        case retrieveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case invalidData
        case notFound

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to keychain: \(status)"
            case .retrieveFailed(let status):
                return "Failed to retrieve from keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from keychain: \(status)"
            case .invalidData:
                return "Invalid data format"
            case .notFound:
                return "API key not found in keychain"
            }
        }
    }

    /// Save API key to keychain
    /// - Parameter apiKey: The API key to save
    /// - Returns: Result indicating success or failure
    func save(_ apiKey: String) -> Result<Void, KeychainError> {
        guard let data = apiKey.data(using: .utf8) else {
            return .failure(.invalidData)
        }

        // First, try to delete any existing key
        _ = delete()

        // Build query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Add to keychain
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            return .failure(.saveFailed(status))
        }

        return .success(())
    }

    /// Retrieve API key from keychain
    /// - Returns: Result with API key string or error
    func retrieve() -> Result<String, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return .failure(.notFound)
            }
            return .failure(.retrieveFailed(status))
        }

        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return .failure(.invalidData)
        }

        return .success(apiKey)
    }

    /// Delete API key from keychain
    /// - Returns: Result indicating success or failure
    func delete() -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.deleteFailed(status))
        }

        return .success(())
    }

    /// Check if API key exists in keychain
    /// - Returns: true if key exists, false otherwise
    func exists() -> Bool {
        switch retrieve() {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
