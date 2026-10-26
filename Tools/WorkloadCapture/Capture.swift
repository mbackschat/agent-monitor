import AgentMonitorCore
import Foundation

struct CaptureOptions {
    let seconds: Double
    let maximumBytes: Int

    init(seconds: Double = 60, maximumBytes: Int = 32 * 1024 * 1024) throws {
        guard seconds.isFinite, seconds > 0, seconds <= 300,
            (8192...128 * 1024 * 1024).contains(maximumBytes)
        else { throw CaptureError.invalidOptions }
        self.seconds = seconds
        self.maximumBytes = maximumBytes
    }
}

enum CaptureError: Error { case invalidOptions, recordTooLarge }

enum Capture {
    static let interval = 0.1

    enum StopReason: String, Encodable { case duration, sizeLimit, cancelled, readerFailure }

    struct Header: Encodable {
        let kind = "header"
        let format = "agent-monitor-workload-observations"
        let version = 1
        let startedAt = Date()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let excludedPID = ProcessInfo.processInfo.processIdentifier
        let intervalSeconds = Capture.interval
        let durationSeconds: Double
        let maximumBytes: Int
        let population = "Readable current-user processes, excluding this recorder; no session attribution"
        let limitations =
            "Polling observations: unseen workers and final exit CPU are unknown; absence is not exit"
    }

    struct Footer: Encodable {
        let kind = "footer"
        let reason: StopReason
        let scanCount: Int
        let elapsedSeconds: Double
        let processCPUSeconds: Double
        let bytesBeforeFooter: Int
        let maximumListingGapSeconds: Double?
        let maximumScanSeconds: Double
    }

    static func run(
        options: CaptureOptions, now: () -> Double, sleep: (Double) -> Void,
        cpu: () -> Double, cancelled: () -> Bool, read: () throws -> ProcessSnapshot,
        write: (Data) throws -> Void
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let started = now()
        let cpuStarted = cpu()
        var bytes = 0
        var scans = 0
        var previousListing: Double?
        var maximumGap: Double?
        var maximumScan = 0.0

        func append(_ value: some Encodable, reserve: Int) throws -> Bool {
            var data = try encoder.encode(value)
            data.append(10)
            guard data.count <= options.maximumBytes - bytes - reserve else { return false }
            try write(data)
            bytes += data.count
            return true
        }

        func finish(_ reason: StopReason) throws {
            let footer = Footer(
                reason: reason, scanCount: scans, elapsedSeconds: now() - started,
                processCPUSeconds: cpu() - cpuStarted, bytesBeforeFooter: bytes,
                maximumListingGapSeconds: maximumGap, maximumScanSeconds: maximumScan)
            guard try append(footer, reserve: 0) else { throw CaptureError.recordTooLarge }
        }

        // Reserve a terminal record even when one population-sized scan cannot fit on disk.
        guard
            try append(
                Header(durationSeconds: options.seconds, maximumBytes: options.maximumBytes), reserve: 4096)
        else { throw CaptureError.recordTooLarge }
        while now() - started < options.seconds {
            if cancelled() {
                try finish(.cancelled)
                return
            }
            let snapshot: ProcessSnapshot
            do { snapshot = try read() } catch {
                // Preserve the primary failure across cleanup, as required by the a9f0339 harness fix.
                try? finish(.readerFailure)
                throw error
            }
            let gap = previousListing.map { snapshot.listedAt - $0 }
            let record = CaptureScan(snapshot, sequence: scans, listingGapSeconds: gap)
            guard try append(record, reserve: 4096) else {
                try finish(.sizeLimit)
                return
            }
            scans += 1
            previousListing = snapshot.listedAt
            if let gap { maximumGap = max(maximumGap ?? gap, gap) }
            maximumScan = max(maximumScan, snapshot.scanSeconds)
            let elapsed = now() - started
            let nextSlot = (floor(elapsed / interval) + 1) * interval
            sleep(max(0, min(options.seconds, nextSlot) - elapsed))
        }
        try finish(.duration)
    }
}
