import Darwin
import Foundation
import Testing

@testable import AgentMonitorActions
@testable import AgentMonitorCore

@Test func terminationChecksLifetimeThenSignalsOnlyDisposableChild() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    defer {
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
    }
    let reader = try NativeProcessReader()
    let sample = try #require(reader.snapshot().samples.first { $0.identity.pid == child.processIdentifier })
    var monitor = Monitor()
    monitor.ingest([sample])
    let row = try #require(monitor.finding(for: sample.identity))
    let stale = HeavyProcess(
        process: ProcessIdentity(pid: sample.identity.pid, startMicroseconds: 1),
        executable: row.executable, name: row.name, cpuPercent: nil, footprintBytes: nil, cwd: nil,
        command: nil, metadataStatus: .notObserved, attribution: row.attribution)
    #expect(throws: (any Error).self) { try NativeActions.terminate(stale) }
    #expect(child.isRunning)
    try NativeActions.terminate(row)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while child.isRunning, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
    #expect(!child.isRunning)
    #expect(child.terminationReason == .uncaughtSignal)
    #expect(child.terminationStatus == SIGTERM)
}

@Test func monitorCanInspectProcessesBelowDisplayThresholds() throws {
    let identity = ProcessIdentity(pid: 987, startMicroseconds: 1)
    var monitor = Monitor()
    monitor.ingest([
        ProcessSample(
            identity: identity, parentPID: 1, executable: "/fixture/worker",
            name: "worker", sampledAt: 0, cpuSeconds: nil, footprintBytes: nil)
    ])
    #expect(monitor.findings().isEmpty)
    #expect(monitor.finding(for: identity)?.process == identity)
    monitor.ingest([])
    #expect(monitor.finding(for: identity) == nil)
}

@Test func lookupByPIDReturnsTheCurrentLifetimeIndependentOfThresholds() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    defer {
        child.terminate()
        child.waitUntilExit()
    }
    let row = try NativeActions.process(pid: child.processIdentifier)
    #expect(row.process.pid == child.processIdentifier)
    #expect(row.executable == "/bin/sleep")
    #expect(throws: ActionFailure.self) { try NativeActions.process(pid: getpid()) }
}

// Every Terminal.app shell runs under root-owned `login`; the ancestor walk must read processes
// of other users, which proc_pidinfo refuses with EPERM (observed 2026-10-15, macOS 27).
@Test func ancestorLineageIsReadableForProcessesOfOtherUsers() throws {
    let launchd = try #require(NativeActions.lineage(of: 1))
    #expect(launchd.parent == 0)
    #expect(launchd.start > 0)
}
