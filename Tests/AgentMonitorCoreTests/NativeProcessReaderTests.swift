import Darwin
import Testing

@testable import AgentMonitorCore

@Test func nativeReaderMeasuresItsOwnProcess() throws {
    let reader = try NativeProcessReader()
    let snapshot = try reader.snapshot()
    let own = try #require(snapshot.samples.first { $0.identity.pid == getpid() })
    #expect(own.identity.startMicroseconds > 0)
    #expect(own.cpuSeconds != nil)
    #expect(try #require(own.footprintBytes) > 0)
    #expect(!own.executable.isEmpty)
    #expect(reader.metadata(for: own).cwd != nil)
}

@Test func nativeMetadataRejectsWrongProcessLifetime() throws {
    let reader = try NativeProcessReader()
    let wrong = sample(getpid(), start: 1)
    #expect(reader.metadata(for: wrong).status == .unavailable)
}

@Test func cpuCounterMatchesPOSIXProcessClock() throws {
    var clock = timespec()
    #expect(clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &clock) == 0)
    let before = Double(clock.tv_sec) + Double(clock.tv_nsec) / 1_000_000_000
    let snapshot = try NativeProcessReader().snapshot()
    let own = try #require(snapshot.samples.first { $0.identity.pid == getpid() })
    #expect(clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &clock) == 0)
    let after = Double(clock.tv_sec) + Double(clock.tv_nsec) / 1_000_000_000
    let cpu = try #require(own.cpuSeconds)
    #expect(cpu >= before - 0.01)
    #expect(cpu <= after + 0.01)
}
