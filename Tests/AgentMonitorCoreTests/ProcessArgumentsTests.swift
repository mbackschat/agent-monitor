import Foundation
import Testing

@testable import AgentMonitorCore

func argumentBuffer(arguments: [String] = ["worker", ""], environment: [String]) -> [UInt8] {
    var count = Int32(arguments.count)
    var bytes = withUnsafeBytes(of: &count) { Array($0) }
    bytes += Array("/tmp/worker".utf8) + [0, 0, 0]
    for item in arguments + environment { bytes += Array(item.utf8) + [0] }
    bytes += [0]
    return bytes
}

@Test func environmentParserPreservesEmptyArgumentsAndOnlySessionMarkers() throws {
    let result = ProcessArguments.parse(
        argumentBuffer(environment: [
            "PRIVATE_TOKEN=never-output", "CODEX_THREAD_ID=\(sessionB)", "CODEX_SESSION_ID=\(sessionA)",
        ]), includeCommand: true)
    #expect(result.markers == [SessionMarker(threadID: sessionB, rootSessionID: sessionA, provider: .codex)])
    #expect(result.command == ["worker", ""])
    #expect(result.status == .markerRead)
}

@Test func argumentsAreNotRetainedByDefault() {
    let result = ProcessArguments.parse(argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"]))
    #expect(result.command == nil)
    #expect(result.markers.map(\.threadID) == [sessionA])
}

@Test func conflictingMarkersAreNotResolvedByOrder() {
    let result = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CODEX_THREAD_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)",
        ]))
    #expect(result.markers.isEmpty)
    #expect(result.status == .malformed)
}

@Test(arguments: [[UInt8](), [1, 0, 0, 0, 65], [255, 255, 255, 127, 0]])
func truncatedOrImpossibleBufferIsRejected(bytes: [UInt8]) {
    #expect(ProcessArguments.parse(bytes).status == .malformed)
}

@Test func claudeSessionMarkerIsParsedWithoutReadingTranscripts() {
    let result = ProcessArguments.parse(argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)"]))
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .claude)])
    #expect(result.status == .markerRead)
}

// One agent running inside the other passes both markers on; attribution picks by nearest runtime.
@Test func nestedProviderMarkersAreBothKept() {
    let result = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CLAUDE_CODE_SESSION_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)",
        ]))
    #expect(
        result.markers == [
            SessionMarker(threadID: sessionB, provider: .codex),
            SessionMarker(threadID: sessionA, provider: .claude),
        ])
    #expect(result.status == .markerRead)
}

@Test func claudeInboxSocketIsKeptOnlyBesideItsOwnSessionMarker() {
    let socket = "/tmp/cc-socks/42.sock"
    let claude = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CLAUDE_CODE_SESSION_ID=\(sessionA)", "CLAUDE_CODE_MESSAGING_SOCKET=\(socket)",
            "CLAUDE_CODE_MESSAGING_TOKEN=never-retained",
        ]))
    #expect(claude.markers == [SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: socket)])
    let orphan = ProcessArguments.parse(
        argumentBuffer(environment: ["CLAUDE_CODE_MESSAGING_SOCKET=\(socket)"]))
    #expect(orphan.markers.isEmpty)
    #expect(orphan.status == .notObserved)
}

// An unusable inbox only disables messaging; it is not attribution evidence.
@Test(arguments: [
    ["relative.sock"], ["/" + String(repeating: "a", count: 104)], ["/tmp/a\u{1b}.sock"], [""],
    ["/tmp/a.sock", "/tmp/b.sock"],
])
func unusableInboxPathKeepsTheSessionMarker(paths: [String]) {
    let result = ProcessArguments.parse(
        argumentBuffer(
            environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)"]
                + paths.map { "CLAUDE_CODE_MESSAGING_SOCKET=\($0)" }))
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .claude)])
    #expect(result.status == .markerRead)
}

@Test(arguments: [false, true])
func longUnrelatedFieldsCannotHideOrImitateAnAllowedMarker(includeCommand: Bool) {
    let long = String(repeating: "x", count: 100_000)
    let result = ProcessArguments.parse(
        argumentBuffer(
            arguments: ["worker", long, ""],
            environment: [
                "PRIVATE_VALUE=\(long)", "CODEX_THREAD_ID_EXTRA=\(sessionB)",
                "CODEX_THREAD_ID=\(sessionA)", "NO_EQUAL_SIGN", "=ignored",
            ]), includeCommand: includeCommand)
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
    #expect(result.command == (includeCommand ? ["worker", long, ""] : nil))
    #expect(result.status == .markerRead)
}

@Test func unterminatedLongEnvironmentValueRejectsTheWholeObservation() {
    var bytes = argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"])
    bytes.removeLast()
    bytes += Array(("PRIVATE_VALUE=" + String(repeating: "x", count: 100_000)).utf8)
    #expect(ProcessArguments.parse(bytes).status == .malformed)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ARGUMENT_PARSE_MEASUREMENT_PATH"] != nil))
func measureAllowlistedArgumentParsing() throws {
    let path = try #require(ProcessInfo.processInfo.environment["ARGUMENT_PARSE_MEASUREMENT_PATH"])
    let long = String(repeating: "x", count: 100_000)
    let bytes = argumentBuffer(
        arguments: ["worker", long],
        environment: [
            "PRIVATE_VALUE=\(long)", "CODEX_THREAD_ID=\(sessionA)",
        ])
    let start = ContinuousClock.now
    for _ in 0..<100 {
        let result = ProcessArguments.parse(bytes)
        #expect(result.markers.first?.threadID == sessionA)
    }
    let elapsed = start.duration(to: .now).components
    let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    let data = ["repetitions": 100.0, "bufferBytes": Double(bytes.count), "milliseconds": milliseconds]
    try JSONEncoder().encode(data).write(to: URL(fileURLWithPath: path))
}

@Test func invocationNameIsKeptWithoutRetainingArguments() {
    let hidden = ProcessArguments.parse(argumentBuffer(arguments: ["ugrep", "-G"], environment: []))
    #expect(hidden.invocation == "ugrep")
    #expect(hidden.command == nil)
    #expect(hidden.status == .notObserved)
    let malformed = ProcessArguments.parse(
        argumentBuffer(arguments: ["ugrep"], environment: ["CLAUDE_CODE_SESSION_ID=invalid"]))
    #expect(malformed.status == .malformed)
    #expect(malformed.invocation == "ugrep")
}
