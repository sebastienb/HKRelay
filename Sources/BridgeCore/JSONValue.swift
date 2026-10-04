import Foundation
import CoreFoundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public init(any value: Any?) throws {
        switch value {
        case nil, is NSNull:
            self = .null
        case let value as NSNumber:
            // NSNumber(0/1) also bridges to Bool; distinguish the actual CFBoolean type.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as Data:
            self = .string(value.base64EncodedString())
        case let value as [Any]:
            self = .array(try value.map { try JSONValue(any: $0) })
        case let value as [String: Any]:
            self = .object(try value.mapValues { try JSONValue(any: $0) })
        default:
            throw APIError(
                code: "unsupported_value",
                message: "The HomeKit value cannot be represented as JSON."
            )
        }
    }

    public var foundationValue: Any {
        switch self {
        case .null:
            NSNull()
        case let .bool(value):
            value
        case let .number(value):
            value
        case let .string(value):
            value
        case let .array(value):
            value.map(\.foundationValue)
        case let .object(value):
            value.mapValues(\.foundationValue)
        }
    }
}
