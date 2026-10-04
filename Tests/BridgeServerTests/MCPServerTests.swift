import BridgeCore
import Foundation
import Testing
@testable import BridgeServer

@Suite("MCP bearer authentication and tools")
struct MCPServerTests {
    private let token = "mock-token-for-mcp-tests-only"

    private func request(_ method: String = "tools/list", params: JSONValue = .object([:]),
                         id: JSONValue? = .number(1), headers: [String: String] = [:]) throws -> HTTPRequest {
        var message: [String: JSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method), "params": params]
        if let id { message["id"] = id }
        var allHeaders = ["authorization": "Bearer \(token)", "content-type": "application/json",
                          "accept": "application/json, text/event-stream", "mcp-protocol-version": "2025-11-25"]
        allHeaders.merge(headers) { _, new in new }
        return HTTPRequest(method: "POST", path: "/mcp", headers: allHeaders,
                           body: try JSONEncoder().encode(JSONValue.object(message)))
    }

    private func object(_ response: HTTPResponse) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: response.body)
        guard case let .object(object) = value else { throw APIError(code: "test", message: "Expected object") }
        return object
    }

    private func unusedRoute(_ request: HTTPRequest) async throws -> HTTPResponse {
        Issue.record("Unauthorized or invalid request reached backend: \(request.path)")
        return .json(envelope: .success())
    }

    @Test("Authentication rejects missing, wrong, empty, and padded tokens before tool dispatch")
    func requiresToken() async throws {
        for value in ["", "Bearer wrong-token", "Basic \(token)", "Bearer \(token)\(String(repeating: "\0", count: 256))"] {
            let response = await MCPServer.handle(try request(headers: ["authorization": value]), token: token, route: unusedRoute)
            #expect(response.statusCode == 401)
            #expect(response.headers["WWW-Authenticate"] != nil)
            #expect(!String(decoding: response.body, as: UTF8.self).contains(token))
        }
        var missing = try request()
        missing.headers.removeValue(forKey: "authorization")
        #expect(await MCPServer.handle(missing, token: token, route: unusedRoute).statusCode == 401)
        #expect(await MCPServer.handle(try request(), token: "", route: unusedRoute).statusCode == 401)
    }

    @Test("Rotated tokens revoke the old credential and scheme is case insensitive")
    func tokenRotation() async throws {
        #expect(await MCPServer.handle(try request(), token: "mock-new-token", route: unusedRoute).statusCode == 401)
        let accepted = try request(headers: ["authorization": "bearer mock-new-token"])
        #expect(await MCPServer.handle(accepted, token: "mock-new-token", route: unusedRoute).statusCode == 200)
    }

    @Test("Browser origins are denied even with a valid bearer token")
    func rejectsOrigins() async throws {
        for origin in ["https://example.com", "null", "http://localhost:8765"] {
            #expect(await MCPServer.handle(try request(headers: ["origin": origin]), token: token, route: unusedRoute).statusCode == 403)
        }
    }

    @Test("Initializes and negotiates supported versions without issuing a session")
    func initialize() async throws {
        for version in MCPServer.protocolVersions + ["unknown-version"] {
            let params: JSONValue = .object(["protocolVersion": .string(version), "capabilities": .object([:]),
                                            "clientInfo": .object(["name": .string("mock-client"), "version": .string("1")])])
            let response = await MCPServer.handle(try request("initialize", params: params, id: .string("init")), token: token, route: unusedRoute)
            let envelope = try object(response)
            #expect(envelope["id"] == .string("init"))
            guard case let .object(result) = envelope["result"] else { Issue.record("Missing result"); return }
            #expect(result["protocolVersion"] == .string(MCPServer.protocolVersions.contains(version) ? version : "2025-11-25"))
            #expect(response.headers["MCP-Session-Id"] == nil)
        }
    }

    @Test("Lists six tools with restrictive write schema and annotations")
    func listsTools() async throws {
        let response = await MCPServer.handle(try request(), token: token, route: unusedRoute)
        guard case let .object(result) = try object(response)["result"], case let .array(tools) = result["tools"] else {
            Issue.record("Missing tools"); return
        }
        #expect(tools.count == 6)
        guard case let .object(write) = tools.last,
              case let .object(schema) = write["inputSchema"], case let .object(properties) = schema["properties"] else {
            Issue.record("Missing write schema"); return
        }
        #expect(schema["additionalProperties"] == .bool(false))
        #expect(properties["confirm"] == .object(["type": .string("boolean"), "const": .bool(true)]))
        #expect(write["annotations"] == .object(["readOnlyHint": .bool(false), "destructiveHint": .bool(true),
                                                "idempotentHint": .bool(false), "openWorldHint": .bool(false)]))
    }

    @Test("Read tools dispatch to the existing REST routes")
    func readRoutes() async throws {
        let examples: [(String, [String: JSONValue], String)] = [
            ("homekit_status", [:], "/v1/status"),
            ("homekit_list_accessories", [:], "/v1/accessories"),
            ("homekit_get_accessory", ["accessoryID": .string("mock-accessory")], "/v1/accessories/mock-accessory"),
            ("homekit_read_characteristic", ["accessoryID": .string("mock-accessory"), "characteristicID": .string("mock-value")], "/v1/accessories/mock-accessory/characteristics/mock-value"),
            ("homekit_camera_motion", ["accessoryID": .string("mock-camera")], "/v1/accessories/mock-camera/camera/motion")
        ]
        for (name, args, expectedPath) in examples {
            let response = await MCPServer.handle(try request("tools/call", params: .object(["name": .string(name), "arguments": .object(args)])), token: token) { rest in
                #expect(rest.method == "GET")
                #expect(rest.path == expectedPath)
                return .json(envelope: .success(.object(["mock": .bool(true)])))
            }
            guard case let .object(result) = try object(response)["result"] else { Issue.record("Missing result"); return }
            #expect(result["isError"] == .bool(false))
        }
    }

    @Test("Discovery and detail omit bulky values but preserve rooms, permissions and control IDs")
    func compactAccessoryResponses() async throws {
        let characteristic: JSONValue = .object([
            "id": .string("mock-power"), "name": .string("Power"), "type": .string("mock-power-type"),
            "access": .string("read-write"), "readable": .bool(true), "writable": .bool(true),
            "value": .string(String(repeating: "x", count: 20_000))
        ])
        let accessory: JSONValue = .object([
            "id": .string("mock-light"), "name": .string("Mock Lamp"), "room": .string("Test Room"),
            "category": .string("Outlet"), "access": .string("read-write"), "reachable": .bool(true),
            "manufacturer": .string("mock-vendor"),
            "services": .array([.object(["characteristics": .array([characteristic])])])
        ])
        for name in ["homekit_list_accessories", "homekit_get_accessory"] {
            let args: JSONValue = name == "homekit_get_accessory" ? .object(["accessoryID": .string("mock-light")]) : .object([:])
            let response = await MCPServer.handle(try request("tools/call", params: .object(["name": .string(name), "arguments": args])), token: token) { _ in
                .json(envelope: .success(name == "homekit_list_accessories" ? .array([accessory]) : accessory))
            }
            guard case let .object(result) = try object(response)["result"],
                  case let .array(content) = result["content"], case let .object(block) = content.first,
                  case let .string(text) = block["text"] else { Issue.record("Missing content"); return }
            #expect(text.utf8.count < 1_000)
            let data = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            let fields: [String: JSONValue]
            if case let .array(items) = data, case let .object(object) = items.first { fields = object }
            else if case let .object(object) = data { fields = object }
            else { Issue.record("Missing accessory"); return }
            #expect(fields["room"] == .string("Test Room"))
            #expect(fields["access"] == .string("read-write"))
            #expect(fields["services"] == nil)
            #expect(fields["manufacturer"] == nil)
            if name == "homekit_get_accessory" {
                guard case let .array(items) = fields["characteristics"], case let .object(power) = items.first else {
                    Issue.record("Missing characteristics"); return
                }
                #expect(power["id"] == .string("mock-power"))
                #expect(power["writable"] == .bool(true))
                #expect(power["value"] == nil)
            } else { #expect(fields["characteristics"] == nil) }
        }
    }

    @Test("Write confirmation, required arguments, and path injection are checked before dispatch")
    func rejectsInvalidWrites() async throws {
        let valid: [String: JSONValue] = ["accessoryID": .string("mock-accessory"), "characteristicID": .string("mock-value"), "value": .bool(true), "confirm": .bool(true)]
        var variants = [[String: JSONValue]]()
        for field in valid.keys { var args = valid; args.removeValue(forKey: field); variants.append(args) }
        for invalid in [JSONValue.bool(false), .string("true"), .null] { var args = valid; args["confirm"] = invalid; variants.append(args) }
        for invalid in ["../status", "mock%2Fvalue", "mock/value", "mock?query", ""] { var args = valid; args["accessoryID"] = .string(invalid); variants.append(args) }
        var extra = valid; extra["permission"] = .string("read-write"); variants.append(extra)
        for args in variants {
            let response = await MCPServer.handle(try request("tools/call", params: .object(["name": .string("homekit_write_characteristic"), "arguments": .object(args)])), token: token, route: unusedRoute)
            guard case let .object(error) = try object(response)["error"] else { Issue.record("Expected parameter error"); return }
            #expect(error["code"] == .number(-32602))
        }
    }

    @Test("Confirmed writes use the permission-enforcing route and preserve denial as a tool error")
    func writeDenied() async throws {
        let params: JSONValue = .object(["name": .string("homekit_write_characteristic"), "arguments": .object([
            "accessoryID": .string("mock-accessory"), "characteristicID": .string("mock-value"), "value": .bool(true), "confirm": .bool(true)])])
        let response = await MCPServer.handle(try request("tools/call", params: params), token: token) { rest in
            #expect(rest.method == "PUT")
            #expect(rest.path == "/v1/accessories/mock-accessory/characteristics/mock-value")
            let body = try JSONDecoder().decode(JSONValue.self, from: rest.body)
            #expect(body == .object(["value": .bool(true)]))
            return .json(statusCode: 403, envelope: .failure(code: "write_denied", message: "Write access is disabled."))
        }
        guard case let .object(result) = try object(response)["result"] else { Issue.record("Missing result"); return }
        #expect(result["isError"] == .bool(true))
        #expect(String(decoding: response.body, as: UTF8.self).contains("write_denied"))
    }

    @Test("Notifications never execute tools and initialized returns an empty 202")
    func notifications() async throws {
        let accepted = await MCPServer.handle(try request("notifications/initialized", id: nil), token: token, route: unusedRoute)
        #expect(accepted.statusCode == 202)
        #expect(accepted.body.isEmpty)
        #expect(await MCPServer.handle(try request("tools/call", id: nil), token: token, route: unusedRoute).statusCode == 400)
    }

    @Test("Transport rejects unsupported methods, media types, and protocol versions")
    func transportValidation() async throws {
        for method in ["GET", "DELETE", "PUT", "OPTIONS"] {
            var value = try request(); value.method = method
            let response = await MCPServer.handle(value, token: token, route: unusedRoute)
            #expect(response.statusCode == 405)
            #expect(response.headers["Allow"] == "POST")
        }
        #expect(await MCPServer.handle(try request(headers: ["content-type": "text/plain"]), token: token, route: unusedRoute).statusCode == 415)
        #expect(await MCPServer.handle(try request(headers: ["accept": "application/json"]), token: token, route: unusedRoute).statusCode == 406)
        #expect(await MCPServer.handle(try request(headers: ["mcp-protocol-version": "unsupported"]), token: token, route: unusedRoute).statusCode == 400)
        var legacy = try request(); legacy.headers.removeValue(forKey: "mcp-protocol-version")
        #expect(await MCPServer.handle(legacy, token: token, route: unusedRoute).statusCode == 200)
    }

    @Test("Malformed JSON, batches, and invalid message IDs never reach the backend")
    func malformedMessages() async throws {
        for body in ["{", "[]", "{\"jsonrpc\":\"1.0\",\"method\":\"tools/list\",\"id\":1}", "{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\",\"id\":null}"] {
            var value = try request(); value.body = Data(body.utf8)
            #expect(await MCPServer.handle(value, token: token, route: unusedRoute).statusCode == 400)
        }
        let response = await MCPServer.handle(try request("unknown-method"), token: token, route: unusedRoute)
        guard case let .object(error) = try object(response)["error"] else { Issue.record("Missing error"); return }
        #expect(error["code"] == .number(-32601))
    }

    @Test("Serves authenticated MCP calls over the real loopback HTTP transport")
    func loopbackTransport() async throws {
        let expectedToken = token
        let server = LocalHTTPServer(port: 0) { request in
            await MCPServer.handle(request, token: expectedToken) { rest in
                #expect(rest.path == "/v1/status")
                return .json(envelope: .success(.object(["mock": .bool(true)])))
            }
        }
        let states = AsyncStream<ServerState> { continuation in
            server.start { continuation.yield($0) }
        }
        defer { server.stop() }
        var port: UInt16?
        for await state in states {
            if case let .ready(value) = state { port = value; break }
            if case let .failed(message) = state { Issue.record("Server failed: \(message)"); break }
        }
        let readyPort = try #require(port)
        let url = try #require(URL(string: "http://127.0.0.1:\(readyPort)/mcp"))
        let call = try request("tools/call", params: .object(["name": .string("homekit_status")]))
        var networkRequest = URLRequest(url: url)
        networkRequest.httpMethod = "POST"
        networkRequest.httpBody = call.body
        networkRequest.timeoutInterval = 5
        for (key, value) in call.headers { networkRequest.setValue(value, forHTTPHeaderField: key) }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: networkRequest)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        guard case let .object(envelope) = try JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(result) = envelope["result"] else { Issue.record("Missing tool result"); return }
        #expect(result["isError"] == .bool(false))
        networkRequest.setValue(nil, forHTTPHeaderField: "authorization")
        let (_, denied) = try await session.data(for: networkRequest)
        #expect((denied as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test("Parser rejects duplicated security headers")
    func duplicateHeaders() {
        for name in ["Authorization", "Origin", "MCP-Protocol-Version"] {
            let data = Data("POST /mcp HTTP/1.1\r\n\(name): first\r\n\(name): second\r\n\r\n".utf8)
            #expect(throws: HTTPParseError.invalidHeaders) { try HTTPParser.parse(data) }
        }
    }
}
