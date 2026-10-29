import Darwin
import Foundation
import Synchronization

private final class RecordingReader: ProcessReading, Sendable {
    struct Capture: Sendable {
        var monitor = Monitor()
        var seconds: [ProcessIdentity: Double] = [:]
        var scans = 0
    }
    let native: NativeProcessReader
    let parent: Int32
    let capture = Mutex(Capture())

    init(parent: Int32) throws {
        self.parent = parent
        native = try NativeProcessReader()
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let snapshot = try native.snapshot(excluding: excluding)
        capture.withLock { value in
            value.monitor.ingest(snapshot)
            value.scans += 1
            for sample in snapshot.samples where sample.parentPID == parent {
                if let cpu = value.monitor.cpuContribution(for: sample.identity) {
                    value.seconds[sample.identity, default: 0] += cpu.cpuSeconds
                }
            }
        }
        return snapshot
    }

    func isCurrent(_ sample: ProcessSample) -> Bool { native.isCurrent(sample) }

    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        native.captureLaunchEvidence(for: sample, maximumBytes: maximumBytes)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?)
        -> ProcessMetadata
    {
        native.metadata(for: sample, includeCommand: includeCommand, capturedLaunch: capturedLaunch)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        native.metadata(for: sample, includeCommand: includeCommand)
    }
}

@main enum Conservation {
    struct Ledger: Decodable {
        struct Worker: Decodable {
            let pid: Int32
            let cpuSeconds: Double
            let requestedCPUSeconds: Double
            enum CodingKeys: String, CodingKey {
                case pid
                case cpuSeconds = "cpu_seconds"
                case requestedCPUSeconds = "requested_cpu_seconds"
            }
        }
        let parent: Int32
        let workers: [Worker]
        let totalCPUSeconds: Double
        enum CodingKeys: String, CodingKey {
            case parent, workers
            case totalCPUSeconds = "total_cpu_seconds"
        }
    }

    static func main() async throws {
        for interval in (CommandLine.arguments.contains("--fast") ? [0.01] : [0.1, 1.0]) {
            let worker = Process()
            let output = Pipe()
            worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            worker.arguments = ["Tools/CPUAccountingProbe/trace-workload.py", "--mixed"]
            worker.environment = [
                "PATH": "/usr/bin:/bin", "CODEX_THREAD_ID": "11111111-1111-4111-8111-111111111111",
            ]
            worker.standardOutput = output
            try worker.run()
            let reader = try RecordingReader(parent: worker.processIdentifier)
            let start = ContinuousClock.now
            if interval < 0.1 {
                var seen: [ProcessIdentity: String] = [:]
                for _ in 0..<401 {
                    let snapshot = try reader.snapshot(excluding: [getpid()])
                    for sample in snapshot.samples where seen[sample.identity] != sample.executable {
                        _ = reader.metadata(for: sample, includeCommand: false)
                        seen[sample.identity] = sample.executable
                    }
                    try await Task.sleep(for: .seconds(interval))
                }
            } else {
                let session = MonitoringSession(
                    configuration: try MonitoringConfiguration(
                        intervalSeconds: interval, samples: interval < 1 ? 50 : 8, collectAgentLoad: true),
                    reader: reader, clock: ContinuousSamplingClock(),
                    excluding: [getpid()])
                try await session.run({ _ in })
            }
            worker.waitUntilExit()
            guard worker.terminationStatus == 0 else { fatalError("Owned fixture failed") }
            let ledger = try JSONDecoder().decode(
                Ledger.self, from: output.fileHandleForReading.readDataToEndOfFile())
            let capture = reader.capture.withLock { $0 }
            let rows: [[String: Double]] = ledger.workers.map { expected in
                let matches = capture.seconds.filter { $0.key.pid == expected.pid }
                precondition(matches.count <= 1, "Fixture PID reused; reject the run")
                return [
                    "pid": Double(expected.pid), "requestedCPUSeconds": expected.requestedCPUSeconds,
                    "oracleCPUSeconds": expected.cpuSeconds, "measuredCPUSeconds": matches.values.first ?? 0,
                    "measuredLifetimes": Double(matches.count),
                ]
            }
            let measured = rows.compactMap { $0["measuredCPUSeconds"] }.reduce(0, +)
            let duration = start.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let result: [String: Any] = [
                "intervalSeconds": interval, "elapsedSeconds": seconds, "scans": capture.scans,
                "method": interval < 0.1
                    ? "prototype: native scans plus first-observation metadata; no refresh, registry or UI"
                    : "production MonitoringSession; registry disabled; no UI",
                "oracleCPUSeconds": ledger.totalCPUSeconds, "measuredCPUSeconds": measured,
                "ratio": measured / ledger.totalCPUSeconds, "workers": rows,
            ]
            var data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        }
    }
}
