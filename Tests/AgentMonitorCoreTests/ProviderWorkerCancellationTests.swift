import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func providerWorkerObservesCancellationOutsideTheCooperativeExecutor(launchFails: Bool) async throws {
    let stopped = Mutex(false)
    let checks = Mutex(0)
    let started = AsyncStream<Void>.makeStream()
    let cancellationReady = DispatchSemaphore(value: 0)
    let worker = SerialBlockingWorker(name: "Provider cancellation fixture", initial: ())
    let registry = CommandSessionRegistryReader(
        executable: URL(fileURLWithPath: launchFails ? "/dev/null/provider-fixture" : "/usr/bin/python3"),
        prefix: ["-c", "import time; time.sleep(30)"], timeout: 5)
    let query = SessionRegistryQuery(tool: "fixture", command: [], environment: [:])
    let task = Task {
        defer { started.continuation.finish() }
        return try await worker.perform { _ in
            try registry.output(
                of: query,
                checking: {
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
