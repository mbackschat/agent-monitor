import AgentMonitorCore
import Darwin
import Foundation
import Testing

@testable import monitor_workload_capture

@Suite struct WorkloadCaptureTests {
    @Test(arguments: [0.0, 12_345.67])
    func defaultBudgetKeepsAFullMinuteOfPopulationSizedScans(origin: Double) throws {
        let samples = (0..<1000).map { index in
            ProcessSample(
                identity: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1), parentPID: 0,
                executable: "/fixture/node-\(index)", name: "node", sampledAt: 0,
                cpuSeconds: 0.25, footprintBytes: 4096)
        }
        var time = origin
        var starts: [Double] = []
        var lastRecord = Data()
        var bytes = 0
        try Capture.run(
            options: CaptureOptions(), now: { time }, sleep: { time += $0 }, cpu: { 0 },
            cancelled: { false },
            read: {
                starts.append(time)
                return ProcessSnapshot(
                    samples: samples, enumeratedCount: samples.count, unreadableCount: 0,
                    listedAt: time, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8)
            },
            write: {
                bytes += $0.count
                lastRecord = $0
            })
        let last = try #require(JSONSerialization.jsonObject(with: lastRecord) as? [String: Any])
        #expect(last["reason"] as? String == "duration")
        #expect(last["scanCount"] as? Int == 600)
        #expect(time == origin + 60)
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 })
        #expect(bytes > 32 * 1024 * 1024)
    }

    func snapshot(at time: Double, birth: UInt64 = 1, cpu: Double? = 0.2) -> ProcessSnapshot {
        var sample = ProcessSample(
            identity: ProcessIdentity(pid: 42, startMicroseconds: birth), parentPID: 10,
            executable: "/fixture/node", name: "node", sampledAt: time,
            cpuSeconds: cpu, footprintBytes: 4096)
        sample.startedAt = 0.01
        sample.kernelPeakFootprintBytes = 8192
        return ProcessSnapshot(
            samples: [sample], enumeratedCount: 1, unreadableCount: 0,
            listedAt: time, scanSeconds: 0.01, hostCounters: nil, logicalCPUCount: 8,
            nativeOutcomes: [
                NativeCounterOutcome(
                    pid: 43, identity: nil, operation: .resourceUsage,
                    status: .lookupUnavailable, failure: nil, observedAtTicks: 123)
            ], listedPIDs: [42, 43])
    }

    func records(_ data: Data) throws -> [[String: Any]] {
        try data.split(separator: 10).map {
            try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    @Test func retainsExactIdentitiesMissingCountersAndFailureEvidence() throws {
        var time = 0.0
        var output = Data()
        var count = 0
        try Capture.run(
            options: CaptureOptions(seconds: 0.25), now: { time }, sleep: { time += $0 },
            cpu: { 0.012 }, cancelled: { false },
            read: {
                count += 1
                return snapshot(at: time, birth: UInt64(count), cpu: count == 2 ? nil : 0.2)
            }, write: { output.append($0) })
        let rows = try records(output)
        #expect(rows.count == 5)
        let scans = rows.filter { $0["kind"] as? String == "scan" }
        try #require(scans.count == 3)
        let processes = try scans.map {
            try #require(($0["processes"] as? [[String: Any]])?.first)
        }
        #expect(
            processes.compactMap { ($0["identity"] as? [String: Any])?["startMicroseconds"] as? Int } == [
                1, 2, 3,
            ])
        #expect(processes[1]["cpuSeconds"] == nil)
        #expect(processes[0]["kernelPeakFootprintBytes"] as? Int == 8192)
        let failures = try #require(scans[0]["outcomes"] as? [[String: Any]])
        #expect(failures[0]["status"] as? String == "lookupUnavailable")
        #expect(rows.last?["reason"] as? String == "duration")
        #expect(rows.last?["scanCount"] as? Int == 3)
        #expect(time == 0.25)
    }

    @Test func sizeLimitReservesFooterAndNeverWritesPartialRecord() throws {
        var output = Data()
        var reads = 0
        try Capture.run(
            options: CaptureOptions(seconds: 1, maximumBytes: 8192), now: { 0 }, sleep: { _ in },
            cpu: { 0 }, cancelled: { false },
            read: {
                reads += 1
                let original = snapshot(at: 0)
                return ProcessSnapshot(
                    samples: Array(repeating: original.samples[0], count: 100),
                    enumeratedCount: 100, unreadableCount: 0, listedAt: 0, scanSeconds: 0,
                    hostCounters: nil, logicalCPUCount: 8)
            }, write: { output.append($0) })
        #expect(output.count <= 8192)
        #expect(reads == 1)
        let rows = try records(output)
        #expect(rows.count == 2)
        #expect(rows.last?["reason"] as? String == "sizeLimit")
        #expect(rows.last?["scanCount"] as? Int == 0)
    }

    @Test func cancellationDoesNotReadAndSlowReadsDoNotTriggerCatchUpBurst() throws {
        var output = Data()
        try Capture.run(
            options: CaptureOptions(), now: { 0 }, sleep: { _ in }, cpu: { 0 },
            cancelled: { true },
            read: {
                Issue.record("Read after cancellation")
                return snapshot(at: 0)
            },
            write: { output.append($0) })
        #expect(try records(output).last?["reason"] as? String == "cancelled")
        var time = 0.0
        var starts: [Double] = []
        try Capture.run(
            options: CaptureOptions(seconds: 0.35), now: { time }, sleep: { time += $0 },
            cpu: { 0 }, cancelled: { false },
            read: {
                starts.append(time)
                time += 0.24
                return snapshot(at: time - 0.24)
            }, write: { _ in })
        try #require(starts.count == 2)
        #expect(abs(starts[1] - 0.3) < 0.00001)
    }

    enum Failure: Error { case reader, writer }

    @Test func preservesReaderFailureWhenFooterWriteAlsoFails() throws {
        var writes = 0
        #expect(throws: Failure.reader) {
            try Capture.run(
                options: CaptureOptions(), now: { 0 }, sleep: { _ in }, cpu: { 0 },
                cancelled: { false }, read: { throw Failure.reader },
                write: { _ in
                    writes += 1
                    if writes > 1 { throw Failure.writer }
                })
        }
        #expect(writes == 2)
    }

    @Test(arguments: [Double.nan, .infinity, 0, -1, 301])
    func rejectsInvalidDuration(seconds: Double) {
        #expect(throws: (any Error).self) { try CaptureOptions(seconds: seconds) }
    }

    @Test(arguments: [-1, 0, 8191, CaptureOptions.maximumMiB * 1024 * 1024 + 1])
    func rejectsInvalidSizeLimit(bytes: Int) {
        #expect(throws: (any Error).self) { try CaptureOptions(maximumBytes: bytes) }
    }

    @Test(arguments: [Capture.StopReason.duration, .sizeLimit, .cancelled, .readerFailure])
    func completionDistinguishesEarlyStops(reason: Capture.StopReason) {
        let result = Capture.Footer(
            reason: reason, scanCount: 125, elapsedSeconds: 12.5, processCPUSeconds: 0.5,
            bytesBeforeFooter: 32 * 1024 * 1024, maximumListingGapSeconds: 0.1, maximumScanSeconds: 0.01)
        #expect(result.statusLine(requestedSeconds: 60).contains("12.5 / 60.0 seconds"))
        switch reason {
        case .duration: #expect(result.exitStatus == 0)
        case .sizeLimit:
            #expect(result.exitStatus == 2)
            #expect(result.statusLine(requestedSeconds: 60).contains("file limit"))
        case .cancelled: #expect(result.exitStatus == 130)
        case .readerFailure: #expect(result.exitStatus == 1)
        }
    }

    @Test func writerFailureStopsBeforeReading() {
        #expect(throws: Failure.writer) {
            try Capture.run(
                options: CaptureOptions(), now: { 0 }, sleep: { _ in }, cpu: { 0 },
                cancelled: { false },
                read: {
                    Issue.record("Read after writer failure")
                    return snapshot(at: 0)
                },
                write: { _ in throw Failure.writer })
        }
    }

    @Test func outputIsPrivateAndNeverOverwritesExistingDataOrSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("capture.jsonl").path
        let file = try CaptureFile(path: path)
        try file.handle.write(contentsOf: Data("fixture".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o077 == 0)
        #expect(throws: (any Error).self) { _ = try CaptureFile(path: path) }
        let link = directory.appendingPathComponent("link.jsonl").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: path)
        #expect(throws: (any Error).self) { _ = try CaptureFile(path: link) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "fixture")
    }
}
