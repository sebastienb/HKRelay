import BridgeCore
import Foundation

struct CredentialStore {
    private struct Credentials: Codable {
        var token: String
    }

    let environment: [String: String]
    let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    func loadToken() throws -> String? {
        for key in ["HKRELAY_TOKEN", "HKBRIDGE_TOKEN"] {
            if let token = environment[key], !token.isEmpty { return token }
        }

        guard fileManager.fileExists(atPath: credentialsURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: credentialsURL)
        return try JSONDecoder().decode(Credentials.self, from: data).token
    }

    func saveToken(_ token: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw CLIError(code: "empty_token", message: "The token cannot be empty.")
        }

        let directory = credentialsURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let data = try JSONEncoder().encode(Credentials(token: trimmedToken))
        try PrivateFile.write(data, to: credentialsURL)
    }

    var credentialsURL: URL {
        for key in ["HKRELAY_CONFIG_DIR", "HKBRIDGE_CONFIG_DIR"] {
            if let configuredPath = environment[key], !configuredPath.isEmpty {
                return URL(fileURLWithPath: configuredPath, isDirectory: true)
                    .appendingPathComponent("credentials.json", isDirectory: false)
            }
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("hkbridge", isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }
}
