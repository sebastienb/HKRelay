import Foundation

public enum RequestClientKind: String, Codable, CaseIterable, Sendable {
    case cli
    case curl
    case browser
    case apiClient

    public var displayName: String {
        switch self {
        case .cli: "HomeKitLink CLI"
        case .curl: "curl"
        case .browser: "Web browser"
        case .apiClient: "API client"
        }
    }
}

public struct RequestHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let method: String
    public let path: String
    public let client: RequestClientKind
    public let statusCode: Int
    public let durationMilliseconds: Int
    public let requestBody: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        path: String,
        client: RequestClientKind,
        statusCode: Int,
        durationMilliseconds: Int,
        requestBody: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.client = client
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
        self.requestBody = requestBody
    }
}

public enum RequestHistorySanitizer {
    public static func path(_ path: String) -> String {
        guard let queryStart = path.firstIndex(of: "?") else { return path }
        return String(path[..<queryStart]) + "?[redacted]"
    }

    public static func client(userAgent: String?) -> RequestClientKind {
        guard let userAgent = userAgent?.lowercased() else { return .apiClient }

        if userAgent.hasPrefix("homekitlink-cli/") || userAgent.hasPrefix("hkbridge-cli/") {
            return .cli
        }
        if userAgent.hasPrefix("curl/") {
            return .curl
        }
        if userAgent.contains("mozilla/") {
            return .browser
        }
        return .apiClient
    }

    public static func requestBody(_ data: Data, characterLimit: Int = 8_192) -> String? {
        guard !data.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return "[Non-JSON request body omitted: \(data.count) bytes]"
        }

        let redacted = redactSensitiveValues(in: object)
        guard let safeData = try? JSONSerialization.data(
            withJSONObject: redacted,
            options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys]
        ) else {
            return "[Request body could not be displayed]"
        }

        let text = String(decoding: safeData, as: UTF8.self)
        guard text.count > characterLimit else { return text }
        return String(text.prefix(characterLimit)) + "\n… [truncated]"
    }

    private static func redactSensitiveValues(in value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = isSensitiveKey(item.key)
                    ? "[REDACTED]"
                    : redactSensitiveValues(in: item.value)
            }
        }

        if let array = value as? [Any] {
            return array.map(redactSensitiveValues(in:))
        }

        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("credential")
            || normalized == "apikey"
            || normalized == "auth"
            || normalized == "authorization"
    }
}
