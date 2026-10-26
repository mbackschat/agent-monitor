import Foundation

/// SwiftTUI 0.14.0 TaskRunner.cancelAll cancels without joining. The host must wait
/// for collection's drain before reading terminal coverage or releasing its controller.
@MainActor
final class TerminalCollectionTask {
    private var task: Task<Void, Never>?
    private var stopped = false

    func start(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard !stopped else { return nil }
        if let task { return task }
        let task = Task { await operation() }
        self.task = task
        return task
    }

    func stop() async {
        stopped = true
        task?.cancel()
        await task?.value
        task = nil
    }
}
