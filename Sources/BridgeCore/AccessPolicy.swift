import Foundation

public enum AccessLevel: String, Codable, CaseIterable, Sendable {
    case denied
    case readOnly = "read"
    case readWrite = "read-write"

    public var allowsRead: Bool {
        self != .denied
    }

    public var allowsWrite: Bool {
        self == .readWrite
    }
}

public struct AccessRule: Codable, Equatable, Sendable {
    public var accessoryID: String
    public var access: AccessLevel
    public var characteristicOverrides: [String: AccessLevel]

    public init(
        accessoryID: String,
        access: AccessLevel = .denied,
        characteristicOverrides: [String: AccessLevel] = [:]
    ) {
        self.accessoryID = accessoryID
        self.access = access
        self.characteristicOverrides = characteristicOverrides
    }

    public func effectiveAccess(for characteristicID: String) -> AccessLevel {
        characteristicOverrides[characteristicID] ?? access
    }
}

public struct PolicyDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var rules: [String: AccessRule]

    public init(version: Int = 1, rules: [String: AccessRule] = [:]) {
        self.version = version
        self.rules = rules
    }

    public func access(for accessoryID: String, characteristicID: String) -> AccessLevel {
        rules[accessoryID]?.effectiveAccess(for: characteristicID) ?? .denied
    }
}
