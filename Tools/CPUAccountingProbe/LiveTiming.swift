import Darwin
import Foundation

@main enum LiveTiming {
    struct Scan: Encodable {
        let listedAt: Double
        let periodSeconds: Double?
        let scanSeconds: Double
        let hostBusyPercent: Double?
        let measuredUserPercent: Double
        let readableLifetimes: Int
        let unreadableCount: Int
        let newLifetimes: Int
        let absentLifetimes: Int
    }

    struct Run: Encodable {
        let requestedWaitSeconds: Double
        let elapsedSeconds: Double
        let processCPUSeconds: Double
        let startedAt: Date
        let scans: [Scan]
    }

    static func main() async throws {
        let reader = try NativeProcessReader()
        for interval in [0.1, 0.01] {
            var monitor = Monitor()
            var scans: [Scan] = []
            var previousListing: Double?
            var previousIdentities: Set<ProcessIdentity> = []
            let start = ContinuousClock.now
            let date = Date()
            let cpuStart = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
            while start.duration(to: .now) < .seconds(20) {
                let snapshot = try reader.snapshot(excluding: [getpid()])
                let accounting = monitor.ingest(snapshot)
                let identities = Set(snapshot.samples.map(\.identity))
                scans.append(
                    Scan(
                        listedAt: snapshot.listedAt,
                        periodSeconds: previousListing.map { snapshot.listedAt - $0 },
                        scanSeconds: snapshot.scanSeconds,
                        hostBusyPercent: accounting.hostBusyPercent,
                        measuredUserPercent: accounting.measuredUserPercent,
                        readableLifetimes: identities.count,
                        unreadableCount: snapshot.unreadableCount,
                        newLifetimes: previousListing == nil
                            ? 0 : identities.subtracting(previousIdentities).count,
                        absentLifetimes: previousListing == nil
                            ? 0 : previousIdentities.subtracting(identities).count))
                previousListing = snapshot.listedAt
                previousIdentities = identities
                try await Task.sleep(for: .seconds(interval))
            }
            let duration = start.duration(to: .now).components
            let result = Run(
                requestedWaitSeconds: interval,
                elapsedSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                processCPUSeconds: Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart) / 1e9,
                startedAt: date, scans: scans)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(result)
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        }
    }
}
