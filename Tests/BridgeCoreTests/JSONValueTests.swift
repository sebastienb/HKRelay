import Foundation
import Testing
@testable import BridgeCore

@Suite("JSON values")
struct JSONValueTests {
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
