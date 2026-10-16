import Foundation
import Testing

@testable import AgentMonitorCore

private func cpuSample(
    at: Double, cpu: Double?, born: Double, start: UInt64 = 10, executable: String = "/bin/worker"
) -> ProcessSample {
    var value = sample(10, start: start, executable: executable, at: at, cpu: cpu)
    value.startedAt = born
    return value
}

@Test func newbornUsesPreviousListingRatherThanAgeOrConfiguredWait() throws {
    var monitor = Monitor()
    monitor.ingest([], listedAt: 10)
    monitor.ingest([cpuSample(at: 14, cpu: 1, born: 13)], listedAt: 13.9)
    #expect(try #require(monitor.findings().first).cpuPercent == 25)
}

@Test(arguments: [9.0, 10.0]) func olderFirstObservationHasNoCPU(born: Double) throws {
    var monitor = Monitor()
    monitor.ingest([], listedAt: 10)
    monitor.ingest([cpuSample(at: 12, cpu: 1, born: born)], listedAt: 11.9)
    #expect(try #require(monitor.findings().first).cpuPercent == nil)
    monitor.ingest([cpuSample(at: 14, cpu: 2, born: born)], listedAt: 13.9)
    #expect(try #require(monitor.findings().first).cpuPercent == 50)
}

@Test func firstSnapshotHasNoCPU() throws {
    var monitor = Monitor()
    monitor.ingest([cpuSample(at: 12, cpu: 1, born: 11)], listedAt: 11.9)
    #expect(try #require(monitor.findings().first).cpuPercent == nil)
}

@Test func existingLifetimeUsesOwnSampleDeltaAcrossExec() throws {
    var monitor = Monitor()
    monitor.ingest([cpuSample(at: 11, cpu: 2, born: 1)], listedAt: 10)
    monitor.ingest([cpuSample(at: 13, cpu: 3, born: 1, executable: "/bin/replacement")], listedAt: 12)
    #expect(try #require(monitor.findings().first).cpuPercent == 50)
}

@Test func reusedPIDGetsNewbornBaselineWithoutOldCPU() throws {
    var monitor = Monitor()
    monitor.ingest([cpuSample(at: 11, cpu: 20, born: 1)], listedAt: 10)
    monitor.ingest([cpuSample(at: 14, cpu: 1, born: 12, start: 200)], listedAt: 13)
    #expect(try #require(monitor.findings().first).cpuPercent == 25)
}

@Test func retainedAncestorCannotBridgeAnUnobservedSnapshot() throws {
    var monitor = Monitor()
    monitor.ingest([cpuSample(at: 11, cpu: 2, born: 1), sample(20, parent: 10)], listedAt: 10)
    monitor.ingest([sample(20, parent: 10, at: 13)], listedAt: 12)
    monitor.ingest([cpuSample(at: 15, cpu: 4, born: 1)], listedAt: 14)
    #expect(try #require(monitor.findings().first).cpuPercent == nil)
}

@Test func unreadableCPUDoesNotInventANewbornBaselineOnNextObservation() throws {
    var monitor = Monitor()
    monitor.ingest([], listedAt: 10)
    monitor.ingest([cpuSample(at: 12, cpu: nil, born: 11)], listedAt: 11.9)
    monitor.ingest([cpuSample(at: 14, cpu: 1, born: 11)], listedAt: 13.9)
    #expect(try #require(monitor.findings().first).cpuPercent == nil)
}

@Test func nativeNewbornCPUAgreesWithOwnedFixedCPUBurn() throws {
    let reader = try NativeProcessReader()
    let baseline = try reader.snapshot(processIDs: { [] })
    var monitor = Monitor()
    monitor.ingest(baseline)
    let child = Process()
    let output = Pipe()
    let input = Pipe()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    child.arguments = [
        "-c",
        "import time,sys\nstart=time.process_time()\nwhile time.process_time()-start < 0.3: pass\n"
            + "print(time.process_time(),flush=True)\nsys.stdin.buffer.read(1)",
    ]
    child.standardOutput = output
    child.standardInput = input
    try child.run()
    defer {
        try? input.fileHandleForWriting.write(contentsOf: Data([10]))
        child.waitUntilExit()
    }
    let bytes = output.fileHandleForReading.availableData
    let cpu = try #require(
        Double(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    let snapshot = try reader.snapshot(processIDs: { [child.processIdentifier] })
    let process = try #require(snapshot.samples.first)
    #expect(try #require(process.startedAt) > baseline.listedAt)
    #expect(snapshot.scanSeconds >= 0)
    monitor.ingest(snapshot)
    let actual = try #require(
        monitor.findings(thresholds: Thresholds(cpuPercent: 0, memoryBytes: 0)).first?.cpuPercent)
    let expected = 100 * cpu / (process.sampledAt - baseline.listedAt)
    // POSIX CPU time is the independent oracle; 20 ms allows printing and native counter/read skew.
    #expect(abs(actual - expected) <= 100 * 0.02 / (process.sampledAt - baseline.listedAt))
}
