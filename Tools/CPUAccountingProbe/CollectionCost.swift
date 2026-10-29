import Darwin
import Foundation
import Synchronization

@main enum CollectionCost {
    static func main() async throws {
        for interval in [0.1, 1.0] {
            let samples = 30
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    intervalSeconds: interval, samples: samples, collectAgentLoad: true),
                reader: try NativeProcessReader(), clock: ContinuousSamplingClock(), excluding: [getpid()])
            let scanSeconds = Mutex<[Double]>([])
            let population = Mutex<[Int]>([])
            let cpu = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
            let start = ContinuousClock.now
            try await session.run(

                { snapshot in
                    if let seconds = snapshot.cpuAccounting.previousScanSeconds {
                        scanSeconds.withLock { $0.append(seconds) }
                    }
                    population.withLock { $0.append(snapshot.sampledProcessCount) }
                })
            let cpuSeconds = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpu) / 1e9
            let duration = start.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let scans = scanSeconds.withLock { $0 }
            let output: [String: Double] = [
                "intervalSeconds": interval, "samples": Double(samples), "elapsedSeconds": seconds,
                "processCPUSeconds": cpuSeconds, "averagePercentOfOneCPUCore": 100 * cpuSeconds / seconds,
                "meanScanSeconds": scans.reduce(0, +) / Double(scans.count),
                "maximumScanSeconds": scans.max() ?? 0,
                "meanSampledProcessCount": Double(population.withLock { $0.reduce(0, +) }) / Double(samples),
            ]
            var data = try JSONEncoder().encode(output)
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        }
    }
}
