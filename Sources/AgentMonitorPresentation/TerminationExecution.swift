import AgentMonitorActions
import AgentMonitorCore

/// Runs the frozen review targets through the same fresh verification as individual termination.
public enum TerminationExecution {
    public static func perform(_ processes: [HeavyProcess], using actions: any ProcessActions) async
        -> ActionResult
    {
        guard !processes.isEmpty else { return .failed("No termination targets were reviewed.") }
        var outcomes: [String] = []
        for (index, process) in processes.enumerated() {
            let remaining = processes.dropFirst(index + 1).map { String($0.process.pid) }
            func stopped(_ detail: String) -> String {
                (outcomes + ["PID \(process.process.pid): " + detail]
                    + (remaining.isEmpty ? [] : ["Not attempted: PID " + remaining.joined(separator: ", ")]))
                    .joined(separator: "\n")
            }
            if Task.isCancelled {
                return .failed(stopped("Not attempted; action cancelled."))
            }
            do {
                try await actions.terminate(process)
                outcomes.append(ActionWording.terminationAccepted(pid: process.process.pid))
            } catch is CancellationError {
                return .uncertain(stopped("Interrupted; check its outcome before trying again."))
            } catch {
                let detail = stopped(error.localizedDescription)
                return (error as? ActionFailure)?.uncertain == true ? .uncertain(detail) : .failed(detail)
            }
        }
        return .accepted(outcomes.joined(separator: "\n"))
    }
}
