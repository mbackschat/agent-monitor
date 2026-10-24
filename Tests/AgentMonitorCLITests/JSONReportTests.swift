import AgentMonitorPresentation
import Darwin
import Foundation
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

@Test func jsonPreservesUnfilteredObservationsBesideDisplayFindings() throws {
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 1, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 100,
        memoryThresholdBytes: 3_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: [], observedFindings: [jsonProcess()])
    let json = try #require(
        JSONSerialization.jsonObject(with: JSONReport.encodeLine(snapshot)) as? [String: Any])
    #expect((json["findings"] as? [[String: Any]])?.isEmpty == true)
    let observed = try #require(json["observedFindings"] as? [[String: Any]])
    #expect(observed.count == 1)
    #expect(observed[0]["footprintBytes"] as? UInt64 == 2_000_000_000)
    #expect(observed[0]["cpuPercent"] == nil)
}

@Test func schemaDiscoveryIsAnExplicitOutputMode() throws {
    #expect(try Options.parse(["--json-schema"]).jsonSchema)
    #expect(throws: (any Error).self) { try Options.parse(["--json", "--json-schema"]) }
    let schema = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
    #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(properties["schemaVersion"]?["const"] as? Int == 6)
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

@Test func jsonlV6CarriesTypedCPUAccountingAndOmitsUnavailableValues() throws {
    var records: [Data] = []
    for host: Double? in [210.9, nil] {
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: host, logicalCPUCount: 8,
                measuredUserPercent: 169.1, unmeasuredLifetimeCount: 3,
                previousScanSeconds: host == nil ? nil : 0.041,
                acquisition: host == nil
                    ? nil
                    : AcquisitionTiming(
                        runID: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                        scanSequence: 1,
                        qualityOfService: .userInitiated, requestedPeriodSeconds: 0.1,
                        achievedPeriodSeconds: 0.102,
                        scanWorkSeconds: 0.008, resolutionDelaySeconds: 0.02,
                        promptCapture: PromptCaptureSummary([]))),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
            memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 10, unreadableProcessCount: 2,
            findings: [jsonProcess()])
        let data = try JSONReport.encodeLine(snapshot)
        records.append(data)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 6)
        let accounting = try #require(json["cpuAccounting"] as? [String: Any])
        #expect(accounting["hostBusyPercent"] as? Double == host)
        #expect(accounting["logicalCPUCount"] as? Int == 8)
        #expect(accounting["measuredUserPercent"] as? Double == 169.1)
        #expect(accounting["unmeasuredLifetimeCount"] as? Int == 3)
        #expect((accounting["previousScanSeconds"] == nil) == (host == nil))
        #expect((accounting["acquisition"] == nil) == (host == nil))
        if host != nil {
            let acquisition = try #require(accounting["acquisition"] as? [String: Any])
            #expect(acquisition["qualityOfService"] as? String == "userInitiated")
            #expect(acquisition["achievedPeriodSeconds"] as? Double == 0.102)
            #expect(acquisition["scanSequence"] as? Int == 1)
        }
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
        footprintBytes: 2_000_000_000, kernelPeakFootprintBytes: 3_000_000_000, cwd: nil,
        command: ["line\nbreak"], metadataStatus: .unavailable,
        attribution: Attribution(
            provider: nil, evidence: .unknown, context: .unverified, threadID: nil,
            rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [],
            ancestry: [identity]))
}

@Test func nativeKernelFootprintPeakReachesJSON() throws {
    let pid = ProcessInfo.processInfo.processIdentifier
    var before = rusage_info_v4()
    #expect(
        withUnsafeMutablePointer(to: &before) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        } == 0)
    let observed = try NativeProcessReader().snapshot(processIDs: { [pid] })
    var monitor = Monitor()
    let accounting = monitor.ingest(observed)
    let snapshot = MonitoringSnapshot(
        cpuAccounting: accounting, timestamp: Date(), intervalSeconds: 0.1,
        cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 1,
        unreadableProcessCount: 0, findings: monitor.findings())
    let json = try #require(
        JSONSerialization.jsonObject(with: JSONReport.encodeLine(snapshot)) as? [String: Any])
    let rows = try #require(json["observedFindings"] as? [[String: Any]])
    let row = try #require(rows.first)
    let peak = try #require(row["kernelPeakFootprintBytes"] as? NSNumber).uint64Value
    #expect(peak >= before.ri_lifetime_max_phys_footprint)
    #expect(peak == observed.samples.first?.kernelPeakFootprintBytes)
}

@Test func windowJSONAndTextRetainHistoricalCPUAndReplayEvidence() throws {
    let original = jsonProcess()
    let run = UUID()
    let opening = AcquisitionScanID(runID: run, sequence: 0)
    let closing = CounterObservationID(
        scan: AcquisitionScanID(runID: run, sequence: 1), process: original.process)
    let contribution = FrozenCPUContribution(
        CPUContribution(
            id: .init(opening: .newbornZero(listing: opening, verifiedBirth: 0.2), closing: closing),
            cpuSeconds: 0.08, startedAt: 0, endedAt: 0.3), attribution: original.attribution, observedAt: 0.25
    )
    let usage = ProcessWindowAccounting(
        cpuSeconds: 0.08, recoveredCPUSeconds: 0,
        pointCandidateCPUSeconds: 0, uncertainCPUSeconds: 0.08, isHistorical: true,
        lastObservedAt: 0.3, lastObservedFootprintBytes: 2_000_000_000)
    let row = HeavyProcess(
        process: original.process, executable: original.executable,
        name: original.name, cpuPercent: 8, footprintBytes: nil, cwd: nil, command: nil,
        metadataStatus: original.metadataStatus, attribution: original.attribution, accounting: usage)
    let window = ReportWindowSummary(
        runID: run, baselineScan: 0, finalScan: 10, startedAt: 0,
        endedAt: 1, contributions: [contribution], excludedObservationCount: 0, evictedBaselineCount: 0,
        unmeasuredLifetimeCount: 0)
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8,
            measuredUserPercent: 8, unmeasuredLifetimeCount: 0, previousScanSeconds: 0.01),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1, cpuThresholdPercent: 0,
        memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: 0,
        findings: [row], window: window)
    let data = try JSONReport.encodeLine(snapshot)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encodedWindow = try #require(json["window"] as? [String: Any])
    let records = try #require(encodedWindow["contributions"] as? [[String: Any]])
    #expect(records[0]["verifiedBirth"] as? Double == 0.2)
    #expect(records[0]["pointEvidenceObservedAt"] as? Double == 0.25)
    #expect(records[0]["revision"] as? Int == 1)
    let text = TextReport.render(snapshot, grouping: .session)
    #expect(text.contains("No longer observed"))
    #expect(text.contains("excluded from current totals"))
    #expect(text.contains("CPU over 1.00 s"))
    #expect(text.contains("0.08 s"))
    var state = LiveReportState(grouping: .none)
    state.receive(snapshot)
    #expect(state.beginAction(.terminate) == nil)
    #expect(state.actionPanel == nil)
    #expect(state.beginMessage(for: row) == nil)
    #expect(
        LiveReportLayout.lines(state: state, width: 120, height: 24).contains { $0.text.contains("[past]") })
    if let path = ProcessInfo.processInfo.environment["JSON_WINDOW_FIXTURE_PATH"] {
        try data.write(to: URL(fileURLWithPath: path))
    }
}
