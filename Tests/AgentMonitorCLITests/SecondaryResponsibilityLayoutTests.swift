import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct SecondaryResponsibilityLayoutTests {
    private let sessions = [
        "abcdabcd-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "12345678-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ]
    private let directories = ["/work/alpha/project", "/tmp/alpha/project"]

    private func snapshot(
        missingReadings: Bool = false, historical: Bool = false, mixedDirectories: Bool = false,
        highReadings: Bool = false
    ) -> MonitoringSnapshot {
        let rows = (0..<4).map { index in
            let group = index / 2
            return HeavyProcess(
                process: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1),
                executable: index.isMultiple(of: 2) ? "/bin/java" : "/bin/rustc",
                name: historical
                    ? "rust-analyzer-proc-macro-srv" : (index.isMultiple(of: 2) ? "java" : "rustc"),
                cpuPercent: highReadings
                    ? 999.9 : index.isMultiple(of: 2) ? (group == 0 ? 90 : 80) : (missingReadings ? nil : 0),
                footprintBytes: highReadings
                    ? 99_990_000_000 : index.isMultiple(of: 2) ? 320_000_000 : (missingReadings ? nil : 0),
                cwd: directories[mixedDirectories ? index % 2 : group], command: nil,
                metadataStatus: .markerRead,
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

    @Test(arguments: [60, 85, 120, 160])
    func groupedChildrenKeepTheirOwnDirectoryBesideResources(width: Int) throws {
        var state = LiveReportState(grouping: .session)
        let report = snapshot(mixedDirectories: true)
        state.receive(report)
        state.overview.enabled = false
        for group in state.groups {
            state.select(.group(group.id))
            state.setDisclosure(expanded: true)
        }
        for process in report.findings {
            state.select(.process(process.process))
            let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
            let selected = lines.filter { $0.style == .selected }
            try #require(!selected.isEmpty)
            let row = ReportLine(selected.map(\.text).joined(separator: " "))
            #expect(row.text.contains(process.observedName))
            #expect(
                row.text.contains(
                    process.process.pid.isMultiple(of: 2) ? "/tmp/alpha/project" : "/work/alpha/project"))
            #expect(
                row.text.contains(
                    process.process.pid.isMultiple(of: 2)
                        ? "0.00" : (process.process.pid == 1 ? "90.00" : "80.00")))
            #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
        }
    }

    @Test(arguments: [60, 85, 120])
    func groupedLongNamesRetainDirectoryAndExplicitTruncation(width: Int) throws {
        var state = LiveReportState(grouping: .session)
        let report = snapshot(historical: true, mixedDirectories: true)
        state.receive(report)
        state.overview.enabled = false
        for group in state.groups {
            state.select(.group(group.id))
            state.setDisclosure(expanded: true)
        }
        for process in report.findings {
            state.select(.process(process.process))
            let selected = LiveReportLayout.lines(state: state, width: width, height: 24)
                .filter { $0.style == .selected }
            try #require(!selected.isEmpty)
            let row = ReportLine(selected.map(\.text).joined(separator: " "))
            #expect(row.text.contains("[past]"))
            #expect(row.text.contains("rust"))
            #expect(row.text.contains(process.process.pid.isMultiple(of: 2) ? "/tmp" : "/work"))
            if !row.text.contains(process.observedName) { #expect(row.text.contains("…")) }
            #expect(selected.allSatisfy { TerminalCells.width($0.text) <= width })
        }
    }

    @Test func scrolledGroupedChildKeepsSessionWhenItsHeadingDoesNotFit() throws {
        var state = LiveReportState(grouping: .session)
        let report = snapshot(mixedDirectories: true)
        state.receive(report)
        state.overview.enabled = false
        for group in state.groups {
            state.select(.group(group.id))
            state.setDisclosure(expanded: true)
        }
        let process = try #require(report.findings.last)
        state.select(.process(process.process))
        let lines = LiveReportLayout.lines(state: state, width: 60, height: 12)
        let selected = lines.filter { $0.style == .selected }.map(\.text).joined(separator: " ")
        #expect(selected.contains("claude/12345678"))
        #expect(selected.contains("rustc"))
        #expect(selected.contains("/tmp/alpha/project"))
        #expect(selected.contains("0.00"))
        #expect(!lines.contains { $0.text.contains("▾") })
    }

    @Test(arguments: [60, 85, 120, 160], [ReportGrouping.none, .session])
    func groupControlsLeadRowsAndHeadersRemainDistinct(width: Int, grouping: ReportGrouping) throws {
        var state = LiveReportState(grouping: grouping)
        state.receive(snapshot())
        let group = try #require(state.groups.first)
        if grouping == .none { state.togglePin(.group(group.id)) }
        state.select(.group(group.id))
        var lines = LiveReportLayout.lines(state: state, width: width, height: 30)
        let closed = try #require(lines.first { $0.text.contains("▸") })
        #expect(closed.text.dropFirst(2).hasPrefix("▸ "))
        state.setChildDisclosure(expanded: true)
        state.select(.process(try #require(group.processes.first).process))
        lines = LiveReportLayout.lines(state: state, width: width, height: 30)
        let parent = try #require(lines.first { $0.text.contains("▾") })
        #expect(parent.text.dropFirst(2).hasPrefix("▾ "))
        #expect(parent.style == .heading)
        let header = try #require(lines.first { $0.text.contains("CPU%") })
        #expect(header.style == .muted)
        if width >= 85 {
            let child = try #require(lines.first { $0.style == .selected })
            let parentCPU = try #require(parent.text.range(of: "90.00"))
            let childCPU = try #require(child.text.range(of: "90.00"))
            #expect(
                parent.text.distance(from: parent.text.startIndex, to: parentCPU.lowerBound)
                    == child.text.distance(from: child.text.startIndex, to: childCPU.lowerBound))
        }
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test func pinnedGroupTotalsDetermineNumericColumnWidthsInFlatMode() throws {
        var state = LiveReportState(grouping: .none)
        state.receive(snapshot(highReadings: true))
        let group = try #require(state.groups.first)
        state.togglePin(.group(group.id))
        state.select(.group(group.id))
        state.setChildDisclosure(expanded: true)
        state.select(.process(try #require(group.processes.first).process))
        let lines = LiveReportLayout.lines(state: state, width: 120, height: 30)
        let parent = try #require(lines.first { $0.text.contains("▾") }).text
        let child = try #require(lines.first { $0.style == .selected }).text
        for (total, individual) in [("1999.80", "999.90"), ("199.98", "99.99")] {
            let parentValue = try #require(parent.range(of: total))
            let childValue = try #require(child.range(of: individual))
            #expect(
                parent.distance(from: parent.startIndex, to: parentValue.upperBound)
                    == child.distance(from: child.startIndex, to: childValue.upperBound))
        }
    }

    @Test(arguments: [60, 85, 120, 160], [ReportGrouping.none, .session])
    func processLeavesAdvertiseInspectionWithoutChildDisclosure(width: Int, grouping: ReportGrouping) throws {
        var state = LiveReportState(grouping: grouping)
        let report = snapshot()
        state.receive(report)
        for group in state.groups { state.setSessionDisclosure(expanded: true, from: .group(group.id)) }
        let process = try #require(report.findings.first)
        state.select(.process(process.process))
        let lines = LiveReportLayout.lines(state: state, width: width, height: 30)
        let selected = try #require(lines.first { $0.style == .selected })
        #expect(selected.text.hasPrefix("> i "))
        #expect(!selected.text.contains("▸"))
        #expect(!selected.text.contains("▾"))
        if width >= 85 {
            let header = try #require(lines.first { $0.text.contains("CPU%") })
            let heading = try #require(header.text.range(of: "CPU%"))
            let value = try #require(selected.text.range(of: "90.00"))
            #expect(
                TerminalCells.width(String(header.text[..<heading.upperBound]))
                    == TerminalCells.width(String(selected.text[..<value.upperBound])))
        }
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test func sessionInspectorDoesNotTeachLeafExpansion() throws {
        var state = LiveReportState(grouping: .session)
        state.receive(snapshot())
        state.select(.group(try #require(state.groups.first).id))
        state.toggleDetails()
        let text = LiveReportLayout.lines(state: state, width: 120, height: 40)
            .map(\.text).joined(separator: "\n")
        #expect(text.contains("i shows/hides details"))
        #expect(!text.contains("→ opens its details"))
    }

    @Test func processDirectoryLabelsDoNotBorrowRuntimeOrSiblingDirectories() {
        func row(_ pid: Int32, cwd: String?, shared: Bool = false) -> HeavyProcess {
            let identity = ProcessIdentity(pid: pid, startMicroseconds: 1)
            return HeavyProcess(
                process: identity, executable: "/bin/codex", name: "codex", cpuPercent: 10,
                footprintBytes: 1_000, cwd: cwd, command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: shared ? .ambiguous : .marker, context: .unverified,
                    threadID: shared ? nil : sessions[0], rootSessionID: nil,
                    runtime: shared ? identity : nil, terminal: nil, runtimeDirectory: "/runtime/only",
                    candidateThreadIDs: shared ? [sessions[0], sessions[1]] : [], ancestry: []))
        }
        let missing = row(1, cwd: nil)
        let shared = row(2, cwd: "/runtime/only", shared: true)
        let worker = row(3, cwd: "/work/api")
        let labels = ProcessDirectoryLabels([missing, shared, worker])
        #expect(labels.label(for: missing) == "CWD unavailable")
        #expect(labels.label(for: shared) == "Shared runtime")
        #expect(labels.label(for: worker) == "/work/api")
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
