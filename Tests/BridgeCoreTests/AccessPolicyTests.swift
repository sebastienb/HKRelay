import Testing
@testable import BridgeCore

@Suite("Access policy")
struct AccessPolicyTests {
    @Test("Unknown accessories are denied")
    func unknownAccessoriesAreDenied() {
        let policy = PolicyDocument()

        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-power") == .denied)
    }

    @Test("Denying an accessory defeats every saved override")
    func deniedParent() {
        for override in AccessLevel.allCases {
            let rule = AccessRule(accessoryID: "mock-accessory", access: .denied,
                                  characteristicOverrides: ["mock-power": override])
            #expect(rule.effectiveAccess(for: "mock-power") == .denied)
        }
    }

    @Test("A characteristic can narrow an allowed accessory")
    func restrictedChild() {
        let rule = AccessRule(accessoryID: "mock-accessory", access: .readWrite,
                              characteristicOverrides: ["mock-power": .denied, "mock-state": .readOnly])
        #expect(rule.effectiveAccess(for: "mock-power") == .denied)
        #expect(rule.effectiveAccess(for: "mock-state") == .readOnly)
        #expect(rule.effectiveAccess(for: "mock-other") == .readWrite)
    }

    @Test("Characteristic rules cannot widen accessory access")
    func characteristicOverride() {
        let rule = AccessRule(
            accessoryID: "mock-accessory",
            access: .readOnly,
            characteristicOverrides: ["mock-power": .readWrite]
        )
        let policy = PolicyDocument(rules: [rule.accessoryID: rule])

        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-temperature") == .readOnly)
        #expect(policy.access(for: "mock-accessory", characteristicID: "mock-power") == .readOnly)
    }
}
