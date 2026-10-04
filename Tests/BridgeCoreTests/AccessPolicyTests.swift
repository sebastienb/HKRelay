import Testing
@testable import BridgeCore

@Suite("Access policy")
struct AccessPolicyTests {
    @Test("Unknown accessories are denied")
    func unknownAccessoriesAreDenied() {
        let policy = PolicyDocument()

        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-power") == .denied)
    }

    @Test("Characteristic rules override accessory rules")
    func characteristicOverride() {
        let rule = AccessRule(
            accessoryID: "mock-accessory",
            access: .readOnly,
            characteristicOverrides: ["mock-power": .readWrite]
        )
        let policy = PolicyDocument(rules: [rule.accessoryID: rule])

        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-temperature") == .readOnly)
        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-power") == .readWrite)
    }
}
