import Foundation
import Security

struct TokenStore {
    static let customTokenLength = 16...128

    private let service = "org.homekitrestbridge.app"
    private let account = "loopback-api-token"
    private static let customTokenCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    func loadOrCreateToken() throws -> String {
        do {
            if let token = try loadKeychainToken() {
                return token
            }
            return try generateAndStoreToken()
        } catch let TokenStoreError.keychainFailure(status) where status == errSecMissingEntitlement {
            #if DEBUG
            if let token = try loadDevelopmentToken() {
                return token
            }
            return try generateAndStoreDevelopmentToken()
            #else
            throw TokenStoreError.keychainFailure(status)
            #endif
        }
    }

    func regenerateToken() throws -> String {
        do {
            return try generateAndStoreToken()
        } catch let TokenStoreError.keychainFailure(status) where status == errSecMissingEntitlement {
            #if DEBUG
            return try generateAndStoreDevelopmentToken()
            #else
            throw TokenStoreError.keychainFailure(status)
            #endif
        }
    }

    func setToken(_ value: String) throws -> String {
        let token = try Self.validatedCustomToken(value)
        do {
            try storeKeychainToken(token)
        } catch let TokenStoreError.keychainFailure(status) where status == errSecMissingEntitlement {
            #if DEBUG
            try storeDevelopmentToken(token)
            #else
            throw TokenStoreError.keychainFailure(status)
            #endif
        }
        return token
    }

    static func isValidCustomToken(_ value: String) -> Bool {
        (try? validatedCustomToken(value)) != nil
    }

    private func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw TokenStoreError.randomGenerationFailed(status)
        }

        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateAndStoreToken() throws -> String {
        let token = try generateToken()

        try storeKeychainToken(token)
        return token
    }

    private func storeKeychainToken(_ token: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(deleteQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw TokenStoreError.keychainFailure(updateStatus)
        }

        var addQuery = deleteQuery
        addQuery.merge(attributes) { _, newValue in newValue }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TokenStoreError.keychainFailure(addStatus)
        }
    }

    private func loadKeychainToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TokenStoreError.keychainFailure(status)
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw TokenStoreError.invalidToken
        }
        return token
    }

    #if DEBUG
    private var developmentTokenURL: URL {
        get throws {
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return supportDirectory
                .appendingPathComponent("HomeKitRESTBridge", isDirectory: true)
                .appendingPathComponent("development-api-token", isDirectory: false)
        }
    }

    private func loadDevelopmentToken() throws -> String? {
        let url = try developmentTokenURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                throw TokenStoreError.invalidToken
            }
            return token
        } catch let error as TokenStoreError {
            throw error
        } catch {
            throw TokenStoreError.fileFailure(error.localizedDescription)
        }
    }

    private func generateAndStoreDevelopmentToken() throws -> String {
        let token = try generateToken()
        try storeDevelopmentToken(token)
        return token
    }

    private func storeDevelopmentToken(_ token: String) throws {
        let url = try developmentTokenURL
        let directory = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data(token.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw TokenStoreError.fileFailure(error.localizedDescription)
        }
    }
    #endif

    private static func validatedCustomToken(_ value: String) throws -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard customTokenLength.contains(token.count),
              token.unicodeScalars.allSatisfy(customTokenCharacters.contains) else {
            throw TokenStoreError.invalidCustomToken
        }
        return token
    }
}

enum TokenStoreError: LocalizedError {
    case randomGenerationFailed(OSStatus)
    case keychainFailure(OSStatus)
    case invalidToken
    case invalidCustomToken
    case fileFailure(String)

    var errorDescription: String? {
        switch self {
        case let .randomGenerationFailed(status):
            "Could not generate an API token (status \(status))."
        case let .keychainFailure(status):
            "Could not access the Keychain (status \(status))."
        case .invalidToken:
            "The stored API token is invalid."
        case .invalidCustomToken:
            "The token must be 16-128 characters using only letters, numbers, hyphens, periods, underscores, or tildes."
        case let .fileFailure(message):
            "Could not access the private development token file: \(message)"
        }
    }
}
