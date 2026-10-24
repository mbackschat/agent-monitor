import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@Test func providerWorkerObservesCancellationOutsideTheCooperativeExecutor() async throws {
    let stopped = Mutex(false)
    let checks = Mutex(0)
    let started = AsyncStream<Void>.makeStream()
    let cancellationReady = DispatchSemaphore(value: 0)
    let worker = SerialBlockingWorker(name: "Provider cancellation fixture", initial: ())
    let registry = CommandSessionRegistryReader(
        executable: URL(fileURLWithPath: "/usr/bin/python3"),
        prefix: ["-c", "import time; time.sleep(30)"], timeout: 5)
    let query = SessionRegistryQuery(tool: "fixture", command: [], environment: [:])
    let task = Task {
        try await worker.perform { _ in
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
    for await _ in started.stream { break }
    stopped.withLock { $0 = true }
    cancellationReady.signal()
    await #expect(throws: CancellationError.self) { try await task.value }
    await worker.close()
    started.continuation.finish()
}
