import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct SamplingCoveragePresentationTests {
    @Test func detailsExplainRatesUsingTheirActualSupportAndRetainOverrideTotals() throws {
        let snapshot = try samplingSnapshot()
        let summary = SamplingCoverageSummary(snapshot: snapshot)
        let metrics = Dictionary(uniqueKeysWithValues: summary.metrics.map { ($0.id, $0) })
        #expect(summary.metrics.allSatisfy { $0.help.count <= 75 && !$0.help.contains("\n") })
        #expect(metrics["sampling-mode"]?.value == "Adaptive")
        #expect(metrics["sampling-requested"]?.value == "100.00 / 300.00 ms")
        #expect(metrics["sampling-bounds"]?.value == "100.00–500.00 ms")
        #expect(metrics["gap"]?.value == "600.00 / 500.00 ms")
        #expect(metrics["sampling-rolling"]?.value == "4.00 / 2.00 ms/s")
        #expect(metrics["sampling-rolling"]?.help.contains("12.50 s") == true)
        #expect(metrics["sampling-recent"]?.value == "20.00 ms/s")
        #expect(metrics["sampling-recent"]?.help.contains("1.25 s") == true)
        #expect(metrics["sampling-arrivals"]?.value == "6.00 / min")
        #expect(metrics["sampling-rolling-support"]?.value == "12.50 s")
        #expect(metrics["sampling-recent-support"]?.value == "1.25 s")
        #expect(metrics["sampling-override-recovery"]?.value == "1 × / 0.50 s")
        #expect(metrics["sampling-override-recovery"]?.help.contains("currently active") == true)
        #expect(metrics["sampling-changes"]?.value == "2")
        var state = LiveReportState()
        state.receive(snapshot)
        state.showReference(.diagnostics)
        let content = ReportReferenceLayout.content(state: state, page: .diagnostics).map(\.text).joined(
            separator: "\n")
        #expect(content.contains("Requested / base: 100.00 / 300.00 ms"))
        #expect(content.contains("Recovery: 1 × / 0.50 s"))
        #expect(content.contains("12.50 s of enclosing support"))
    }

    @Test func baselineWithoutRateSupportShowsUnavailableRatherThanMeasuredZero() throws {
        let summary = SamplingCoverageSummary(snapshot: try samplingSnapshot(supported: false))
        for id in [
            "sampling-rolling", "sampling-recent", "sampling-arrivals", "sampling-rolling-support",
            "sampling-recent-support",
        ] {
            #expect(summary.metrics.first { $0.id == id }?.value == "—")
        }
    }

    @Test func retainedRecentDetailsUseTheirOwnAcquisitionRange() throws {
        let snapshot = try samplingSnapshot()
        var sampling = SamplingCoverage()
        sampling.setLatest(
            SamplingDecision(requestedSeconds: 1, baseSeconds: 1, maximumSeconds: 1))
        var recent = AcquisitionCoverage()
        recent.append(
            AcquisitionTiming(
                runID: UUID(), scanSequence: 1, qualityOfService: .userInitiated,
                requestedPeriodSeconds: 1, achievedPeriodSeconds: 1.2, scanWorkSeconds: 0,
                resolutionDelaySeconds: 0, sampling: sampling))
        let summary = SamplingCoverageSummary(snapshot: snapshot, recentDuration: 10, acquisition: recent)
        #expect(summary.metrics.first { $0.id == "gap" }?.value == "1200.00 / 1000.00 ms")
        #expect(summary.metrics.first { $0.id == "sampling-mode" }?.value == "Maximum interval")
        #expect(summary.scanLabel == "1 scan · 10.00 s recent")
    }

    @Test func strictSchemaDeclaresSamplingObjectsAndEveryWireField() throws {
        let snapshot = try samplingSnapshot()
        let record = try JSONReport.encodeLine(snapshot)
        let json = try #require(JSONSerialization.jsonObject(with: record) as? [String: Any])
        let window = try #require(json["window"] as? [String: Any])
        let coverage = try #require(window["acquisitionCoverage"] as? [String: Any])
        let sampling = try #require(coverage["sampling"] as? [String: Any])
        #expect(coverage["minimumRequestedPeriodSeconds"] as? Double == 0.1)
        #expect(coverage["maximumRequestedPeriodSeconds"] as? Double == 0.5)
        #expect(sampling["overrideActivations"] as? [String: Int] == ["recovery": 1])
        #expect(sampling["overrideSeconds"] as? [String: Double] == ["recovery": 0.5])
        #expect(sampling["policyChangeCount"] as? Int == 2)
        let schema = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
        let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
        for name in ["acquisitionCoverage", "acquisitionTiming", "samplingCoverage", "samplingDecision"] {
            let definition = try #require(definitions[name])
            #expect(definition["additionalProperties"] as? Bool == false)
            let properties = try #require(definition["properties"] as? [String: Any])
            if name == "acquisitionCoverage" || name == "acquisitionTiming" {
                let reference = try #require(properties["sampling"] as? [String: String])
                #expect(reference["$ref"] == "#/$defs/samplingCoverage")
                #expect((definition["required"] as? [String])?.contains("sampling") == true)
            }
        }
        let decision = try #require(sampling["latest"] as? [String: Any])
        let definition = try #require(definitions["samplingDecision"])
        let properties = try #require(definition["properties"] as? [String: Any])
        #expect(Set(decision.keys) == Set(properties.keys))
        #expect(Set(definition["required"] as? [String] ?? []) == Set(properties.keys))
        if let path = ProcessInfo.processInfo.environment["JSON_SAMPLING_FIXTURE_PATH"] {
            try record.write(to: URL(fileURLWithPath: path))
        }
    }
}

private func samplingSnapshot(supported: Bool = true) throws -> MonitoringSnapshot {
    var ledger = CounterLedger()
    let baseline = ledger.ingest([], listedAt: 0)
    let scan = ledger.ingest([], listedAt: 0.6)
    let decision = SamplingDecision(
        mode: .adaptive, requestedSeconds: 0.1, baseSeconds: 0.3,
        minimumSeconds: 0.1, maximumSeconds: 0.5, rollingCPURate: 0.004,
        youngCPURate: 0.002, arrivalRate: 0.1, rollingSpanSeconds: supported ? 12.5 : 0,
        recentCPURate: 0.02, recentSpanSeconds: supported ? 1.25 : 0, overrides: [.recovery])
    var sampling = SamplingCoverage()
    var previous = decision
    previous.requestedSeconds = 0.5
    previous.baseSeconds = 0.5
    previous.overrides = []
    sampling.append(previous, duration: 0.1, activations: [], policyChanges: 0)
    sampling.append(decision, duration: 0.5, activations: [.recovery], policyChanges: 2)
    var window = AccountingWindow(baseline: baseline)
    let timing = AcquisitionTiming(
        runID: scan.id.runID, scanSequence: scan.id.sequence, qualityOfService: .userInitiated,
        requestedPeriodSeconds: 0.5, achievedPeriodSeconds: 0.6, scanWorkSeconds: 0,
        resolutionDelaySeconds: 0, sampling: sampling)
    try window.append(scan, rows: [], timing: timing)
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil, acquisition: timing),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1,
        cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 0,
        unreadableProcessCount: 0, findings: [], window: window.summary)
}
