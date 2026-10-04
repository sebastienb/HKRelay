import BridgeCore
import Foundation

struct BridgeClient {
    let baseURL: URL
    let token: String?

    func get(path: String) async throws -> Data {
        try await request(path: path, method: "GET")
    }

    func put(path: String, body: JSONValue) async throws -> Data {
        let payload = try JSONEncoder().encode(body)
        return try await request(path: path, method: "PUT", body: payload)
    }

    private func request(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CLIError(code: "invalid_url", message: "The bridge URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("hkrelay-cli/0.1.0", forHTTPHeaderField: "User-Agent")

        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CLIError(code: "invalid_response", message: "The bridge returned an invalid response.")
            }

            guard JSONSerialization.isValidJSONObject(
                (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
            ) else {
                throw CLIError(code: "invalid_json", message: "The bridge returned invalid JSON.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw HTTPFailure(statusCode: httpResponse.statusCode, body: data)
            }

            return data
        } catch let error as CLIError {
            throw error
        } catch let error as HTTPFailure {
            throw error
        } catch {
            throw CLIError(
                code: "bridge_unavailable",
                message: "Could not reach the bridge on this Mac: \(error.localizedDescription)"
            )
        }
    }
}

struct HTTPFailure: Error {
    let statusCode: Int
    let body: Data
}

struct CLIError: Error {
    let code: String
    let message: String
}
