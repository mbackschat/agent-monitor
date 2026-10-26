import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct SecondaryResponsibilityLayoutTests {
    private let sessions = [
        "abcdabcd-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "12345678-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ]
    private let directories = ["/work/alpha/project", "/tmp/alpha/project"]

    private func snapshot(missingReadings: Bool = false, historical: Bool = false) -> MonitoringSnapshot {
        let rows = (0..<4).map { index in
            let group = index / 2
            return HeavyProcess(
                process: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1),
                executable: index.isMultiple(of: 2) ? "/bin/java" : "/bin/rustc",
                name: historical
                    ? "rust-analyzer-proc-macro-srv" : (index.isMultiple(of: 2) ? "java" : "rustc"),
                cpuPercent: index.isMultiple(of: 2) ? (group == 0 ? 90 : 80) : (missingReadings ? nil : 0),
                footprintBytes: index.isMultiple(of: 2) ? 320_000_000 : (missingReadings ? nil : 0),
                cwd: directories[group], command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .claude, evidence: .marker, context: .terminal,
                    threadID: sessions[group], rootSessionID: nil, runtime: nil,
                    terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []),
                accounting: historical
                    ? ProcessWindowAccounting(
                        cpuSeconds: 1, recoveredCPUSeconds: 0, pointCandidateCPUSeconds: 1,
                        uncertainCPUSeconds: 0, isHistorical: true, lastObservedAt: 0,
                        lastObservedFootprintBytes: nil) : nil)
        }
        return MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 170,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: 1), intervalSeconds: 0.1,
            cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 4,
            unreadableProcessCount: 0, findings: rows)
    }

    @Test func groupHeadingsDisambiguateDirectoriesAcrossThePopulation() {
        let groups = SessionGrouping.groups(snapshot().observedFindings)
        #expect(groups.count == 2)
        for group in groups {
            let index = group.sessionID == sessions[0] ? 0 : 1
            #expect(group.project == directories[index])
            #expect(group.headingLabel.title.contains(directories[index]))
            #expect(group.cpuTotal == (index == 0 ? 90 : 80))
        }
    }

    @Test(arguments: [false, true], [0, 1])
    func narrowProcessViewKeepsSelectedIdentityResourcesAndDirectory(grouped: Bool, selected: Int) throws {
        var state = LiveReportState(grouping: grouped ? .session : .none)
        state.receive(snapshot())
        state.overview.enabled = false
        if grouped {
            state.select(.group(.session(provider: "claude", id: sessions[selected])))
        } else {
            state.select(.process(ProcessIdentity(pid: Int32(selected * 2 + 1), startMicroseconds: 1)))
        }
        let lines = LiveReportLayout.lines(state: state, width: 40, height: 12)
        let identity = try #require(lines.firstIndex { $0.text.contains(sessions[selected].prefix(8)) })
        #expect(lines[identity].style == .selected)
        #expect(lines[identity].text.contains("claude"))
        if !grouped { #expect(lines[identity].text.contains("java")) }
        #expect(identity + 1 < lines.count)
        let resources = lines[min(identity + 1, lines.count - 1)]
        #expect(resources.style == .selected)
        #expect(resources.text.contains(selected == 0 ? "90.00" : "80.00"))
        #expect(resources.text.contains("0.32"))
        #expect(resources.text.contains(selected == 0 ? "/work" : "/tmp"))
        #expect(lines.count <= 12)
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= 40 })
    }
    @Test(arguments: [12, 13, 14, 15])
    func narrowViewportNeverSeparatesIdentityFromResources(height: Int) {
        var state = LiveReportState(grouping: .session)
        state.receive(snapshot(missingReadings: true))
        state.overview.enabled = false
        state.select(.group(.session(provider: "claude", id: sessions[1])))
        state.togglePin(.group(.session(provider: "claude", id: sessions[1])))
        let lines = LiveReportLayout.lines(state: state, width: 40, height: height)
        for (index, line) in lines.enumerated()
        where sessions.contains(where: { line.text.contains($0.prefix(8)) }) {
            #expect(index + 1 < lines.count)
            let resources = lines[min(index + 1, lines.count - 1)]
            #expect(resources.text.contains("~"))
            #expect(resources.style == line.style)
            if line.style == .selected {
                #expect(line.text.hasPrefix("@"))
                #expect(resources.text.hasPrefix("@"))
            }
        }
        #expect(lines.filter { $0.style == .selected }.count == 2)
        #expect(lines.count <= height)
    }

    @Test func historicalMarkerPrecedesLongExecutableAndTruncationIsExplicit() throws {
        var state = LiveReportState(grouping: .none)
        state.receive(snapshot(historical: true))
        state.overview.enabled = false
        state.select(.process(ProcessIdentity(pid: 1, startMicroseconds: 1)))
        let lines = LiveReportLayout.lines(state: state, width: 40, height: 12)
        let selected = lines.filter { $0.style == .selected }
        #expect(selected.count == 2)
        let identity = try #require(selected.first)
        #expect(identity.text.contains("[past]"))
        #expect(identity.text.contains("abcdabcd"))
        #expect(identity.text.hasSuffix("…"))
    }

}
