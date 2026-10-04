import BridgeCore
import Foundation

@MainActor
final class PolicyStore {
    private static let defaultsKey = "bridge.access-policy.v1"
    private let defaults: UserDefaults
    private(set) var document: PolicyDocument

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(PolicyDocument.self, from: data) {
            document = decoded
        } else {
            document = PolicyDocument()
        }
    }

    func setAccess(_ access: AccessLevel, for accessoryID: String) throws {
        var rule = document.rules[accessoryID] ?? AccessRule(accessoryID: accessoryID)
        rule.access = access
        document.rules[accessoryID] = rule
        let data = try JSONEncoder().encode(document)
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
