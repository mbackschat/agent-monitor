import Foundation
import Testing

@testable import AgentMonitorActions
@testable import AgentMonitorCore

private let selected = "11111111-1111-4111-8111-111111111111"
private let root = "22222222-2222-4222-8222-222222222222"

@Test(arguments: ["live", "fragmented"])
func codexHandshakeReadsSummaryAndQueuesLiteralArguments(mode: String) throws {
    let fixture = try FakeCodex(mode: mode)
    defer { fixture.remove() }
    let recipients = try fixture.client.recipients(for: target(selected))
    #expect(recipients.root.id == root)
    #expect(recipients.selected.id == selected)
    #expect(recipients.choices.count == 2)
    #expect(try fixture.client.recipients(for: target(root)).choices.count == 1)
    let message = "PID 42\n'$(echo no)' `pwd`"
    try fixture.client.send(message, to: root, for: target(selected))
    let calls = try fixture.calls()
    #expect(calls.contains { $0.contains("\"includeTurns\": false") })
    let arguments = try #require(calls.last)
    let array = try #require(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String])
    #expect(array == ["queue", "--remote", "unix://", "--thread", root, "--message", message])
}

@Test(arguments: [
    "malformed", "unloaded", "wrong-id", "rpc-error", "unknown-status", "bad-upgrade", "oversized", "closed",
])
func codexRejectsUnverifiedSessions(mode: String) throws {
    let fixture = try FakeCodex(mode: mode)
    defer { fixture.remove() }
    #expect(throws: (any Error).self) { try fixture.client.recipients(for: target(selected)) }
    #expect(try fixture.calls().allSatisfy { !$0.contains("\"queue\"") })
}

@Test(arguments: ["root-unloaded", "root-missing"])
func unavailableRootDoesNotSilentlySelectChild(mode: String) throws {
    let fixture = try FakeCodex(mode: mode)
    defer { fixture.remove() }
    let recipients = try fixture.client.recipients(for: target(selected))
    #expect(recipients.root.id == root)
    #expect(recipients.root.unavailableReason != nil)
    #expect(recipients.selected.unavailableReason == nil)
}

@Test func providerTimeoutIsBoundedAndQueueFailureIsUncertain() throws {
    let fixture = try FakeCodex(mode: "hang", timeout: 0.3)
    defer { fixture.remove() }
    let start = ContinuousClock.now
    #expect(throws: (any Error).self) { try fixture.client.recipients(for: target(selected)) }
    #expect(start.duration(to: .now) < .seconds(3))
    do {
        try fixture.client.send("message", to: root, for: target(selected))
        Issue.record("Expected uncertain queue result")
    } catch {
        #expect(error.localizedDescription.contains("may have been accepted"))
    }
}

private func target(_ session: String) -> MessageTarget {
    let runtime = ProcessIdentity(pid: 700, startMicroseconds: 1)
    return MessageTarget(
        process: HeavyProcess(
            process: ProcessIdentity(pid: 701, startMicroseconds: 1), executable: "/fixture/worker",
            name: "worker", cpuPercent: nil, footprintBytes: nil, cwd: nil, command: nil,
            metadataStatus: .markerRead,
            attribution: Attribution(
                provider: .codex, evidence: .marker, context: .terminal, threadID: session,
                rootSessionID: nil, runtime: runtime, terminal: nil, runtimeDirectory: nil,
                candidateThreadIDs: [], ancestry: [])),
        session: session, runtime: runtime)
}

private struct FakeCodex {
    let directory: URL
    let client: CodexMessaging
    init(mode: String, timeout: TimeInterval = 3) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("codex.py")
        try #"""
        import base64, hashlib, json, struct, sys, time
        mode, log = sys.argv[1:3]
        args = sys.argv[3:]
        def record(value):
            with open(log, 'a') as f: f.write(json.dumps(value) + '\n')
        record(args)
        if mode == 'hang': time.sleep(30)
        if args[0] == 'queue': sys.exit(0)
        assert sys.stdin.buffer.readline().startswith(b'GET / HTTP/1.1')
        headers = {}
        while True:
            line = sys.stdin.buffer.readline()
            if line == b'\r\n': break
            key, value = line.decode().split(':', 1)
            headers[key.lower()] = value.strip()
        accept = base64.b64encode(hashlib.sha1((headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        if mode == 'bad-upgrade': accept = 'invalid'
        sys.stdout.buffer.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n').encode())
        sys.stdout.buffer.flush()
        def frame(data, opcode=1, final=True):
            size = len(data)
            header = bytes([(128 if final else 0) | opcode])
            header += bytes([size]) if size < 126 else bytes([126]) + struct.pack('!H', size)
            sys.stdout.buffer.write(header + data); sys.stdout.buffer.flush()
        def respond(value):
            data = json.dumps(value).encode()
            if mode == 'fragmented':
                frame(data[:5], final=False)
                frame(b'ping', opcode=9)
                frame(data[5:], opcode=0)
            else: frame(data)
        initialized = False
        while True:
            head = sys.stdin.buffer.read(2)
            if not head: break
            assert head[1] & 128
            size = head[1] & 127
            if size == 126: size = struct.unpack('!H', sys.stdin.buffer.read(2))[0]
            elif size == 127: size = struct.unpack('!Q', sys.stdin.buffer.read(8))[0]
            mask = sys.stdin.buffer.read(4)
            data = bytes(b ^ mask[i % 4] for i,b in enumerate(sys.stdin.buffer.read(size)))
            if head[0] & 15 == 10:
                assert data == b'ping'
                continue
            request = json.loads(data)
            record(request)
            method = request['method']
            if method == 'initialized':
                initialized = True
                continue
            if method == 'initialize': result = {}
            else:
                assert initialized
                assert method == 'thread/read'
                assert request['params']['includeTurns'] is False
                identity = request['params']['threadId']
                root = '22222222-2222-4222-8222-222222222222'
                if mode == 'root-missing' and identity == root:
                    respond({'id': request['id'], 'error': {'code': -1}})
                    continue
                status = 'idle'
                if mode == 'unloaded' or (mode == 'root-unloaded' and identity == root): status = 'notLoaded'
                if mode == 'unknown-status': status = 'future-status'
                if mode == 'wrong-id': identity = root
                result = {'thread': {'id': identity, 'sessionId': root, 'status': {'type': status}}}
            if mode == 'oversized':
                sys.stdout.buffer.write(b'\x81\x7f' + struct.pack('!Q', 2**32)); sys.stdout.buffer.flush()
                time.sleep(10)
            elif mode == 'closed': frame(b'', opcode=8)
            elif mode == 'malformed': frame(b'not JSON')
            elif mode == 'rpc-error': respond({'id': request['id'], 'error': {'code': -1}})
            else: respond({'id': request['id'], 'result': result})
        """#.write(to: script, atomically: true, encoding: .utf8)
        client = CodexMessaging(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            prefix: [script.path, mode, directory.appendingPathComponent("calls.jsonl").path],
            timeout: timeout)
    }
    func calls() throws -> [String] {
        try String(contentsOf: directory.appendingPathComponent("calls.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
