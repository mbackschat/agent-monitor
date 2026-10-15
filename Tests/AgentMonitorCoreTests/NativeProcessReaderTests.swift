import Darwin
import Foundation
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

@Test func listeningUnixSocketsOfAnOwnedProcessAreRead() throws {
    let directory = "/tmp/am-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/in.sock"
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    child.arguments = [
        "-c",
        "import socket,sys,time\ns=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.listen(1)\n"
            + "c=socket.socket(socket.AF_UNIX)\ntime.sleep(30)",
        path,
    ]
    try child.run()
    defer {
        child.terminate()
        child.waitUntilExit()
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !FileManager.default.fileExists(atPath: path), ContinuousClock.now < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    Thread.sleep(forTimeInterval: 0.1)
    #expect(try NativeProcessReader().listeningSockets(child.processIdentifier) == [path])
}
