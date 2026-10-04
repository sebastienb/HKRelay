import BridgeCore
import Darwin
import Foundation
import Testing
@testable import BridgeServer

@Suite("Server resource and shutdown boundaries")
struct ServerHardeningTests {
    @Test("Stop closes an accepted socket while its handler is still pending")
    func stopClosesPendingHandler() async throws {
        let gate = HandlerGate()
        let server = LocalHTTPServer(port: 0) { _ in
            await gate.wait()
            return .json(envelope: .success())
        }
        let port = try await start(server)
        let descriptor = try connect(port)
        defer { Darwin.close(descriptor) }
        try sendRequest(descriptor)
        await gate.waitUntilEntered()
        await withCheckedContinuation { continuation in server.stop { continuation.resume() } }
        #expect(peerClosed(descriptor))
        await gate.release()
    }

    @Test("The connection cap includes timed-out, cancellation-resistant handlers")
    func boundedPendingHandlers() async throws {
        let gate = HandlerGate()
        let server = LocalHTTPServer(port: 0, maximumConnections: 1, requestTimeout: 0.2) { _ in
            await gate.wait()
            return .json(envelope: .success())
        }
        let port = try await start(server)
        defer { server.stop() }
        let first = try connect(port)
        defer { Darwin.close(first) }
        try sendRequest(first)
        await gate.waitUntilEntered()
        // The absolute handler deadline closes the peer even though cancellation is ignored.
        #expect(peerClosed(first))
        let second = try connect(port)
        defer { Darwin.close(second) }
        #expect(peerClosed(second))
        await gate.release()
    }

    @Test("An incomplete request expires and frees its connection slot")
    func incompleteRequestDeadline() async throws {
        let server = LocalHTTPServer(port: 0, maximumConnections: 1, requestTimeout: 0.2) { _ in
            .json(envelope: .success())
        }
        let port = try await start(server)
        defer { server.stop() }
        let idle = try connect(port)
        defer { Darwin.close(idle) }
        #expect(peerClosed(idle))
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("A client that does not read its response does not block other requests")
    func slowResponseReader() async throws {
        let server = LocalHTTPServer(port: 0, requestTimeout: 2) { request in
            if request.path == "/large" {
                return .json(envelope: .success(.string(String(repeating: "x", count: 4_000_000))))
            }
            return .json(envelope: .success())
        }
        let port = try await start(server)
        defer { server.stop() }
        let slow = try connect(port)
        defer { Darwin.close(slow) }
        var bufferSize: Int32 = 1_024
        _ = setsockopt(slow, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        let bytes = Data("GET /large HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(slow, $0.baseAddress, $0.count) }
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    private func start(_ server: LocalHTTPServer) async throws -> UInt16 {
        let states = AsyncStream<ServerState> { continuation in
            server.start { continuation.yield($0) }
        }
        for await state in states {
            if case let .ready(port) = state { return port }
            if case let .failed(message) = state { throw APIError(code: "start_failed", message: message) }
        }
        throw APIError(code: "start_failed", message: "No server state")
    }

    private func connect(_ port: UInt16) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw APIError(code: "socket", message: "Socket creation failed") }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw APIError(code: "connect", message: "Connection failed")
        }
        return descriptor
    }

    private func sendRequest(_ descriptor: Int32) throws {
        let bytes = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == bytes.count else { throw APIError(code: "write", message: "Request write failed") }
    }

    private func peerClosed(_ descriptor: Int32) -> Bool {
        var byte: UInt8 = 0
        let count = Darwin.read(descriptor, &byte, 1)
        return count == 0 || count == -1 && errno == ECONNRESET
    }
}

private actor HandlerGate {
    private var entered = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        for waiter in readyWaiters { waiter.resume() }
        readyWaiters.removeAll()
        // Deliberately ignore task cancellation to model a stalled external framework.
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
