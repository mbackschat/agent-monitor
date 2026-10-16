import Foundation
import SwiftTUIViews
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorPresentation

@Suite struct TerminalCellLayoutTests {
    @Test(arguments: ["👩‍💻", "می\u{200C}روم", "क्\u{200D}ष"])
    func displaySanitizationPreservesShapingJoiners(text: String) {
        let line = ReportLine(text)
        #expect(line.text == text)
        #expect(TerminalCells.width(line.text) == cells(text))
        #expect(ReportTable.pad(text, to: 12).hasPrefix(text))
    }

    @Test(arguments: ["\u{202E}", "\u{2066}", "\u{200B}", "\u{009B}", "\u{001B}"])
    func displaySanitizationStillNeutralizesOtherControls(control: String) {
        #expect(ReportLine("a" + control + "b").text == "a�b")
    }

    @Test(arguments: [
        "", "ASCII", "编译器", "ＡＢＣ", "e\u{301}", "\u{301}", "👍🏽", "👩‍💻", "🇩🇪", "1️⃣",
        "©", "©️", "©︎", "─…←", "\u{200D}", "\u{20000}",
    ]) func widthsMatchPinnedRenderer(text: String) {
        #expect(TerminalCells.width(text) == cells(text))
    }

    @Test func clippingPreservesWholeGraphemesAndHandlesNarrowWidths() {
        #expect(TerminalCells.clipped("A编B", to: 2) == "A")
        #expect(TerminalCells.padded("A编B", to: 2) == "A ")
        #expect(TerminalCells.clipped("e\u{301}x", to: 1) == "e\u{301}")
        #expect(TerminalCells.wrapped("编译", to: 1) == ["�", "�"])
        #expect(TerminalCells.wrapped("编译", to: 0).isEmpty)
        #expect(TerminalCells.clipped("worker", to: -1).isEmpty)
    }

    @Test(arguments: ["编译器", "🦀🔧", "e\u{301}cole", "ＡＢＣ", "👍🏽"])
    func tablePaddingUsesRendererCells(name: String) {
        let padded = ReportTable.pad(name, to: 8)
        #expect(cells(padded) == 8)
        #expect(padded.hasPrefix(name))
        #expect(cells(ReportTable.pad(name, to: 3)) == 3)
    }

    @Test(arguments: [40, 60, 85, 120])
    func rowsFitCellsAndAlignFollowingColumns(width: Int) throws {
        var state = LiveReportState()
        state.receive(snapshot())
        let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
        #expect(lines.allSatisfy { cells($0.text) <= width })
        guard width >= 60 else { return }
        let header = try #require(lines.first { $0.text.contains("AGENT / SESSION") })
        let column = try #require(header.text.range(of: "AGENT / SESSION"))
        let expected = cells(String(header.text[..<column.lowerBound]))
        for line in lines where line.text.contains("codex/") {
            let start = try #require(line.text.range(of: "codex/"))
            #expect(cells(String(line.text[..<start.lowerBound])) == expected)
        }
    }

    @Test func detailsWrapWithoutLosingWideCharacters() {
        var state = LiveReportState()
        state.receive(snapshot())
        state.setDisclosure(expanded: true)
        state.maximizeDetails()
        let lines = LiveReportLayout.lines(state: state, width: 40, height: 60)
        #expect(lines.allSatisfy { cells($0.text) <= 40 })
        #expect(lines.map(\.text).joined().contains("/" + String(repeating: "编译", count: 35)))
    }

    private func cells(_ value: String) -> Int { layoutText(for: value, width: nil).size.width }

    private func snapshot() -> MonitoringSnapshot {
        let rows = ["编译器", "worker", "👩‍💻", "می\u{200C}روم", String(repeating: "🔧", count: 50)]
            .enumerated().map { index, name in
                let identity = ProcessIdentity(pid: Int32(40 + index), startMicroseconds: 1)
                return HeavyProcess(
                    process: identity, executable: "/" + String(repeating: "编译", count: 35), name: name,
                    cpuPercent: 50, footprintBytes: 1, cwd: "/项目", command: nil,
                    metadataStatus: .notObserved,
                    attribution: Attribution(
                        provider: .codex, evidence: .unknown, context: .unverified,
                        threadID: nil, rootSessionID: nil, runtime: nil, terminal: nil,
                        runtimeDirectory: nil, candidateThreadIDs: [], ancestry: [identity]))
            }
        return MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 150,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
            sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows)
    }
}
