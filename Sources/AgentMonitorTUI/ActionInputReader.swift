import SwiftTUIRuntime

/// Ignore bracketed paste so pasted keys cannot confirm actions or become report commands.
final class ActionInputReader: TerminalInputReading, Sendable {
    func inputEvents() -> AsyncStream<InputEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let reader = InputReader()
                for await event in reader.inputEvents() {
                    if Task.isCancelled { break }
                    switch event {
                    case .paste: break
                    default: continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
