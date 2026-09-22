import Foundation
import Testing
@testable import Mindlore

@MainActor
struct UndoQueueTests {
    @Test func undoCancelsTheDelete() {
        let queue = UndoQueue(window: .seconds(60))
        var committed = 0
        let id = UUID()
        queue.schedule([id], message: "Entry deleted") { committed += 1 }

        #expect(queue.hiddenIDs == [id])
        queue.undo()
        queue.commitNow()

        #expect(committed == 0)
        #expect(queue.hiddenIDs.isEmpty)
    }

    @Test func aSecondDeleteCommitsTheFirst() {
        let queue = UndoQueue(window: .seconds(60))
        var committed: [String] = []
        queue.schedule([UUID()], message: "one") { committed.append("one") }
        queue.schedule([UUID()], message: "two") { committed.append("two") }

        #expect(committed == ["one"])
        queue.commitNow()
        #expect(committed == ["one", "two"])
        queue.commitNow()
        #expect(committed == ["one", "two"], "a commit runs once")
    }

    @Test func theWindowRunningOutCommits() async throws {
        let queue = UndoQueue(window: .milliseconds(10))
        var committed = false
        queue.schedule([UUID()], message: "Entry deleted") { committed = true }
        try await Task.sleep(for: .milliseconds(200))

        #expect(committed)
        #expect(queue.pending == nil)
    }
}
