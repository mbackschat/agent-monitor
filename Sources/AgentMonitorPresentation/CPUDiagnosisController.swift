import AgentMonitorCore
import Foundation
import Observation

public typealias CPUDiagnosisSource = @Sendable () async throws -> CPUDiagnosis

/// One interface's owned finite run; cancellation hides results before synchronous work drains.
@MainActor @Observable
public final class CPUDiagnosisController {
    public private(set) var state = DiagnosisViewState() {
        didSet { onChange?(state) }
    }
    @ObservationIgnored public var onChange: (@MainActor (DiagnosisViewState) -> Void)?
    @ObservationIgnored private let source: CPUDiagnosisSource
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    public init(source: @escaping CPUDiagnosisSource = CPUDiagnosisSession.collectLocal) {
        self.source = source
    }

    @discardableResult public func start() -> Bool {
        guard !state.isRunning else { return false }
        generation = UUID()
        let token = generation
        state = DiagnosisViewState(phase: .collecting, isRunning: true)
        task = Task { @concurrent [source] in
            let result: Result<CPUDiagnosis, any Error>
            do {
                try Task.checkCancellation()
                let value = try await source()
                try Task.checkCancellation()
                result = .success(value)
            } catch { result = .failure(error) }
            await self.finish(result, generation: token)
        }
        return true
    }

    public func cancel() {
        guard state.phase == .collecting else { return }
        generation = UUID()
        task?.cancel()
        state = DiagnosisViewState(phase: .cancelled, isRunning: state.isRunning)
    }

    public func dismiss() {
        generation = UUID()
        task?.cancel()
        state = DiagnosisViewState(isRunning: state.isRunning)
    }

    public func waitForCompletion() async { await task?.value }

    public func stop() async {
        dismiss()
        await waitForCompletion()
    }

    private func finish(_ result: Result<CPUDiagnosis, any Error>, generation token: UUID) {
        task = nil
        guard token == generation else {
            state.isRunning = false
            return
        }
        switch result {
        case .success(let value):
            state = DiagnosisViewState(phase: .completed, content: DiagnosisViewState.resultLines(value))
        case .failure(is CancellationError):
            state = DiagnosisViewState(phase: .cancelled)
        case .failure:
            state = DiagnosisViewState(phase: .failed)
        }
    }
}
