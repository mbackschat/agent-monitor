import AgentMonitorPresentation
import Foundation
import Testing

@testable import monitor_preview

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
    var state = try Preview.state()
    if grouped { state.toggleGrouping() }
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    #expect(lines.count == 24)
    #expect(lines.allSatisfy { $0.text.count <= width })
    #expect(lines.contains { $0.text.contains("q/Ctrl-C quit") })
    #expect(lines.contains { $0.text.contains("CPU > 25.00% OR GB > 1.00") })
    let svg = Preview.svg(lines: lines, width: width, height: 24)
    #expect(svg.contains("SYNTHETIC DATA"))
    #expect(!svg.contains("/Users/"))
}
