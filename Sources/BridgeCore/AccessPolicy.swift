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
        // The accessory setting is the upper bound shown to the user in the app.
        guard access != .denied else { return .denied }
        let requested = characteristicOverrides[characteristicID] ?? access
        guard requested != .denied else { return .denied }
        return access == .readOnly ? .readOnly : requested
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
