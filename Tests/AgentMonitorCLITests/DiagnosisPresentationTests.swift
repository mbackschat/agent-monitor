import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

func diagnosisPresentationFixture(
    empty: Bool = false, label: String = "/bin/compiler", available: Bool = false
) -> CPUDiagnosis {
    let start = Date(timeIntervalSince1970: 1_792_152_000)
    let first = ProcessSample(
        identity: ProcessIdentity(
            pid: 42001, startMicroseconds: available ? UInt64.max : 1_792_151_999_000_000), parentPID: 1,
        executable: label, name: "fallback", sampledAt: 3, cpuSeconds: 2.4, footprintBytes: nil)
    let second = ProcessSample(
        identity: ProcessIdentity(pid: 42002, startMicroseconds: 1_792_152_000_100_000), parentPID: 1,
        executable: "/bin/worker", name: "worker", sampledAt: 2, cpuSeconds: 1.5, footprintBytes: nil)
    return CPUDiagnosis(
        startedAt: start, endedAt: start.addingTimeInterval(3.2), elapsedSeconds: 3.2,
        maximumScanSeconds: 0.05,
        host: CPUWindowHost(
            meanBusyPercent: empty ? nil : 210, logicalCPUCount: 8, observedSeconds: empty ? 0 : 3.15,
            validIntervals: empty ? 0 : 3),
        cpuSeconds: empty ? nil : 3.9, windowCPUPercent: empty ? nil : 121.875,
        observedLifetimeCount: empty ? 0 : 3, measuredLifetimeCount: empty ? 0 : 2,
        unmeasuredObservationCount: empty ? 0 : 2, unreadableObservationCount: empty ? 0 : 1,
        omittedContributorCount: 0,
        contributors: empty
            ? []
            : [
                DiagnosisContributor(
                    sample: first, cpuSeconds: 2.4, observedSeconds: 3, validIntervals: 3,
                    meanCPUPercent: 80, peakCPUPercent: 100,
                    footprint: available ? DiagnosisFootprint(bytes: 123, sampledAt: start) : nil,
                    attribution: available
                        ? .available(
                            observedAt: start,
                            value: Attribution(
                                provider: .codex, evidence: .ambiguous, context: .terminal,
                                threadID: nil, rootSessionID: nil, runtime: first.identity,
                                terminal: "ttys001", runtimeDirectory: "/same",
                                candidateThreadIDs: [
                                    "11111111-1111-4111-8111-111111111111",
                                    "22222222-2222-4222-8222-222222222222",
                                ],
                                ancestry: [first.identity])) : .unavailable(.metadataUnavailable)),
                DiagnosisContributor(
                    sample: second, cpuSeconds: 1.5, observedSeconds: 2, validIntervals: 2,
                    meanCPUPercent: 75, peakCPUPercent: 100, footprint: nil,
                    attribution: .unavailable(.notObservedAtEnrichment)),
            ], providerLookups: available ? [DiagnosisLookup(provider: .claude, status: .failed)] : [])
}

@Suite struct DiagnosisPresentationTests {
    @Test func encodedExampleMatchesApprovedShapeAndExportsIndependentValidatorFixtures() throws {
        let data = try JSONDiagnosis.encode(diagnosisPresentationFixture())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Diagnosis/example.json")
        let example = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        for key in example.keys where key != "startedAt" && key != "endedAt" {
            #expect(
                NSDictionary(dictionary: [key: try #require(object[key])])
                    == NSDictionary(dictionary: [key: try #require(example[key])]))
        }
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(
            date.date(from: try #require(object["endedAt"] as? String))
                == diagnosisPresentationFixture().endedAt)
        #expect(!String(decoding: data, as: UTF8.self).contains("\u{1B}"))
        if let output = ProcessInfo.processInfo.environment["CPU_DIAGNOSIS_FIXTURE_PATH"] {
            var records = data
            records.append(10)
            records.append(try JSONDiagnosis.encode(diagnosisPresentationFixture(empty: true)))
            records.append(10)
            records.append(try JSONDiagnosis.encode(diagnosisPresentationFixture(available: true)))
            records.append(10)
            try records.write(to: URL(fileURLWithPath: output))
            try JSONDiagnosis.schema().write(to: URL(fileURLWithPath: output + ".schema.json"))
        }
    }

    @Test func availableEvidenceRetainsExactIdentitiesAndCandidateIDs() throws {
        let value = diagnosisPresentationFixture(available: true)
        let data = try JSONDiagnosis.encode(value)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(String(UInt64.max)))
        #expect(json.contains("11111111-1111-4111-8111-111111111111"))
        #expect(json.contains("22222222-2222-4222-8222-222222222222"))
        #expect(json.contains("\"footprint\":{\"bytes\":123"))
        #expect(DiagnosisText.render(value).contains("Candidate alternatives"))
    }

    @Test func unavailableFieldsAreOmittedAndEmptyDoesNotClaimIdle() throws {
        let data = try JSONDiagnosis.encode(diagnosisPresentationFixture(empty: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let measured = try #require(object["measured"] as? [String: Any])
        let host = try #require(object["host"] as? [String: Any])
        #expect(measured["cpuSeconds"] == nil)
        #expect(measured["windowCPUPercent"] == nil)
        #expect(host["meanBusyPercent"] == nil)
        let text = DiagnosisText.render(diagnosisPresentationFixture(empty: true))
        #expect(text.contains("No data"))
        #expect(!text.contains("host 0%"))
    }

    @Test func schemaReusesExactReportIdentityAndAttributionDefinitions() throws {
        let diagnosis = try #require(
            JSONSerialization.jsonObject(with: JSONDiagnosis.schema()) as? [String: Any])
        let report = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
        let definitions = try #require(diagnosis["$defs"] as? [String: Any])
        let reportDefinitions = try #require(report["$defs"] as? [String: Any])
        for key in ["processIdentity", "attribution"] {
            #expect(
                NSDictionary(dictionary: [key: try #require(definitions[key])])
                    == NSDictionary(dictionary: [key: try #require(reportDefinitions[key])]))
        }
        #expect(diagnosis["additionalProperties"] as? Bool == false)
    }

    @Test func labelsUseBasenameFallbackAndUnicodeScalarLimit() throws {
        for (path, expected, truncated) in [
            ("/bin/tool", "tool", false), ("", "fallback", false),
            (
                "/bin/" + String(repeating: "e\u{301}", count: 80), String(repeating: "e\u{301}", count: 60),
                true
            ),
        ] {
            let encoded = JSONDiagnosis(diagnosisPresentationFixture(label: path))
            #expect(encoded.contributors[0].label == expected)
            #expect(encoded.contributors[0].labelTruncated == truncated)
            #expect(encoded.contributors[0].process.startMicroseconds == 1_792_151_999_000_000)
        }
        let text = DiagnosisText.render(diagnosisPresentationFixture(label: "/bin/evil\u{1B}[31m\nname"))
        #expect(!text.contains("\u{1B}"))
        #expect(!text.contains("\nname"))
    }

    @Test func guidesAndTextShareEveryDiagnosticExplanation() {
        for code in DiagnosisDiagnostic.allCases {
            #expect(AgentGuide.render(.diagnostics).contains(code.rawValue))
            #expect(AgentGuide.render(.diagnostics).contains(code.explanation))
        }
        let result = diagnosisPresentationFixture()
        for code in result.diagnostics {
            #expect(DiagnosisText.render(result).contains(code.explanation))
        }
        for evidence in [
            "marker", "inheritedMarker", "writerLock", "sessionRegistry", "runtimeOnly", "ambiguous",
            "unknown",
        ] {
            #expect(AgentGuide.render(.semantics).contains(evidence))
        }
        #expect(AgentGuide.render().contains("agent-monitor diagnose cpu --json"))
        #expect(AgentGuide.render(.actions).contains("invocation"))
        #expect(AgentGuide.render(.tui).contains("1/2"))
        #expect(AgentGuide.render(.tui).contains("h"))
    }
}
