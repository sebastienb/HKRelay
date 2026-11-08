import Testing
@testable import BridgeCore

@Suite("Transient command lifetime")
@MainActor
struct CommandActivityTests {
    @Test("The card waits until every concurrent command finishes")
    func concurrentLifetime() {
        let activity = CommandActivity()
        let ids = (0..<16).map { activity.begin(title: "Mock Lamp \($0)", detail: "Turn on") }
        for id in ids.dropLast() {
            activity.finish(id, failed: false)
            #expect(!activity.canDismiss(revision: activity.revision))
        }
        activity.finish(ids.last!, failed: false)
        #expect(activity.canDismiss(revision: activity.revision))
        #expect(activity.completedCount == 16)
    }

    @Test("A new command invalidates the previous dismissal timer")
    func staleDismissal() {
        let activity = CommandActivity()
        let first = activity.begin(title: "Mock Lamp A", detail: "Turn on")
        activity.finish(first, failed: false)
        let oldRevision = activity.revision
        let second = activity.begin(title: "Mock Lamp B", detail: "Turn off")
        #expect(!activity.canDismiss(revision: oldRevision))
        activity.finish(second, failed: false)
        #expect(!activity.canDismiss(revision: oldRevision))
        #expect(activity.canDismiss(revision: activity.revision))
        #expect(activity.title == "Mock Lamp B")
    }

    @Test("A failure remains visible through the rest of its batch")
    func failureInBatch() {
        let activity = CommandActivity()
        let first = activity.begin(title: "Mock Lamp A", detail: "Turn on")
        let second = activity.begin(title: "Mock Lamp B", detail: "Turn on")
        activity.finish(first, failed: true)
        activity.finish(second, failed: false)
        activity.finish(first, failed: true)
        #expect(activity.failureCount == 1)
        #expect(activity.completedCount == 2)
        _ = activity.begin(title: "Mock Lamp A", detail: "Read Power State")
        #expect(activity.failureCount == 0)
        #expect(activity.completedCount == 0)
    }
}
