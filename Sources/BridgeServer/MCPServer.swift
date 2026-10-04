import BridgeCore
import Foundation

/// Stateless Streamable HTTP with preconfigured bearer authentication.
/// No sessions, browser origins, OAuth discovery, or server-initiated messages.
public enum MCPServer {
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public typealias Route = @Sendable (HTTPRequest) async throws -> HTTPResponse

    public static func handle(_ request: HTTPRequest, token: String, route: Route) async -> HTTPResponse {
        // Native clients do not send Origin. Browser access is deliberately denied.
        guard request.headers["origin"] == nil else {
            return error(id: .null, code: -32000, message: "Browser origins are not allowed.", status: 403)
        }
        guard BearerAuthentication.isAuthorized(headers: request.headers, token: token) else {
            var response = error(id: .null, code: -32000, message: "A valid bearer token is required.", status: 401)
            response.headers["WWW-Authenticate"] = "Bearer realm=\"HomeKitLink\""
            return response
        }
        if let version = request.headers["mcp-protocol-version"], !protocolVersions.contains(version) {
            return error(id: .null, code: -32600, message: "Unsupported MCP protocol version.", status: 400)
        }
        guard request.method == "POST" else {
            var response = HTTPResponse.empty(statusCode: 405)
            response.headers["Allow"] = "POST"
            return response
        }
        let mediaType = request.headers["content-type"]?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard mediaType == "application/json" else {
            return error(id: .null, code: -32600, message: "Content-Type must be application/json.", status: 415)
        }
        let accepted = (request.headers["accept"] ?? "").split(separator: ",").map {
            $0.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        }
        guard accepted.contains("application/json"), accepted.contains("text/event-stream") else {
            return error(id: .null, code: -32600, message: "Accept must include application/json and text/event-stream.", status: 406)
        }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: request.body) }
        catch { return Self.error(id: .null, code: -32700, message: "Invalid JSON.", status: 400) }
        guard case let .object(message) = value, message["jsonrpc"] == .string("2.0"),
              case let .string(method) = message["method"],
              message["result"] == nil, message["error"] == nil else {
            return error(id: .null, code: -32600, message: "Expected one JSON-RPC 2.0 message.", status: 400)
        }
        if let id = message["id"] {
            switch id {
            case .string: break
            case let .number(number) where number.isFinite && number.rounded() == number: break
            default: return error(id: .null, code: -32600, message: "Invalid request ID.", status: 400)
            }
        }
        let id = message["id"] ?? .null
        let params: [String: JSONValue]
        if let value = message["params"] {
            guard case let .object(object) = value else {
                return error(id: id, code: -32602, message: "Parameters must be an object.", status: 400)
            }
            params = object
        } else { params = [:] }
        // Never execute tool calls supplied as notifications.
        guard message["id"] != nil else {
            guard ["notifications/initialized", "notifications/cancelled"].contains(method) else {
                return error(id: .null, code: -32600, message: "Unsupported notification.", status: 400)
            }
            return .empty(statusCode: 202)
        }
        switch method {
        case "initialize":
            guard case let .string(version) = params["protocolVersion"],
                  case .object = params["capabilities"],
                  case let .object(info) = params["clientInfo"],
                  case .string = info["name"], case .string = info["version"] else {
                return error(id: id, code: -32602, message: "Invalid initialization parameters.")
            }
            return result(id: id, value: .object([
                "protocolVersion": .string(protocolVersions.contains(version) ? version : protocolVersions[0]),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("homekitlink"), "version": .string("0.1.0")]),
                "instructions": .string("Only accessories allowed in the Mac app are exposed. Ask the user before operating devices. Writes require confirm=true and read-write permission.")
            ]))
        case "ping": return result(id: id, value: .object([:]))
        case "tools/list":
            guard params["cursor"] == nil else {
                return error(id: id, code: -32602, message: "Pagination is not supported.")
            }
            return result(id: id, value: .object(["tools": .array(tools)]))
        case "tools/call":
            do {
                let restRequest = try toolRequest(params)
                let response = try await route(restRequest)
                let envelope = try JSONDecoder().decode(APIEnvelope.self, from: response.body)
                if envelope.ok, (200..<300).contains(response.statusCode) {
                    return result(id: id, value: toolResult(compactData(envelope.data ?? .null, tool: params["name"]), isError: false))
                }
                let failure = envelope.error ?? APIError(code: "bridge_error", message: "The bridge could not complete the request.")
                return result(id: id, value: toolResult(.object([
                    "code": .string(failure.code), "message": .string(failure.message)
                ]), isError: true))
            } catch let failure as ParameterError {
                return error(id: id, code: -32602, message: failure.message)
            } catch let failure as APIError {
                return result(id: id, value: toolResult(.object([
                    "code": .string(failure.code), "message": .string(failure.message)
                ]), isError: true))
            } catch {
                return result(id: id, value: toolResult(.object([
                    "code": .string("internal_error"), "message": .string("The bridge could not complete the request.")
                ]), isError: true))
            }
        default: return error(id: id, code: -32601, message: "Method not found.")
        }
    }

    private static func result(id: JSONValue, value: JSONValue) -> HTTPResponse {
        .jsonValue(value: .object(["jsonrpc": .string("2.0"), "id": id, "result": value]))
    }

    private static func error(id: JSONValue, code: Int, message: String, status: Int = 200) -> HTTPResponse {
        .jsonValue(statusCode: status, value: .object([
            "jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(message)])
        ]))
    }

    /// Discovery stays small; detail exposes characteristic IDs without cached values or metadata.
    private static func compactData(_ value: JSONValue, tool: JSONValue?) -> JSONValue {
        let summaryKeys: Set<String> = ["id", "name", "room", "category", "access", "reachable"]
        func summary(_ fields: [String: JSONValue]) -> [String: JSONValue] {
            fields.filter { summaryKeys.contains($0.key) }
        }
        if tool == .string("homekit_list_accessories"), case let .array(items) = value {
            return .array(items.map { item in
                guard case let .object(fields) = item else { return item }
                return .object(summary(fields))
            })
        }
        if tool == .string("homekit_get_accessory"), case let .object(fields) = value {
            var output = summary(fields)
            if let camera = fields["camera"] { output["camera"] = camera }
            if case let .array(services) = fields["services"] {
                let keys: Set<String> = ["id", "name", "type", "readable", "writable", "access"]
                output["characteristics"] = .array(services.flatMap { service -> [JSONValue] in
                    guard case let .object(object) = service,
                          case let .array(characteristics) = object["characteristics"] else { return [] }
                    return characteristics.map { characteristic in
                        guard case let .object(object) = characteristic else { return characteristic }
                        return .object(object.filter { keys.contains($0.key) })
                    }
                })
            }
            return .object(output)
        }
        return value
    }

    private static func toolResult(_ value: JSONValue, isError: Bool) -> JSONValue {
        let text = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError)
        ])
    }

    private struct ParameterError: Error { let message: String }

    private static func toolRequest(_ params: [String: JSONValue]) throws -> HTTPRequest {
        guard case let .string(name) = params["name"], let tool = definitions.first(where: { $0.name == name }) else {
            throw ParameterError(message: "Unknown tool name.")
        }
        let arguments: [String: JSONValue]
        if let value = params["arguments"] {
            guard case let .object(object) = value else { throw ParameterError(message: "Arguments must be an object.") }
            arguments = object
        } else { arguments = [:] }
        guard Set(arguments.keys) == Set(tool.fields) else {
            throw ParameterError(message: "Provide exactly the arguments listed in the tool schema.")
        }
        func identifier(_ field: String) throws -> String {
            guard case let .string(value) = arguments[field], !value.isEmpty, value.utf8.count <= 128,
                  value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
                throw ParameterError(message: "Invalid \(field). Use an ID returned by the bridge.")
            }
            return value
        }
        switch name {
        case "homekit_status": return HTTPRequest(method: "GET", path: "/v1/status")
        case "homekit_list_accessories": return HTTPRequest(method: "GET", path: "/v1/accessories")
        case "homekit_get_accessory":
            return HTTPRequest(method: "GET", path: "/v1/accessories/\(try identifier("accessoryID"))")
        case "homekit_camera_motion":
            return HTTPRequest(method: "GET", path: "/v1/accessories/\(try identifier("accessoryID"))/camera/motion")
        default:
            let path = "/v1/accessories/\(try identifier("accessoryID"))/characteristics/\(try identifier("characteristicID"))"
            if name == "homekit_read_characteristic" { return HTTPRequest(method: "GET", path: path) }
            guard arguments["confirm"] == .bool(true) else {
                throw ParameterError(message: "Writes require confirm=true after user approval.")
            }
            return HTTPRequest(method: "PUT", path: path,
                               body: try JSONEncoder().encode(JSONValue.object(["value": arguments["value"]!])))
        }
    }

    private struct Definition {
        let name: String
        let description: String
        let fields: [String]
        var write: Bool { name == "homekit_write_characteristic" }
    }
    private static let definitions = [
        Definition(name: "homekit_status", description: "Read bridge and HomeKit availability.", fields: []),
        Definition(name: "homekit_list_accessories", description: "List permitted accessories with IDs, names, rooms, categories, access and reachability. Lights may be outlets. Use homekit_get_accessory for characteristic IDs.", fields: []),
        Definition(name: "homekit_get_accessory", description: "Get a permitted accessory and compact characteristics with IDs, types and permissions. Use homekit_read_characteristic for current values.", fields: ["accessoryID"]),
        Definition(name: "homekit_read_characteristic", description: "Read a fresh permitted HomeKit characteristic value.", fields: ["accessoryID", "characteristicID"]),
        Definition(name: "homekit_camera_motion", description: "Read motion sensors on a permitted camera. No images or video.", fields: ["accessoryID"]),
        Definition(name: "homekit_write_characteristic", description: "Operate a physical device. Ask the user first, then pass confirm=true. Requires read-write permission in the Mac app.", fields: ["accessoryID", "characteristicID", "value", "confirm"])
    ]
    private static var tools: [JSONValue] {
        definitions.map { tool in
            var properties: [String: JSONValue] = [:]
            for field in tool.fields {
                switch field {
                case "value": properties[field] = .object(["description": .string("The JSON value to write.")])
                case "confirm": properties[field] = .object(["type": .string("boolean"), "const": .bool(true)])
                default: properties[field] = .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(128), "pattern": .string("^[A-Za-z0-9_-]+$")])
                }
            }
            return .object([
                "name": .string(tool.name), "description": .string(tool.description),
                "inputSchema": .object(["type": .string("object"), "properties": .object(properties),
                                        "required": .array(tool.fields.map(JSONValue.string)), "additionalProperties": .bool(false)]),
                "annotations": .object(["readOnlyHint": .bool(!tool.write), "destructiveHint": .bool(tool.write),
                                         "idempotentHint": .bool(!tool.write), "openWorldHint": .bool(false)])
            ])
        }
    }
}
