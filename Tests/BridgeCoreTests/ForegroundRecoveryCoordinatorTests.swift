import Testing
@testable import BridgeCore

@Suite("Foreground recovery")
@MainActor
struct ForegroundRecoveryCoordinatorTests {
    @Test("A burst of requests shares one window restoration")
    func concurrentRequests() async throws {
        let probe = RecoveryProbe()
        let coordinator = probe.coordinator()
        let requests = (0..<32).map { _ in Task { try await coordinator.ensureReady() } }
        await probe.waitUntilStarted()
        // Let every caller reach the suspended recovery before making the scene ready.
        for _ in 0..<64 { await Task.yield() }
        #expect(probe.attempts == 1)
        probe.finish(ready: true)
        for request in requests { #expect(try await request.value) }
        #expect(probe.attempts == 1)
        #expect(try await coordinator.ensureReady())
        #expect(probe.attempts == 1)
    }

    @Test("An already available window needs no activation")
    func alreadyReady() async throws {
        let probe = RecoveryProbe()
        probe.ready = true
        #expect(try await probe.coordinator().ensureReady())
        #expect(probe.attempts == 0)
    }

    @Test("Recovery can run again after failure or after the window closes")
    func subsequentRecovery() async throws {
        let probe = RecoveryProbe()
        let coordinator = probe.coordinator()
        for result in [false, true, true] {
            probe.ready = false
            let request = Task { try await coordinator.ensureReady() }
            await probe.waitUntilStarted()
            probe.finish(ready: result)
            #expect(try await request.value == result)
        }
        #expect(probe.attempts == 3)
    }

    @Test("Cancelling one request preserves recovery for other requests")
    func cancellation() async throws {
        let probe = RecoveryProbe()
        let coordinator = probe.coordinator()
        let cancelled = Task { try await coordinator.ensureReady() }
        await probe.waitUntilStarted()
        let other = Task { try await coordinator.ensureReady() }
        for _ in 0..<8 { await Task.yield() }
        cancelled.cancel()
        probe.finish(ready: true)
        do {
            _ = try await cancelled.value
            Issue.record("Cancelled request should not proceed to HomeKit")
        } catch is CancellationError {
            // Expected: the shared recovery itself was not cancelled.
        }
        #expect(try await other.value)
        #expect(probe.attempts == 1)
    }
}

@MainActor
private final class RecoveryProbe {
    var ready = false
    var attempts = 0
    private var continuation: CheckedContinuation<Bool, Never>?

    func coordinator() -> ForegroundRecoveryCoordinator {
        ForegroundRecoveryCoordinator(isReady: { self.ready }) {
            self.attempts += 1
            return await withCheckedContinuation { self.continuation = $0 }
        }
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    func finish(ready: Bool) {
        self.ready = ready
        let pending = continuation
        continuation = nil
        pending?.resume(returning: ready)
    }
}
