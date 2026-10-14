import SwiftTUIRuntime

/// Treat bracketed paste as text, never as confirmation or report commands.
final class ActionInputReader: TerminalInputReading, Sendable {
    private let paste: @MainActor @Sendable (String) -> Void

    init(paste: @escaping @MainActor @Sendable (String) -> Void) { self.paste = paste }

    func inputEvents() -> AsyncStream<InputEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let reader = InputReader()
                for await event in reader.inputEvents() {
                    if Task.isCancelled { break }
                    switch event {
                    case .paste(let event): paste(event.content)
                    default: continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
