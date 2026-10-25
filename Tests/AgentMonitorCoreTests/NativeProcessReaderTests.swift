import Darwin
import Foundation
import Testing

@testable import AgentMonitorCore

@Test func commandInspectionVerifiesItsOwnLifetimeAndExecutable() async throws {
    let reader = try NativeProcessReader()
    let own = try #require(try reader.snapshot(processIDs: { [getpid()] }, excluding: []).samples.first)
    func row(_ identity: ProcessIdentity, executable: String) -> HeavyProcess {
        HeavyProcess(
            process: identity, executable: executable, name: own.name, cpuPercent: nil,
            footprintBytes: nil, cwd: nil, command: nil, metadataStatus: .notObserved,
            attribution: Attribution(
                provider: nil, evidence: .unknown, context: .unverified, threadID: nil,
                rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                candidateThreadIDs: [], ancestry: []))
    }
    let command = try await NativeProcessReader.inspectCommand(row(own.identity, executable: own.executable))
    #expect(command?.isEmpty == false)
    let reused = ProcessIdentity(pid: own.identity.pid, startMicroseconds: own.identity.startMicroseconds + 1)
    #expect(try await NativeProcessReader.inspectCommand(row(reused, executable: own.executable)) == nil)
    #expect(
        try await NativeProcessReader.inspectCommand(row(own.identity, executable: "/not-the-executable"))
            == nil)
}

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

@Test func oversizedOwnedArgumentsAreCompleteOrExplicitlyTruncated() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("worker.c")
    let executable = directory.appendingPathComponent("worker")
    try """
    #include <string.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
        if (argc == 1) {
            char filler[102408];
            memcpy(filler, "FILLER=", 7);
            memset(filler + 7, 'x', 102400);
            filler[102407] = 0;
            char *env[] = {filler, "CODEX_THREAD_ID=\(sessionA)", 0};
            char *args[] = {argv[0], "--hold", 0};
            execve(argv[0], args, env);
            return 1;
        }
        char byte;
        if (write(1, "R", 1) != 1) return 2;
        return read(0, &byte, 1) < 0;
    }
    """.write(to: source, atomically: true, encoding: .utf8)
    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/clang")
    compiler.arguments = [source.path, "-o", executable.path]
    try compiler.run()
    compiler.waitUntilExit()
    try #require(compiler.terminationStatus == 0)

    let input = Pipe()
    let ready = Pipe()
    let child = Process()
    child.executableURL = executable
    child.standardInput = input
    child.standardOutput = ready
    try child.run()
    defer {
        try? input.fileHandleForWriting.close()
        child.waitUntilExit()
    }
    try #require(ready.fileHandleForReading.readData(ofLength: 1) == Data("R".utf8))
    let reader = try NativeProcessReader()
    let process = try #require(reader.snapshot().samples.first { $0.identity.pid == child.processIdentifier })
    let limited = try #require(reader.captureLaunchEvidence(for: process, maximumBytes: 65_536))
    #expect(limited.status == .truncated)
    #expect(limited.invocation == nil)
    #expect(limited.markers.isEmpty)
    let full = reader.metadata(for: process, includeCommand: true, capturedLaunch: limited)
    #expect(full.status == .markerRead)
    #expect(full.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
    #expect(full.invocation == executable.path)
    #expect(full.command == [executable.path, "--hold"])
}
