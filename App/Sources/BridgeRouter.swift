import BridgeCore
import BridgeServer
import Foundation

@MainActor
final class BridgeRouter {
    private let homeKit: HomeKitRepository
    private let history: RequestHistoryStore
    private var token: String
    private var loopbackOnly: Bool

    init(
        homeKit: HomeKitRepository,
        token: String,
        loopbackOnly: Bool,
        history: RequestHistoryStore
    ) {
        self.homeKit = homeKit
        self.token = token
        self.loopbackOnly = loopbackOnly
        self.history = history
    }

    func replaceToken(_ token: String) {
        self.token = token
    }

    func setLoopbackOnly(_ loopbackOnly: Bool) {
        self.loopbackOnly = loopbackOnly
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let startedAt = Date()
        let response = await response(for: request)
        history.record(
            request: request,
            response: response,
            duration: Date().timeIntervalSince(startedAt)
        )
        return response
    }

    private func response(for request: HTTPRequest) async -> HTTPResponse {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path

        if path == "/mcp" {
            return await MCPServer.handle(request, token: token) { [self] toolRequest in
                try await self.route(toolRequest)
            }
        }

        guard request.headers["origin"] == nil else {
            return .json(statusCode: 403, envelope: .failure(code: "origin_denied", message: "Browser origins are not allowed."))
        }

        if request.method == "GET",
           path == "/health" || path == RequestHistoryStore.menuBarHealthPath {
            return .json(envelope: .success(.object(["status": .string("ok")])))
        }

        guard isAuthorized(request) else {
            return .json(
                statusCode: 401,
                envelope: .failure(code: "unauthorized", message: "A valid bearer token is required.")
            )
        }

        do {
            return try await route(request)
        } catch let error as APIError {
            let statusCode: Int
            switch error.code {
            case "not_found", "camera_unsupported", "motion_unsupported": statusCode = 404
            case "access_denied", "read_denied", "write_denied": statusCode = 403
            case "motion_unavailable": statusCode = 503
            default: statusCode = 400
            }
            return .json(statusCode: statusCode, envelope: .failure(code: error.code, message: error.message))
        } catch {
            return .json(
                statusCode: 500,
                envelope: .failure(code: "internal_error", message: "The bridge could not complete the request.")
            )
        }
    }

    private func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }

        if request.method == "GET", components == ["v1", "status"] {
            let status = BridgeStatus(
                version: "0.1.0",
                homeKitAuthorized: homeKit.isAuthorized,
                homeDataLoaded: homeKit.homeDataLoaded,
                loopbackOnly: loopbackOnly,
                authenticationRequired: true
            )
            return .json(envelope: .success(try jsonValue(status)))
        }

        if request.method == "GET", components == ["v1", "accessories"] {
            return .json(envelope: .success(try jsonValue(homeKit.permittedAccessories())))
        }

        if request.method == "GET", components.count == 3,
           components[0] == "v1", components[1] == "accessories" {
            return .json(envelope: .success(try jsonValue(homeKit.permittedAccessory(id: components[2]))))
        }

        if request.method == "GET", components.count == 5,
           components[0] == "v1", components[1] == "accessories",
           components[3] == "camera", components[4] == "motion" {
            let readings = try await homeKit.readCameraMotion(accessoryID: components[2])
            return .json(envelope: .success(try jsonValue(readings)))
        }

        if components.count == 5,
           components[0] == "v1", components[1] == "accessories",
           components[3] == "characteristics" {
            let accessoryID = components[2]
            let characteristicID = components[4]

            if request.method == "GET" {
                let value = try await homeKit.read(
                    accessoryID: accessoryID,
                    characteristicID: characteristicID
                )
                return .json(envelope: .success(try jsonValue(value)))
            }

            if request.method == "PUT" {
                let body = try JSONDecoder().decode(JSONValue.self, from: request.body)
                guard case let .object(object) = body, let value = object["value"] else {
                    throw APIError(code: "invalid_body", message: "Expected a JSON object containing 'value'.")
                }
                let result = try await homeKit.write(
                    accessoryID: accessoryID,
                    characteristicID: characteristicID,
                    value: value
                )
                return .json(envelope: .success(try jsonValue(result)))
            }

            return .json(
                statusCode: 405,
                envelope: .failure(code: "method_not_allowed", message: "This method is not supported.")
            )
        }

        return .json(
            statusCode: 404,
            envelope: .failure(code: "not_found", message: "Endpoint not found.")
        )
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        BearerAuthentication.isAuthorized(headers: request.headers, token: token)
    }

    private func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
