import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func blockingCommandObservesCancellationOutsideTheCooperativeExecutor(launchFails: Bool) async throws {
    let stopped = Mutex(false)
    let checks = Mutex(0)
    let started = AsyncStream<Void>.makeStream()
    let cancellationReady = DispatchSemaphore(value: 0)
    let worker = SerialBlockingWorker(name: "Command cancellation fixture", initial: ())
    let task = Task {
        defer { started.continuation.finish() }
        return try await worker.perform { _ in
            let command = try BoundedCommand(
                executable: URL(
                    fileURLWithPath: launchFails ? "/dev/null/command-fixture" : "/usr/bin/python3"),
                arguments: ["-c", "import time; time.sleep(30)"], timeout: 5, tool: "fixture",
                checkCancellation: {
                    let count = checks.withLock {
                        $0 += 1
                        return $0
                    }
                    if count == 2 {
                        started.continuation.yield(())
                        cancellationReady.wait()
                    }
                    if stopped.withLock({ $0 }) { throw CancellationError() }
                })
            defer { command.close() }
            return try command.readOutput()
        }
    }
    var iterator = started.stream.makeAsyncIterator()
    let reachedCancellation = await iterator.next() != nil
    stopped.withLock { $0 = true }
    cancellationReady.signal()
    let result = await task.result
    await worker.close()
    #expect(reachedCancellation == !launchFails)
    if launchFails {
        #expect(throws: BoundedCommandFailure.self) { try result.get() }
    } else {
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
