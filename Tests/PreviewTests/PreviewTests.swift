import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Synchronization
import Testing

@testable import monitor_preview

@Test(.timeLimit(.minutes(1))) func ledgerPreviewKeepsOwnershipAndHistoryWithDelayedMetadata() async throws {
    let held = DispatchSemaphore(value: 0)
    defer { held.signal() }
    let firstMetadata = Mutex(true)
    let started = DispatchSemaphore(value: 0)
    let snapshots = Mutex<[MonitoringSnapshot]>([])
    let delayed = try await Preview.ledgerState(
        beforeMetadata: {
            if firstMetadata.withLock({ value in
                defer { value = false }
                return value
            }) {
                started.signal()
                #expect(held.wait(timeout: .now() + 10) == .success)
            }
        },
        receive: { snapshot in
            if snapshots.withLock({ $0.isEmpty }) {
                #expect(started.wait(timeout: .now() + 5) == .success)
            }
            snapshots.withLock { $0.append(snapshot) }
            if snapshot.cpuAccounting.acquisition?.scanSequence == 12 { held.signal() }
        })
    let reports = snapshots.withLock { $0 }
    #expect(reports.compactMap { $0.cpuAccounting.acquisition?.scanSequence } == Array(1...12))
    let first = try #require(reports.first)
    #expect(first.observedFindings.count == 7)
    for index in 0..<7 {
        let row = try #require(first.observedFindings.first { $0.process.pid == Int32(42000 + index) })
        #expect(row.attribution.threadID == String(format: "%08d-1111-4111-8111-111111111111", index + 1))
    }
    let history = try #require(delayed.snapshot?.recentActivity)
    #expect(history.units.count == 12)
    #expect(history.startedAt == 0)
    #expect(history.endedAt == 12)
    let departed = history.units.flatMap(\.records).filter { $0.category.process.pid == 42006 }
    #expect(!history.present.contains { $0.pid == 42006 })
    #expect(departed.reduce(0) { $0 + $1.cpuSeconds } > 0)
    #expect(departed.allSatisfy { $0.category.owner.sessionID == "00000007-1111-4111-8111-111111111111" })
    let immediate = try await Preview.ledgerState()
    let delayedLines = LiveReportLayout.lines(state: delayed, width: 120, height: 32)
    let immediateLines = LiveReportLayout.lines(state: immediate, width: 120, height: 32)
    if let directory = ProcessInfo.processInfo.environment["TUI_GROUPED_PREVIEW_DIRECTORY"] {
        for page in [ReportReferencePage.keyboard, .glossary, .diagnostics] {
            var reference = immediate
            reference.showReference(page)
            try Preview.svg(
                lines: LiveReportLayout.lines(state: reference, width: 100, height: 46), width: 100,
                height: 46
            )
            .write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("reference-\(page).svg"),
                atomically: true, encoding: .utf8)
        }
    }

    #expect(
        Preview.svg(lines: delayedLines, width: 120, height: 32)
            == Preview.svg(lines: immediateLines, width: 120, height: 32))
}

@Test func previewAdvancesByWideGlyphCells() {
    let svg = Preview.svg(lines: [ReportLine("编译 x")], width: 40, height: 8)
    #expect(svg.contains("<tspan x=\"24\">编</tspan>"))
    #expect(svg.contains("<tspan x=\"42\">译</tspan>"))
    #expect(svg.contains("<tspan x=\"69\">x</tspan>"))
}

@Test(arguments: ["I   W", "PID      CPU%"])
func previewPositionsTerminalCellsWithoutStretchingGlyphs(text: String) {
    let svg = Preview.svg(lines: [ReportLine(text)], width: 40, height: 8)
    #expect(!svg.contains("textLength="))
    #expect(!svg.contains("lengthAdjust="))
    for (column, character) in text.enumerated() where character != " " {
        #expect(svg.contains("<tspan x=\"\(24 + column * 9)\">\(character)</tspan>"))
    }
    #expect(svg.contains("aria-label=\"\(text)\""))
}

@Test func previewEscapesRendererTextWithoutInterpretingMarkup() {
    let svg = Preview.svg(lines: [ReportLine("<worker> & \"args\"")], width: 40, height: 8)
    #expect(svg.contains("&lt;worker&gt; &amp; &quot;args&quot;"))
    #expect(!svg.contains("<worker>"))
}

@Test func previewCheckRejectsMissingAndStaleAssetsWithoutWriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let asset = directory.appendingPathComponent("preview.svg")
    #expect(throws: (any Error).self) { try Preview.check(at: asset, expected: "new") }
    #expect(!FileManager.default.fileExists(atPath: asset.path))
    try "old".write(to: asset, atomically: true, encoding: .utf8)
    #expect(throws: (any Error).self) { try Preview.check(at: asset, expected: "new") }
    #expect(try String(contentsOf: asset, encoding: .utf8) == "old")
    try Preview.check(at: asset, expected: "old")
}

@Test(arguments: [60, 85, 120, 160], [false, true])
func previewFixtureUsesProductionLayoutAcrossWidths(width: Int, grouped: Bool) throws {
    let state = try Preview.state(grouped: grouped)
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    #expect(lines.count == 24)
    #expect(lines.allSatisfy { $0.text.count <= width })
    #expect(lines.contains { $0.text.contains("q/Ctrl-C quit") })
    #expect(lines.contains { $0.text.contains("All observed processes") })
    let svg = Preview.svg(lines: lines, width: width, height: 24)
    #expect(svg.contains("SYNTHETIC DATA"))
    #expect(!svg.contains("/Users/"))
    if grouped, let directory = ProcessInfo.processInfo.environment["TUI_GROUPED_PREVIEW_DIRECTORY"] {
        try svg.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("grouped-\(width).svg"),
            atomically: true, encoding: .utf8)
        var details = state
        details.maximizeDetails()
        try Preview.svg(
            lines: LiveReportLayout.lines(state: details, width: width, height: 24), width: width, height: 24
        )
        .write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("details-\(width).svg"),
            atomically: true, encoding: .utf8)
    }
}
