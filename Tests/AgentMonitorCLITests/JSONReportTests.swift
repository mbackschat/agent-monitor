import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

@Test func schemaDiscoveryIsAnExplicitOutputMode() throws {
    #expect(try Options.parse(["--json-schema"]).jsonSchema)
    #expect(throws: (any Error).self) { try Options.parse(["--json", "--json-schema"]) }
    let schema = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
    #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(properties["schemaVersion"]?["const"] as? Int == 2)
}

@Test func jsonlContainsOneCompleteRecordPerLineEvenWhenArgumentsContainNewlines() throws {
    let identity = ProcessIdentity(pid: 42, startMicroseconds: 1)
    let row = HeavyProcess(
        process: identity, executable: "/bin/worker", name: "worker", cpuPercent: nil,
        footprintBytes: 2_000_000_000, cwd: nil, command: ["line\nbreak"], metadataStatus: .unavailable,
        attribution: Attribution(
            provider: nil, evidence: .unknown, context: .unverified, threadID: nil,
            rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [],
            ancestry: [identity]))
    let snapshot = MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: [row])
    let line = try JSONReport.encodeLine(snapshot)
    #expect(line.filter { $0 == 10 }.count == 1)
    #expect(line.last == 10)
    let value = try #require(JSONSerialization.jsonObject(with: line) as? [String: Any])
    #expect(value["timestamp"] as? String == "1970-01-01T00:00:00Z")
    let rows = try #require(value["findings"] as? [[String: Any]])
    #expect(rows[0]["command"] as? [String] == ["line\nbreak"])
    #expect(rows[0]["cpuPercent"] == nil)
}
