import Darwin
import Foundation
import Synchronization

@main enum LoadProbe {
    private enum ProbeError: Error { case usage }

    static func main() async throws {
        switch Array(CommandLine.arguments.dropFirst()) {
        case []:
            try await measure(interval: 15, samples: 4, collectAgentLoad: true)
        case ["--history"]:
            for enabled in [false, true, true, false] {
                try await measure(interval: 1, samples: 40, collectAgentLoad: enabled)
            }
        default:
            throw ProbeError.usage
        }
    }

    private static func measure(interval: Double, samples: Int, collectAgentLoad: Bool) async throws {
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: interval, samples: samples, collectAgentLoad: collectAgentLoad),
            reader: try NativeProcessReader(), excluding: [getpid()])
        let summaries = Mutex(0)
        let start = ContinuousClock.now
        let cpu = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        try await session.run { snapshot in
            if snapshot.agentLoad != nil { summaries.withLock { $0 += 1 } }
        }
        let ms = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpu) / 1e6
        let time = start.duration(to: .now).components
        let seconds = Double(time.seconds) + Double(time.attoseconds) / 1e18
        let output: [String: Double] = [
            "samples": Double(samples), "intervalSeconds": interval, "elapsedSeconds": seconds,
            "collectAgentLoad": collectAgentLoad ? 1 : 0, "summaryCount": Double(summaries.withLock { $0 }),
            "processCPUMilliseconds": ms, "averagePercentOfOneCPUCore": ms / (seconds * 10),
            "logicalProcessors": Double(ProcessInfo.processInfo.activeProcessorCount),
        ]
        var data = try JSONEncoder().encode(output)
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
