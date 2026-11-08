/// Shares a foreground recovery attempt across concurrent accessory requests.
/// Cancelling one caller must not cancel recovery needed by the other callers.
@MainActor
public final class ForegroundRecoveryCoordinator {
    private let isReady: @MainActor () -> Bool
    private let restore: @MainActor () async -> Bool
    private var inFlight: Task<Bool, Never>?

    public init(
        isReady: @escaping @MainActor () -> Bool,
        restore: @escaping @MainActor () async -> Bool
    ) {
        self.isReady = isReady
        self.restore = restore
    }

    public func ensureReady() async throws -> Bool {
        try Task.checkCancellation()
        if let inFlight {
            let result = await inFlight.value
            try Task.checkCancellation()
            return result
        }
        guard !isReady() else { return true }

        let task = Task { await restore() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        try Task.checkCancellation()
        return result
    }
}
