import Darwin
import Foundation

@main enum LoadProbe {
    static func main() async throws {
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 15, samples: 4, collectAgentLoad: true),
            reader: try NativeProcessReader(), excluding: [getpid()])
        let start = ContinuousClock.now
        let cpu = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        try await session.run { _ in }
        let ms = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpu) / 1e6
        let time = start.duration(to: .now).components
        let seconds = Double(time.seconds) + Double(time.attoseconds) / 1e18
        let output: [String: Double] = [
            "samples": 4, "intervalSeconds": 15, "elapsedSeconds": seconds,
            "processCPUMilliseconds": ms, "averagePercentOfOneCPUCore": ms / (seconds * 10),
            "logicalProcessors": Double(ProcessInfo.processInfo.activeProcessorCount),
        ]
        print(String(decoding: try JSONEncoder().encode(output), as: UTF8.self))
    }
}
