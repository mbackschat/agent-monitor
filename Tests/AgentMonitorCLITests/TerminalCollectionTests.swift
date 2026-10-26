import Foundation
import Testing

@testable import AgentMonitorTUI

@Suite @MainActor struct TerminalCollectionTests {
    @Test func shutdownJoinsCollectionBeforeReadingTerminalCoverage() async throws {
        let collection = TerminalCollectionTask()
        let entered = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        var terminalCount = 0
        let task = try #require(
            collection.start {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { entered.continuation.yield($0) }
                    terminalCount = 3
                } onCancel: {
                    cancelled.continuation.yield(())
                }
            })
        var entries = entered.stream.makeAsyncIterator()
        let release = try #require(await entries.next())
        var joined = false
        let stopping = Task {
            await collection.stop()
            joined = true
        }
        var cancellations = cancelled.stream.makeAsyncIterator()
        _ = await cancellations.next()
        #expect(!joined)
        #expect(terminalCount == 0)
        #expect(collection.start { Issue.record("Cannot restart during shutdown") } == nil)
        release.resume()
        await stopping.value
        await task.value
        #expect(joined)
        #expect(terminalCount == 3)
    }

    @Test func shutdownBeforeFirstRenderDoesNotWaitOrStartCollection() async {
        let collection = TerminalCollectionTask()
        await collection.stop()
        #expect(collection.start { Issue.record("Collection was stopped before startup") } == nil)
    }
}
