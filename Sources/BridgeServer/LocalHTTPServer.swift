import Darwin
import BridgeCore
import Foundation

public enum ServerState: Equatable, Sendable {
    case stopped
    case starting
    case ready(port: UInt16)
    case failed(String)
}

public enum ServerBinding: Equatable, Sendable {
    case loopback
    case localNetwork

    var ipv4Address: String {
        switch self {
        case .loopback: "127.0.0.1"
        case .localNetwork: "0.0.0.0"
        }
    }
}

public final class LocalHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let port: UInt16
    private let binding: ServerBinding
    private let handler: Handler
    private let maximumConnections: Int
    private let requestTimeout: TimeInterval
    private var connections: [UUID: SocketConnection] = [:]
    private let queue = DispatchQueue(label: "org.homekitrestbridge.http-server")
    private var listenerSource: DispatchSourceRead?
    private var isStopping = false
    private var stopCompletions: [@Sendable () -> Void] = []

    public init(
        port: UInt16,
        binding: ServerBinding = .loopback,
        maximumConnections: Int = 32,
        requestTimeout: TimeInterval = 30,
        handler: @escaping Handler
    ) {
        self.port = port
        self.binding = binding
        self.handler = handler
        self.maximumConnections = max(1, maximumConnections)
        self.requestTimeout = max(0.1, requestTimeout)
    }

    public func start(stateHandler: @escaping @Sendable (ServerState) -> Void) {
        queue.async { [weak self] in
            guard let self, listenerSource == nil, !isStopping else { return }
            stateHandler(.starting)

            do {
                let (descriptor, boundPort) = try makeListenerSocket()
                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [weak self] in
                    self?.acceptConnections(from: descriptor)
                }
                source.setCancelHandler { [self] in
                    Darwin.close(descriptor)
                    listenerSource = nil
                    stateHandler(.stopped)
                    finishStoppingWhenSocketsClose()
                }
                listenerSource = source
                source.resume()
                stateHandler(.ready(port: boundPort))
            } catch {
                stateHandler(.failed(error.localizedDescription))
            }
        }
    }

    public func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            if let completion {
                stopCompletions.append(completion)
            }

            guard let listenerSource else {
                finishStoppingWhenSocketsClose()
                return
            }
            guard !isStopping else { return }

            isStopping = true
            // Close sockets before reporting stop; cancel handlers without retrying writes.
            for connection in Array(connections.values) { connection.close() }
            listenerSource.cancel()
        }
    }

    func makeListenerSocket() throws -> (descriptor: Int32, port: UInt16) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw SocketError.operation("socket", errno)
        }

        do {
            var reuseAddress: Int32 = 1
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuseAddress,
                socklen_t(MemoryLayout.size(ofValue: reuseAddress))
            ) == 0 else {
                throw SocketError.operation("setsockopt", errno)
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr(binding.ipv4Address))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.bind(
                        descriptor,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
            guard bindResult == 0 else {
                throw SocketError.operation("bind", errno)
            }
            guard Darwin.listen(descriptor, 16) == 0 else {
                throw SocketError.operation("listen", errno)
            }

            let currentFlags = fcntl(descriptor, F_GETFL, 0)
            guard currentFlags >= 0,
                  fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
                throw SocketError.operation("fcntl", errno)
            }
            var boundAddress = sockaddr_in()
            var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    getsockname(descriptor, socketAddress, &boundAddressLength)
                }
            }
            guard nameResult == 0 else {
                throw SocketError.operation("getsockname", errno)
            }
            return (descriptor, UInt16(bigEndian: boundAddress.sin_port))
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func finishStoppingWhenSocketsClose() {
        guard listenerSource == nil, connections.values.allSatisfy({ $0.socketIsClosed }) else { return }
        finishStopping()
    }

    private func finishStopping() {
        isStopping = false
        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func acceptConnections(from listenerDescriptor: Int32) {
        guard !isStopping else { return }
        // Yield periodically so traffic cannot starve timeouts and stop requests.
        for _ in 0..<64 {
            let connectionDescriptor = Darwin.accept(listenerDescriptor, nil, nil)
            if connectionDescriptor >= 0 {
                guard connections.count < maximumConnections else {
                    Darwin.close(connectionDescriptor)
                    continue
                }
                guard configureConnection(connectionDescriptor) else {
                    Darwin.close(connectionDescriptor)
                    continue
                }
                let id = UUID()
                let connection = SocketConnection(
                    descriptor: connectionDescriptor,
                    queue: queue,
                    requestTimeout: requestTimeout,
                    handler: handler,
                    socketClosed: { [weak self] in self?.finishStoppingWhenSocketsClose() },
                    completion: { [weak self] in self?.connections.removeValue(forKey: id) }
                )
                connections[id] = connection
                connection.start()
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            return
        }
    }

    private func configureConnection(_ descriptor: Int32) -> Bool {
        var noSignal: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout.size(ofValue: noSignal))
        ) == 0 else { return false }

        let currentFlags = fcntl(descriptor, F_GETFL, 0)
        return currentFlags >= 0 && fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0
    }
}

private final class SocketConnection: @unchecked Sendable {
    // Mutable state and all descriptor I/O are confined to the server queue.
    private let descriptor: Int32
    private let queue: DispatchQueue
    private let requestTimeout: TimeInterval
    private let handler: LocalHTTPServer.Handler
    private let completion: @Sendable () -> Void
    private let socketClosed: @Sendable () -> Void
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var timeoutSource: DispatchSourceTimer?
    private var handlerTask: Task<Void, Never>?
    private var buffer = Data()
    private var output = Data()
    private var sent = 0
    private var closed = false
    private var completed = false
    private var activeIOSources = 0
    private var descriptorClosed = false

    init(descriptor: Int32, queue: DispatchQueue, requestTimeout: TimeInterval,
         handler: @escaping LocalHTTPServer.Handler, socketClosed: @escaping @Sendable () -> Void,
         completion: @escaping @Sendable () -> Void) {
        self.descriptor = descriptor
        self.queue = queue
        self.requestTimeout = requestTimeout
        self.handler = handler
        self.completion = completion
        self.socketClosed = socketClosed
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailableBytes() }
        source.setCancelHandler { [self] in ioSourceCancelled() }
        activeIOSources += 1
        readSource = source
        source.resume()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + min(10, requestTimeout))
        timer.setEventHandler { [weak self] in self?.close() }
        timeoutSource = timer
        timer.resume()
    }

    private func readAvailableBytes() {
        guard !closed else { return }
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        if count > 0 {
            buffer.append(bytes, count: count)
            do {
                if let request = try HTTPParser.parse(buffer) { dispatch(request) }
            } catch HTTPParseError.requestTooLarge {
                respond(.json(statusCode: 413, envelope: .failure(code: "request_too_large", message: "Request exceeds 1 MB.")))
            } catch {
                respond(.json(statusCode: 400, envelope: .failure(code: "invalid_request", message: "Malformed HTTP request.")))
            }
        } else if count == 0 {
            respond(.json(statusCode: 400, envelope: .failure(code: "invalid_request", message: "Incomplete HTTP request.")))
        } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            close()
        }
    }

    private func dispatch(_ request: HTTPRequest) {
        readSource?.cancel()
        readSource = nil
        buffer = Data()
        // Keep a deadline during upstream HomeKit work. Never retry a timed-out write.
        timeoutSource?.schedule(deadline: .now() + requestTimeout)
        handlerTask = Task { [self] in
            // Avoid starting queued work after a stop or timeout cancels the task.
            if Task.isCancelled {
                queue.async { [self] in handlerFinished(nil) }
                return
            }
            let response = await handler(request)
            queue.async { [self] in handlerFinished(response) }
        }
    }

    private func handlerFinished(_ response: HTTPResponse?) {
        handlerTask = nil
        if closed { finishCompletion(); return }
        if let response { respond(response) } else { close() }
    }

    private func respond(_ response: HTTPResponse) {
        guard !closed else { return }
        readSource?.cancel()
        readSource = nil
        buffer = Data()
        output = response.serialized()
        timeoutSource?.schedule(deadline: .now() + min(5, requestTimeout))
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.writeAvailableBytes() }
        source.setCancelHandler { [self] in ioSourceCancelled() }
        activeIOSources += 1
        writeSource = source
        source.resume()
    }

    private func writeAvailableBytes() {
        guard !closed else { return }
        // One nonblocking write per event, so a slow client cannot block other connections.
        let count = output.withUnsafeBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            return Darwin.write(descriptor, base.advanced(by: sent), min(bytes.count - sent, 64 * 1024))
        }
        if count > 0 {
            sent += count
            if sent == output.count { close() }
        } else if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            close()
        }
    }

    var socketIsClosed: Bool { descriptorClosed }

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil
        timeoutSource?.cancel()
        timeoutSource = nil
        buffer = Data()
        output = Data()
        handlerTask?.cancel()
        // A cancellation-resistant handler still consumes a slot until it returns.
        // This bounds outstanding tasks instead of admitting unlimited replacement work.
        closeDescriptorIfReady()
    }

    private func ioSourceCancelled() {
        activeIOSources -= 1
        closeDescriptorIfReady()
    }

    private func closeDescriptorIfReady() {
        // A descriptor must not be recycled while Dispatch still owns an I/O source.
        guard closed, activeIOSources == 0, !descriptorClosed else { return }
        descriptorClosed = true
        Darwin.close(descriptor)
        socketClosed()
        finishCompletion()
    }

    private func finishCompletion() {
        guard closed, descriptorClosed, handlerTask == nil, !completed else { return }
        completed = true
        completion()
    }
}

private struct SocketError: LocalizedError {
    let operation: String
    let code: Int32

    static func operation(_ operation: String, _ code: Int32) -> SocketError {
        SocketError(operation: operation, code: code)
    }

    var errorDescription: String? {
        "HTTP server \(operation) failed: \(String(cString: strerror(code)))"
    }
}
