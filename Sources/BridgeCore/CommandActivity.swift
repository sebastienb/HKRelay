import Foundation
import Observation

/// Tracks commands sharing a transient window and invalidates stale dismissal timers.
@MainActor
@Observable
public final class CommandActivity {
    public private(set) var title = "HomeKit command"
    public private(set) var detail = "Preparing…"
    public private(set) var activeCount = 0
    public private(set) var completedCount = 0
    public private(set) var failureCount = 0
    public private(set) var revision = 0
    @ObservationIgnored private var activeIDs: Set<UUID> = []

    public init() {}

    public func begin(title: String, detail: String) -> UUID {
        if activeIDs.isEmpty {
            completedCount = 0
            failureCount = 0
        }
        self.title = title
        self.detail = detail
        let id = UUID()
        activeIDs.insert(id)
        activeCount = activeIDs.count
        revision += 1
        return id
    }

    public func finish(_ id: UUID, failed: Bool) {
        guard activeIDs.remove(id) != nil else { return }
        activeCount = activeIDs.count
        completedCount += 1
        if failed { failureCount += 1 }
        revision += 1
    }

    public func canDismiss(revision: Int) -> Bool {
        activeIDs.isEmpty && revision == self.revision
    }
}
