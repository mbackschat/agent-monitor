import Foundation
import Synchronization
import Testing

@testable import AgentMonitorActions
@testable import AgentMonitorCore

private let runtime = ProcessIdentity(pid: 700, startMicroseconds: 1)
private let terminalApp = HostApplication(pid: 500, bundleIdentifier: "com.apple.Terminal", name: "Terminal")
private let editor = HostApplication(pid: 600, bundleIdentifier: "com.example.Editor", name: "Editor")

private final class FakeAdapter: TerminalFocusAdapter {
    let bundleIdentifiers: Set<String> = ["com.apple.Terminal"]
    let found: Bool
    let requests = Mutex<[String]>([])
    init(found: Bool = true) { self.found = found }
    func focus(tty: String, in application: HostApplication) throws -> Bool {
        requests.withLock { $0.append("\(application.pid) \(tty)") }
        return found
    }
}

private final class FakeActivation: Sendable {
    let accepted: Bool
    let requests = Mutex<[Int32]>([])
    init(accepted: Bool = true) { self.accepted = accepted }
    func activate(_ application: HostApplication) -> Bool {
        requests.withLock { $0.append(application.pid) }
        return accepted
    }
}

private func makeFocus(
    host: HostApplication, adapter: FakeAdapter = FakeAdapter(), activation: FakeActivation = FakeActivation()
) -> TerminalFocus {
    TerminalFocus(
        locate: { identity in
            guard identity == runtime else { throw ActionFailure("Runtime changed.") }
            return TerminalHost(tty: "/dev/ttys019", application: host)
        },
        adapters: [adapter], activate: activation.activate)
}

@Test func adapterForTheHostSelectsTheRuntimeTerminal() throws {
    let adapter = FakeAdapter()
    let activation = FakeActivation()
    let outcome = try makeFocus(host: terminalApp, adapter: adapter, activation: activation)
        .focus(runtime: runtime)
    #expect(outcome == .session(application: "Terminal", tty: "/dev/ttys019"))
    #expect(adapter.requests.withLock { $0 } == ["500 /dev/ttys019"])
    #expect(activation.requests.withLock { $0 }.isEmpty)
}

@Test func adapterThatFindsNoSessionDoesNotFallBackToAnotherWindow() throws {
    // Activating the app here could surface a different session's window and mislead the user.
    let activation = FakeActivation()
    let focus = makeFocus(host: terminalApp, adapter: FakeAdapter(found: false), activation: activation)
    #expect(throws: ActionFailure.self) { try focus.focus(runtime: runtime) }
    #expect(activation.requests.withLock { $0 }.isEmpty)
}

@Test func hostWithoutAdapterIsOnlyActivated() throws {
    let adapter = FakeAdapter()
    let activation = FakeActivation()
    let outcome = try makeFocus(host: editor, adapter: adapter, activation: activation).focus(
        runtime: runtime)
    #expect(outcome == .application("Editor"))
    #expect(adapter.requests.withLock { $0 }.isEmpty)
    #expect(activation.requests.withLock { $0 } == [600])
}

@Test func refusedActivationIsReported() {
    let focus = makeFocus(host: editor, activation: FakeActivation(accepted: false))
    #expect(throws: ActionFailure.self) { try focus.focus(runtime: runtime) }
}

@Test func changedRuntimeIsNotFocused() {
    let adapter = FakeAdapter()
    #expect(throws: ActionFailure.self) {
        try makeFocus(host: terminalApp, adapter: adapter)
            .focus(runtime: ProcessIdentity(pid: 700, startMicroseconds: 2))
    }
    #expect(adapter.requests.withLock { $0 }.isEmpty)
}

@Test(arguments: [
    ("focused", true), ("missing", false),
])
func terminalAppPassesTheTTYAsAnArgument(reply: String, found: Bool) throws {
    let fixture = try FakeOSAScript(reply: reply)
    defer { fixture.remove() }
    #expect(try fixture.adapter.focus(tty: "/dev/ttys019", in: terminalApp) == found)
    let call = try fixture.call()
    // The script is fixed text; the device path reaches it only as `argv`, never interpolated.
    #expect(call.last == "/dev/ttys019")
    #expect(call.dropLast().allSatisfy { !$0.contains("ttys019") })
}

@Test(arguments: [
    ("error -1743", "Automation"), ("error -1712", "did not answer"), ("error -600", "-600"),
    ("unexpected", "unsupported"),
])
func terminalAppFailuresAreExplained(reply: String, expected: String) throws {
    let fixture = try FakeOSAScript(reply: reply)
    defer { fixture.remove() }
    do {
        _ = try fixture.adapter.focus(tty: "/dev/ttys019", in: terminalApp)
        Issue.record("Expected \(reply) to fail")
    } catch {
        #expect(error.localizedDescription.contains(expected))
        // The same failure reaches the TUI and `focus --pid`, so it must not name a key.
        #expect(!error.localizedDescription.contains("press"))
    }
}

@Test(arguments: ["ttys019", "/dev/ttys019; beep", "/dev/tty", "/dev/ttys"])
func terminalAppRefusesMalformedDevicePaths(tty: String) throws {
    let fixture = try FakeOSAScript(reply: "focused")
    defer { fixture.remove() }
    #expect(throws: ActionFailure.self) { try fixture.adapter.focus(tty: tty, in: terminalApp) }
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("call").path))
}

@Test(arguments: [RuntimeContext.nonterminal, .unverified])
func focusNeedsARuntimeWithATerminal(context: RuntimeContext) async throws {
    let row = HeavyProcess(
        process: ProcessIdentity(pid: 701, startMicroseconds: 1), executable: "/fixture/worker",
        name: "worker", cpuPercent: 80, footprintBytes: nil, cwd: nil, command: nil,
        metadataStatus: .notObserved,
        attribution: Attribution(
            provider: .claude, evidence: .runtimeOnly, context: context, threadID: nil,
            rootSessionID: nil, runtime: context == .unverified ? nil : runtime, terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
    let adapter = FakeAdapter()
    let actions = SessionActions(
        inspect: { $0 }, terminate: { _ in }, codex: CodexMessaging(), claude: ClaudeMessaging(),
        focus: makeFocus(host: terminalApp, adapter: adapter))
    await #expect(throws: ActionFailure.self) { try await actions.focusTerminal(of: row) }
    #expect(adapter.requests.withLock { $0 }.isEmpty)
}

@Test func nativeLookupRefusesAReusedRuntimeIdentity() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    defer {
        child.terminate()
        child.waitUntilExit()
    }
    #expect(throws: ActionFailure.self) {
        try NativeActions.terminalHost(
            for: ProcessIdentity(pid: child.processIdentifier, startMicroseconds: 1))
    }
}

private struct FakeOSAScript {
    let directory: URL
    let adapter: TerminalAppFocus

    init(reply: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("am-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("osascript.py")
        try #"""
        import json, sys
        reply, log = sys.argv[1:3]
        open(log, 'w').write(json.dumps(sys.argv[3:]))
        print(reply)
        """#.write(to: script, atomically: true, encoding: .utf8)
        adapter = TerminalAppFocus(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            prefix: [script.path, reply, directory.appendingPathComponent("call").path])
    }

    func call() throws -> [String] {
        let data = try Data(contentsOf: directory.appendingPathComponent("call"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String])
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
