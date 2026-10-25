import Foundation
import Synchronization

enum BlockingWorkerError: Error { case stopped, busy }

/// Synchronous native/provider calls must not occupy Swift's cooperative executor.
/// State belongs to the dedicated thread; the mutex protects only handoff and shutdown.
final class SerialBlockingWorker<WorkerState: Sendable>: Sendable {
    private typealias Job = @Sendable (inout WorkerState) -> Void
    private struct Mailbox {
        var job: Job?
        var stopping = false
        var finished = false
        var join: CheckedContinuation<Void, Never>?
    }

    private let mailbox = Mutex(Mailbox())
    private let ready = DispatchSemaphore(value: 0)

    init(
        name: String, initial: WorkerState, qualityOfService: QualityOfService = .userInitiated,
        profile: PipelineProfile? = nil, role: PipelineProfile.Worker = .acquisition
    ) {
        let thread = Thread { [self] in
            let threadStart = profile.map { _ in PipelineProfile.Stamp() }
            var state = initial
            while true {
                ready.wait()
                let (job, stop) = mailbox.withLock { box in
                    defer { box.job = nil }
                    return (box.job, box.stopping)
                }
                if let job {
                    let start = profile.map { _ in PipelineProfile.Stamp() }
                    autoreleasepool { job(&state) }
                    if let start { profile?.endJob(role, since: start) }
                } else if stop {
                    break
                }
            }
            if let threadStart { profile?.endThread(role, since: threadStart) }
            let join = mailbox.withLock { box in
                box.finished = true
                defer { box.join = nil }
                return box.join
            }
            join?.resume()
        }
        thread.name = name
        thread.qualityOfService = qualityOfService
        thread.start()
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (inout WorkerState) throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let value: Value = try await withCheckedThrowingContinuation { continuation in
            let failure: BlockingWorkerError? = mailbox.withLock { box in
                guard !box.stopping else { return .stopped }
                guard box.job == nil else { return .busy }
                box.job = { state in continuation.resume(with: Result { try operation(&state) }) }
                return nil
            }
            if let failure { continuation.resume(throwing: failure) } else { ready.signal() }
        }
        try Task.checkCancellation()
        return value
    }

    /// Joins after accepted work returns; native syscalls cannot be interrupted safely.
    func close() async {
        await withCheckedContinuation { continuation in
            let finished = mailbox.withLock { box in
                box.stopping = true
                guard !box.finished else { return true }
                box.join = continuation
                return false
            }
            if finished { continuation.resume() } else { ready.signal() }
        }
    }
}
