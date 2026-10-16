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
    #expect(properties["schemaVersion"]?["const"] as? Int == 3)
}

@Test func jsonlContainsOneCompleteRecordPerLineEvenWhenArgumentsContainNewlines() throws {
    let row = jsonProcess()
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
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

@Test func jsonlV3CarriesTypedCPUAccountingAndOmitsUnavailableValues() throws {
    var records: [Data] = []
    for host: Double? in [210.9, nil] {
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: host, logicalCPUCount: 8,
                measuredUserPercent: 169.1, unmeasuredLifetimeCount: 3,
                previousScanSeconds: host == nil ? nil : 0.041),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
            memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 10, unreadableProcessCount: 2,
            findings: [jsonProcess()])
        let data = try JSONReport.encodeLine(snapshot)
        records.append(data)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 3)
        let accounting = try #require(json["cpuAccounting"] as? [String: Any])
        #expect(accounting["hostBusyPercent"] as? Double == host)
        #expect(accounting["logicalCPUCount"] as? Int == 8)
        #expect(accounting["measuredUserPercent"] as? Double == 169.1)
        #expect(accounting["unmeasuredLifetimeCount"] as? Int == 3)
        #expect((accounting["previousScanSeconds"] == nil) == (host == nil))
    }
    let schema = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect((schema["required"] as? [String])?.contains("cpuAccounting") == true)
    let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let accounting = try #require(definitions["cpuAccounting"])
    #expect(accounting["additionalProperties"] as? Bool == false)
    #expect(
        Set(accounting["required"] as? [String] ?? []) == [
            "logicalCPUCount", "measuredUserPercent", "unmeasuredLifetimeCount",
        ])
    if let path = ProcessInfo.processInfo.environment["JSON_REPORT_FIXTURE_PATH"] {
        try records.reduce(into: Data()) { $0.append($1) }.write(to: URL(fileURLWithPath: path))
    }
}

private func jsonProcess() -> HeavyProcess {
    let identity = ProcessIdentity(pid: 42, startMicroseconds: 1)
    return HeavyProcess(
        process: identity, executable: "/bin/worker", name: "worker", cpuPercent: nil,
        footprintBytes: 2_000_000_000, cwd: nil, command: ["line\nbreak"], metadataStatus: .unavailable,
        attribution: Attribution(
            provider: nil, evidence: .unknown, context: .unverified, threadID: nil,
            rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [],
            ancestry: [identity]))
}
