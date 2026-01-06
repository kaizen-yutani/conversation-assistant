import Foundation

/// Use case for configuring the Anthropic API key
class ConfigureApiKeyUseCase {

    private let keyStore: KeychainApiKeyStore

    enum ConfigError: Error, LocalizedError {
        case invalidApiKey
        case saveFailed(String)
        case retrieveFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidApiKey:
                return "Invalid API key format. Must start with 'sk-ant-'"
            case .saveFailed(let message):
                return "Failed to save API key: \(message)"
            case .retrieveFailed(let message):
                return "Failed to retrieve API key: \(message)"
            }
        }
    }

    init(keyStore: KeychainApiKeyStore) {
        self.keyStore = keyStore
    }

    /// Save API key
    /// - Parameter apiKeyString: Raw API key string
    /// - Returns: Validated ApiKey or error
    func save(_ apiKeyString: String) -> Result<ApiKey, ConfigError> {
        // Validate API key
        guard let apiKey = ApiKey(apiKeyString) else {
            return .failure(.invalidApiKey)
        }

        // Save to keychain
        let saveResult = keyStore.save(apiKey.rawValue)

        switch saveResult {
        case .success:
            return .success(apiKey)
        case .failure(let error):
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    /// Retrieve saved API key
    /// - Returns: ApiKey or error
    func retrieve() -> Result<ApiKey, ConfigError> {
        let retrieveResult = keyStore.retrieve()

        switch retrieveResult {
        case .success(let apiKeyString):
            guard let apiKey = ApiKey(apiKeyString) else {
                return .failure(.invalidApiKey)
            }
            return .success(apiKey)

        case .failure(let error):
            return .failure(.retrieveFailed(error.localizedDescription))
        }
    }

    /// Check if API key exists
    /// - Returns: true if exists, false otherwise
    func exists() -> Bool {
        return keyStore.exists()
    }

    /// Delete saved API key
    /// - Returns: Success or error
    func delete() -> Result<Void, ConfigError> {
        let deleteResult = keyStore.delete()

        switch deleteResult {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(.saveFailed(error.localizedDescription))
        }
    }
}
