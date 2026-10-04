import Foundation
import Testing
@testable import BridgeCore

@Suite("JSON values")
struct JSONValueTests {
    @Test("Foundation numbers zero and one remain numeric")
    func foundationNumbers() throws {
        for value in [0.0, 1.0, 2.0, 21.5] {
            #expect(try JSONValue(any: NSNumber(value: value)) == .number(value))
        }
        #expect(try JSONValue(any: NSNumber(value: false)) == .bool(false))
        #expect(try JSONValue(any: NSNumber(value: true)) == .bool(true))
        #expect(try JSONValue(any: 1) == .number(1))
    }

    @Test("Values round-trip through Codable")
    func roundTrip() throws {
        let original = JSONValue.object([
            "enabled": .bool(true),
            "level": .number(42),
            "name": .string("Mock Lamp"),
            "tags": .array([.string("test")]),
            "optional": .null
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(decoded == original)
    }
}
