import Foundation

public enum BearerAuthentication {
    public static func isAuthorized(headers: [String: String], token: String) -> Bool {
        guard !token.isEmpty,
              let header = headers["authorization"],
              header.prefix(7).lowercased() == "bearer " else { return false }
        let supplied = Array(header.dropFirst(7).utf8)
        let expected = Array(token.utf8)
        guard supplied.count == expected.count else { return false }
        var difference: UInt8 = 0
        for index in expected.indices { difference |= supplied[index] ^ expected[index] }
        return difference == 0
    }
}
