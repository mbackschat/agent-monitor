import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Testing

private struct GroupingMeasurement: Codable {
    let processes: Int
    let groups: Int
    let repetitions: Int
    let doubleReadMedianMilliseconds: Double
    let singleReadMedianMilliseconds: Double
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUBAR_GROUPING_MEASUREMENT_PATH"] != nil))
func measureNativeGroupingProjection() throws {
    let path = try #require(ProcessInfo.processInfo.environment["MENUBAR_GROUPING_MEASUREMENT_PATH"])
    var measurements: [GroupingMeasurement] = []
    for count in [10, 100, 1000] {
        let findings = try (0..<count).flatMap { index in
            try menuBarFixture(
                pids: [Int32(42001 + index)],
                sessionID: String(format: "11111111-1111-4111-8111-%012d", index / 5)
            ).findings
        }
        var state = LiveReportState(grouping: .session)
        state.receive(
            MonitoringSnapshot(
                timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
                cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
                sampledProcessCount: count, unreadableProcessCount: 0, findings: findings))
        var doubleRead: [Double] = []
        var singleRead: [Double] = []
        for sample in 0..<5 {
            for repeated in sample.isMultiple(of: 2) ? [true, false] : [false, true] {
                let clock = ContinuousClock()
                let start = clock.now
                var checksum = 0
                for _ in 0..<100 {
                    checksum += groupingChecksum(state, repeated: repeated)
                }
                let duration = start.duration(to: clock.now).components
                let milliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
                #expect(checksum == count * 100)
                if repeated { doubleRead.append(milliseconds) } else { singleRead.append(milliseconds) }
            }
        }
        measurements.append(
            GroupingMeasurement(
                processes: count, groups: state.groups.count, repetitions: 100,
                doubleReadMedianMilliseconds: doubleRead.sorted()[2],
                singleReadMedianMilliseconds: singleRead.sorted()[2]))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(measurements).write(to: URL(fileURLWithPath: path))
}

@inline(never) private func groupingChecksum(_ state: LiveReportState, repeated: Bool) -> Int {
    if repeated {
        return state.groups.isEmpty ? 0 : state.groups.reduce(0) { $0 + $1.processes.count }
    }
    let groups = state.groups
    return groups.isEmpty ? 0 : groups.reduce(0) { $0 + $1.processes.count }
}
