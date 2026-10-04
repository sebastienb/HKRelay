import BridgeCore
import Darwin
import Foundation
import Testing
@testable import BridgeServer

@Suite("HTTP server")
struct LocalHTTPServerTests {
    @Test("Serializes upstream failure status lines")
    func serializesFailureStatuses() {
        let envelope = APIEnvelope.failure(code: "motion_unavailable", message: "Motion state unavailable.")
        let badGateway = HTTPResponse.json(statusCode: 502, envelope: envelope)
        let unavailable = HTTPResponse.json(statusCode: 503, envelope: envelope)

        #expect(String(decoding: badGateway.serialized(), as: UTF8.self).hasPrefix("HTTP/1.1 502 Bad Gateway\r\n"))
        #expect(String(decoding: unavailable.serialized(), as: UTF8.self).hasPrefix("HTTP/1.1 503 Service Unavailable\r\n"))
    }

    @Test("Binds loopback mode to the loopback interface")
    func bindsLoopbackInterface() throws {
        let server = LocalHTTPServer(port: 0, binding: .loopback) { _ in
            .json(envelope: .success())
        }
        let (descriptor, _) = try server.makeListenerSocket()
        defer { Darwin.close(descriptor) }

        #expect(try boundAddress(for: descriptor) == inet_addr("127.0.0.1"))
    }

    @Test("Binds local-network mode to all IPv4 interfaces")
    func bindsAllInterfaces() throws {
        let server = LocalHTTPServer(port: 0, binding: .localNetwork) { _ in
            .json(envelope: .success())
        }
        let (descriptor, _) = try server.makeListenerSocket()
        defer { Darwin.close(descriptor) }

        #expect(try boundAddress(for: descriptor) == inet_addr("0.0.0.0"))
    }

    @Test("Stop completion runs after the listener releases its port")
    func stopReleasesPort() async throws {
        let server = LocalHTTPServer(port: 0) { _ in
            .json(envelope: .success())
        }
        let states = AsyncStream<ServerState> { continuation in
            server.start { state in continuation.yield(state) }
        }

        var iterator = states.makeAsyncIterator()
        var port: UInt16?
        while let state = await iterator.next() {
            if case let .ready(readyPort) = state {
                port = readyPort
                break
            }
            if case let .failed(message) = state {
                Issue.record("Server failed: \(message)")
                break
            }
        }

        await withCheckedContinuation { continuation in
            server.stop { continuation.resume() }
        }

        let replacement = LocalHTTPServer(port: try #require(port)) { _ in
            .json(envelope: .success())
        }
        let (descriptor, reboundPort) = try replacement.makeListenerSocket()
        defer { Darwin.close(descriptor) }

        #expect(reboundPort == port)
    }

    @Test("Serves a JSON response on an ephemeral loopback port")
    func servesJSON() async throws {
        let states = AsyncStream<ServerState> { continuation in
            let server = LocalHTTPServer(port: 0) { request in
                #expect(request.path == "/health")
                return .json(envelope: .success(.object(["status": .string("ok")])))
            }
            continuation.onTermination = { _ in server.stop() }
            server.start { state in continuation.yield(state) }
        }

        var iterator = states.makeAsyncIterator()
        var port: UInt16?
        while let state = await iterator.next() {
            if case let .ready(readyPort) = state {
                port = readyPort
                break
            }
            if case let .failed(message) = state {
                Issue.record("Server failed: \(message)")
                break
            }
        }

        let readyPort = try #require(port)
        let url = try #require(URL(string: "http://127.0.0.1:\(readyPort)/health"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        let envelope = try JSONDecoder().decode(APIEnvelope.self, from: data)

        #expect(httpResponse.statusCode == 200)
        #expect(envelope == .success(.object(["status": .string("ok")])))
    }

    @Test("Rejects an oversized declared body without calling the handler")
    func rejectsOversizedDeclaredBody() async throws {
        let states = AsyncStream<ServerState> { continuation in
            let server = LocalHTTPServer(port: 0) { _ in
                Issue.record("Oversized request reached the handler")
                return .json(envelope: .failure(code: "unexpected", message: "Unexpected handler call."))
            }
            continuation.onTermination = { _ in server.stop() }
            server.start { state in continuation.yield(state) }
        }

        var iterator = states.makeAsyncIterator()
        var port: UInt16?
        while let state = await iterator.next() {
            if case let .ready(readyPort) = state {
                port = readyPort
                break
            }
            if case let .failed(message) = state {
                Issue.record("Server failed: \(message)")
                break
            }
        }

        let readyPort = try #require(port)
        let request = "PUT /value HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(Int.max)\r\n\r\n"
        let response = try rawHTTPExchange(port: readyPort, request: request)
        let responseText = String(decoding: response, as: UTF8.self)

        #expect(responseText.hasPrefix("HTTP/1.1 413 Content Too Large\r\n"))
        #expect(responseText.contains("\"code\":\"request_too_large\""))
    }

    private func rawHTTPExchange(port: UInt16, request: String) throws -> Data {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXTestError(operation: "socket", code: errno)
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard connectResult == 0 else {
            throw POSIXTestError(operation: "connect", code: errno)
        }

        let requestData = Data(request.utf8)
        let written = requestData.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == requestData.count else {
            throw POSIXTestError(operation: "write", code: errno)
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                response.append(buffer, count: count)
            } else if count == 0 {
                return response
            } else if errno != EINTR {
                throw POSIXTestError(operation: "read", code: errno)
            }
        }
    }

    private func boundAddress(for descriptor: Int32) throws -> in_addr_t {
        var address = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &addressLength)
            }
        }
        guard result == 0 else {
            throw POSIXTestError(operation: "getsockname", code: errno)
        }
        return address.sin_addr.s_addr
    }
}

private struct POSIXTestError: Error {
    let operation: String
    let code: Int32
}
