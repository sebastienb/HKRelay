import BridgeCore
import Darwin
import Foundation

@main
struct HKRelayCLI {
    private static let version = "0.1.0"

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        do {
            let result = try await run(arguments: arguments)
            FileHandle.standardOutput.write(result)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch let failure as HTTPFailure {
            FileHandle.standardOutput.write(failure.body)
            FileHandle.standardOutput.write(Data("\n".utf8))
            Foundation.exit(Int32(failure.statusCode == 401 ? 3 : 1))
        } catch let error as CLIError {
            writeFailure(code: error.code, message: error.message)
            Foundation.exit(2)
        } catch {
            writeFailure(code: "internal_error", message: error.localizedDescription)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws -> Data {
        if arguments.isEmpty || arguments == ["help"] || arguments == ["--help"] {
            return try encoded(.success(.object([
                "name": .string("hkrelay"),
                "version": .string(version),
                "commands": .array(helpCommands.map(JSONValue.string))
            ])))
        }

        if arguments == ["version"] || arguments == ["--version"] {
            return try encoded(.success(.object(["version": .string(version)])))
        }

        if arguments.starts(with: ["config", "set-token"]) {
            guard arguments.count == 2 else {
                throw CLIError(
                    code: "invalid_arguments",
                    message: "Usage: printf '%s' TOKEN | hkrelay config set-token"
                )
            }

            let token = try readToken()

            try CredentialStore().saveToken(token)
            return try encoded(.success(.object(["configured": .bool(true)])))
        }

        let baseURL = URL(string: "http://127.0.0.1:8765")!
        let client = BridgeClient(baseURL: baseURL, token: try CredentialStore().loadToken())

        if arguments == ["status"] {
            return try await client.get(path: "/v1/status")
        }

        if arguments == ["accessories", "list"] {
            return try await client.get(path: "/v1/accessories")
        }

        if arguments.count == 3, arguments[0] == "accessories", arguments[1] == "get" {
            let accessoryID = arguments[2]
            return try await client.get(path: "/v1/accessories/\(escaped(accessoryID))")
        }

        if arguments.count == 3, arguments.starts(with: ["camera", "motion"]) {
            return try await client.get(path: "/v1/accessories/\(escaped(arguments[2]))/camera/motion")
        }

        if arguments.count == 3, arguments[0] == "read" {
            let accessoryID = arguments[1]
            let characteristicID = arguments[2]
            return try await client.get(
                path: "/v1/accessories/\(escaped(accessoryID))/characteristics/\(escaped(characteristicID))"
            )
        }

        if arguments.count == 5, arguments[0] == "write", arguments[4] == "--yes" {
            let accessoryID = arguments[1]
            let characteristicID = arguments[2]
            let rawValue = arguments[3]
            let value = try parseJSONValue(rawValue)
            return try await client.put(
                path: "/v1/accessories/\(escaped(accessoryID))/characteristics/\(escaped(characteristicID))",
                body: .object(["value": value])
            )
        }

        if arguments.count == 4, arguments[0] == "write" {
            throw CLIError(
                code: "confirmation_required",
                message: "Add --yes to confirm a HomeKit write."
            )
        }

        throw CLIError(code: "unknown_command", message: "Run 'hkrelay help' for valid commands.")
    }

    private static let helpCommands = [
        "hkrelay status",
        "hkrelay accessories list",
        "hkrelay accessories get ACCESSORY_ID",
        "hkrelay read ACCESSORY_ID CHARACTERISTIC_ID",
        "hkrelay camera motion ACCESSORY_ID",
        "hkrelay write ACCESSORY_ID CHARACTERISTIC_ID JSON_VALUE --yes",
        "hkrelay config set-token"
    ]

    private static func readToken() throws -> String {
        if isatty(STDIN_FILENO) == 1 {
            guard let pointer = getpass("Bridge token: ") else {
                throw CLIError(code: "invalid_token", message: "Could not read the token.")
            }
            return String(cString: pointer)
        }

        let tokenData = FileHandle.standardInput.readDataToEndOfFile()
        guard let token = String(data: tokenData, encoding: .utf8) else {
            throw CLIError(code: "invalid_token", message: "The token must be UTF-8 text.")
        }
        return token
    }

    private static func parseJSONValue(_ rawValue: String) throws -> JSONValue {
        guard let data = rawValue.data(using: .utf8) else {
            throw CLIError(code: "invalid_value", message: "The value must be UTF-8 JSON.")
        }

        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw CLIError(
                code: "invalid_value",
                message: "The value must be valid JSON, such as true, 42, or \"on\"."
            )
        }
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func encoded(_ envelope: APIEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    private static func writeFailure(code: String, message: String) {
        let envelope = APIEnvelope.failure(code: code, message: message)
        let data = (try? encoded(envelope)) ?? Data("{\"ok\":false}".utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
