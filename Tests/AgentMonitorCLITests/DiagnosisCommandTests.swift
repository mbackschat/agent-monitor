import AgentMonitorCore
import AgentMonitorPresentation
import ArgumentParser
import Foundation
import Synchronization
import Testing

@testable import AgentMonitor

@Suite struct DiagnosisCommandTests {
    @Test func parserExposesOnlyApprovedDiagnosisFormsAndLocalGuides() throws {
        for arguments in [
            ["diagnose", "cpu"], ["diagnose", "cpu", "--json"], ["diagnose", "cpu", "--json-schema"],
        ] {
            let command = try #require(AgentMonitorCommand.parseAsRoot(arguments) as? DiagnoseCPUCommand)
            #expect(command.json == arguments.contains("--json"))
            #expect(command.jsonSchema == arguments.contains("--json-schema"))
        }
        for topic in [nil] + AgentGuide.Topic.allCases.map(Optional.some) {
            let arguments = ["guide"] + (topic.map { [$0.rawValue] } ?? [])
            let command = try #require(AgentMonitorCommand.parseAsRoot(arguments) as? GuideCommand)
            #expect(command.rendered == AgentGuide.render(topic))
        }
    }

    @Test(arguments: [
        ["diagnose", "cpu", "--interval", "2"], ["diagnose", "cpu", "--samples", "4"],
        ["diagnose", "cpu", "--cpu", "0"], ["diagnose", "cpu", "--json", "--json-schema"],
        ["diagnose", "cpu", "--cpu", "25"], ["--interval", "2", "diagnose", "cpu"],
        ["guide", "--json"], ["diagnose", "memory"], ["guide", "unknown"], ["guide", "semantics", "extra"],
    ]) func invalidUsageRemainsExit64(arguments: [String]) {
        do {
            _ = try AgentMonitorCommand.parseAsRoot(arguments)
            Issue.record("Expected invalid usage")
        } catch { #expect(AgentMonitorCommand.exitCode(for: error).rawValue == 64) }
    }

    @Test func helpLeadsWithDiagnosisAndMovesExhaustiveKeysToGuide() {
        let help = AgentMonitorCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(
            separator: " ")
        #expect(help.contains("agent-monitor diagnose cpu --json"))
        #expect(help.contains("agent-monitor guide"))
        #expect(!help.contains("1/2 lower/raise"))
        #expect(AgentGuide.render(.tui).contains("1/2 lower/raise CPU by 10 percentage points"))
        #expect(AgentGuide.render(.tui).contains("3/4 lower/raise footprint by 1 GB"))
        #expect(help.count < 4000)
    }

    @Test(arguments: [false, true]) func successWritesOneCompleteResponseAndNoStderr(json: Bool) async throws
    {
        let stdout = Mutex(Data())
        let stderr = Mutex(Data())
        try await DiagnoseCPUCommand.execute(
            json: json, collect: { diagnosisPresentationFixture(empty: true) },
            output: { data in stdout.withLock { $0.append(data) } },
            error: { data in stderr.withLock { $0.append(data) } })
        let bytes = stdout.withLock { $0 }
        #expect(stderr.withLock { $0.isEmpty })
        if json {
            let value = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(value["schemaVersion"] as? Int == 1)
            #expect(bytes.filter { $0 == 10 }.count == 1)
            #expect(!String(decoding: bytes, as: UTF8.self).contains("guide"))
        } else {
            #expect(String(decoding: bytes, as: UTF8.self).contains("CPU diagnosis:"))
        }
    }

    @Test func collectionFailureHasNoStdoutAndExitsOneWithStableCode() async throws {
        let stdout = Mutex(Data())
        let stderr = Mutex(Data())
        do {
            try await DiagnoseCPUCommand.execute(
                json: true, collect: { throw CPUDiagnosisError.collectionFailed },
                output: { data in stdout.withLock { $0.append(data) } },
                error: { data in stderr.withLock { $0.append(data) } })
            Issue.record("Expected exit 1")
        } catch { #expect(AgentMonitorCommand.exitCode(for: error).rawValue == 1) }
        #expect(stdout.withLock { $0.isEmpty })
        #expect(
            String(decoding: stderr.withLock { $0 }, as: UTF8.self) == DiagnosisText.collectionFailure + "\n")
    }
}
