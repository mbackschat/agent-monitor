import Foundation
import Testing

@testable import AgentMonitorActions
@testable import AgentMonitorCore

private let session = "11111111-1111-4111-8111-111111111111"
private let other = "33333333-3333-4333-8333-333333333333"

private let target = MessageTarget(
    process: HeavyProcess(
        process: ProcessIdentity(pid: 701, startMicroseconds: 1), executable: "/fixture/worker",
        name: "worker", cpuPercent: 80, footprintBytes: nil, cwd: nil, command: nil,
        metadataStatus: .markerRead,
        attribution: Attribution(
            provider: .claude, evidence: .inheritedMarker, context: .terminal, threadID: session,
            rootSessionID: nil, runtime: ProcessIdentity(pid: 700, startMicroseconds: 1), terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: [])),
    session: session, runtime: ProcessIdentity(pid: 700, startMicroseconds: 1))

@Test(arguments: ["busy", "waiting", "idle"])
func claudeVerifiesLiveRuntimeAndPostsOneUnauthenticatedUserLine(status: String) throws {
    let fixture = try FakeClaude(agents: status, inbox: "close")
    defer { fixture.remove() }
    let recipients = try fixture.client.recipients(for: target)
    #expect(recipients.choices == [AgentRecipient(id: session, label: "Claude session")])
    let message = "[Agent Monitor: selected process PID 701 (worker)]\nCheck \"quotes\" / $(whoami)"
    try fixture.client.send(message, to: session, for: target)
    #expect(try fixture.calls() == [#"["agents", "--json"]"#])
    // Without the session's token the inbox applies its peer controls; one line is one message.
    let lines = try fixture.received().split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 2 && lines[1].isEmpty)
    let posted = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? NSDictionary)
    #expect(posted == ["type": "user", "message": ["role": "user", "content": message]] as NSDictionary)
}

@Test(arguments: [
    "other-session", "missing-pid", "duplicate-pid", "unknown-status", "exited", "malformed", "failing",
])
func claudeRejectsSessionsNotHostedByTheLiveRuntime(mode: String) throws {
    let fixture = try FakeClaude(agents: mode, inbox: "close")
    defer { fixture.remove() }
    #expect(throws: (any Error).self) { try fixture.client.recipients(for: target) }
}

@Test(arguments: ["file", "symlink", "missing", "stale"])
func unusableInboxIsReportedAsNotSent(kind: String) throws {
    let fixture = try FakeClaude(agents: "idle", inbox: kind)
    defer { fixture.remove() }
    do {
        try fixture.client.send("message", to: session, for: target)
        Issue.record("Expected an unusable inbox to fail")
    } catch {
        #expect(error.localizedDescription.contains("Nothing was sent"))
    }
}

@Test func inboxThatNeverClosesIsBoundedAndUncertain() throws {
    let fixture = try FakeClaude(agents: "idle", inbox: "hang", timeout: 0.5)
    defer { fixture.remove() }
    let start = ContinuousClock.now
    do {
        try fixture.client.send("message", to: session, for: target)
        Issue.record("Expected an unconfirmed inbox handoff")
    } catch {
        #expect(error.localizedDescription.contains("may have been accepted"))
    }
    #expect(start.duration(to: .now) < .seconds(3))
}

@Test func recipientMustBeTheVerifiedSession() throws {
    let fixture = try FakeClaude(agents: "idle", inbox: "close")
    defer { fixture.remove() }
    #expect(throws: (any Error).self) { try fixture.client.send("message", to: other, for: target) }
    #expect(try fixture.received().isEmpty)
}

private struct FakeClaude {
    let directory: URL
    let client: ClaudeMessaging
    private let listener: Process?

    init(agents mode: String, inbox: String, timeout: TimeInterval = 3) throws {
        // sun_path is 104 bytes, so keep the fixture directory short.
        directory = URL(fileURLWithPath: "/tmp").appendingPathComponent("am-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("claude.py")
        try #"""
        import json, sys
        mode, log = sys.argv[1:3]
        with open(log, 'a') as f: f.write(json.dumps(sys.argv[3:]) + '\n')
        live = {'pid': 700, 'sessionId': '11111111-1111-4111-8111-111111111111'.upper(),
                'kind': 'interactive', 'status': mode, 'cwd': '/fixture', 'startedAt': 1}
        others = [{'pid': 9, 'sessionId': '33333333-3333-4333-8333-333333333333', 'kind': 'background',
                   'status': 'idle', 'cwd': '/fixture', 'startedAt': 1}]
        if mode == 'other-session': live['sessionId'] = '33333333-3333-4333-8333-333333333333'; live['status'] = 'idle'
        if mode == 'missing-pid': live['pid'] = 701; live['status'] = 'idle'
        if mode == 'duplicate-pid': live['status'] = 'idle'; others.append(dict(live, sessionId='33333333-3333-4333-8333-333333333333'))
        if mode == 'unknown-status': live['status'] = 'future-status'
        if mode == 'exited': del live['pid']; del live['status']
        if mode == 'malformed': print('not JSON'); sys.exit(0)
        if mode == 'failing': sys.exit(1)
        print(json.dumps(others + [live]))
        """#.write(to: script, atomically: true, encoding: .utf8)
        let socket = directory.appendingPathComponent("in.sock").path
        let received = directory.appendingPathComponent("received")
        FileManager.default.createFile(atPath: received.path, contents: Data())
        switch inbox {
        case "close", "hang", "stale":
            let server = directory.appendingPathComponent("inbox.py")
            try #"""
            import socket, sys, time
            path, mode, out = sys.argv[1:4]
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.bind(path)
            if mode == 'stale': sys.exit(0)
            s.listen(1)
            connection, _ = s.accept()
            data = b''
            while True:
                chunk = connection.recv(4096)
                if not chunk: break
                data += chunk
            open(out, 'wb').write(data)
            if mode == 'hang': time.sleep(30)
            connection.close()
            """#.write(to: server, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [server.path, socket, inbox, received.path]
            try process.run()
            if inbox == "stale" { process.waitUntilExit() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: socket), ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            listener = process
        case "file":
            FileManager.default.createFile(atPath: socket, contents: Data())
            listener = nil
        case "symlink":
            try FileManager.default.createSymbolicLink(atPath: socket, withDestinationPath: received.path)
            listener = nil
        default:
            listener = nil
        }
        client = ClaudeMessaging(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            prefix: [script.path, mode, directory.appendingPathComponent("calls.jsonl").path],
            timeout: timeout, locateInbox: { _ in socket })
    }

    func calls() throws -> [String] {
        try String(contentsOf: directory.appendingPathComponent("calls.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    func received() throws -> String {
        try String(contentsOf: directory.appendingPathComponent("received"), encoding: .utf8)
    }

    func remove() {
        if let listener, listener.isRunning { listener.terminate() }
        listener?.waitUntilExit()
        try? FileManager.default.removeItem(at: directory)
    }
}
