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
    #expect(result.marker == SessionMarker(threadID: sessionB, rootSessionID: sessionA))
    #expect(result.command == ["worker", ""])
    #expect(result.status == .markerRead)
}

@Test func argumentsAreNotRetainedByDefault() {
    let result = ProcessArguments.parse(argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"]))
    #expect(result.command == nil)
    #expect(result.marker?.threadID == sessionA)
}

@Test func conflictingMarkersAreNotResolvedByOrder() {
    let result = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CODEX_THREAD_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)",
        ]))
    #expect(result.marker == nil)
    #expect(result.status == .malformed)
}

@Test(arguments: [[UInt8](), [1, 0, 0, 0, 65], [255, 255, 255, 127, 0]])
func truncatedOrImpossibleBufferIsRejected(bytes: [UInt8]) {
    #expect(ProcessArguments.parse(bytes).status == .malformed)
}

@Test func claudeSessionMarkerIsParsedWithoutReadingTranscripts() {
    let result = ProcessArguments.parse(argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)"]))
    #expect(result.marker == SessionMarker(threadID: sessionA, provider: .claude))
    #expect(result.status == .markerRead)
}

@Test func mixedProviderMarkersAreNotGuessed() {
    let result = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CLAUDE_CODE_SESSION_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)",
        ]))
    #expect(result.marker == nil)
    #expect(result.status == .malformed)
}

@Test func claudeInboxSocketIsKeptOnlyBesideItsOwnSessionMarker() {
    let socket = "/tmp/cc-socks/42.sock"
    let claude = ProcessArguments.parse(
        argumentBuffer(environment: [
            "CLAUDE_CODE_SESSION_ID=\(sessionA)", "CLAUDE_CODE_MESSAGING_SOCKET=\(socket)",
            "CLAUDE_CODE_MESSAGING_TOKEN=never-retained",
        ]))
    #expect(claude.marker == SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: socket))
    let orphan = ProcessArguments.parse(
        argumentBuffer(environment: ["CLAUDE_CODE_MESSAGING_SOCKET=\(socket)"]))
    #expect(orphan.marker == nil)
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
    #expect(result.marker == SessionMarker(threadID: sessionA, provider: .claude))
    #expect(result.status == .markerRead)
}
