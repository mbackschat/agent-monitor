import Testing

@testable import AgentMonitorCore

@Suite struct ProcessorTopologyTests {
    @Test(arguments: [nil, -1, 0, 65])
    func invalidLevelCountFallsBackWithoutEnumerating(count: Int?) {
        let result = ProcessorTopology.read(
            integer: { $0 == "hw.nperflevels" ? count : 8 },
            string: { _ in
                Issue.record("Invalid level count must not enumerate names")
                return "Performance"
            }, fallback: 2)
        #expect(result.logicalCPUCount == 8)
        #expect(result.performanceCPUCount == nil)
    }

    @Test(arguments: [false, true])
    func systemReaderUsesMaximumCountsAndRejectsPartialTopology(missing: Bool) {
        let integers = [
            "hw.logicalcpu_max": 12, "hw.nperflevels": 3,
            "hw.perflevel0.logicalcpu_max": 2, "hw.perflevel1.logicalcpu_max": 4,
            "hw.perflevel2.logicalcpu_max": 6,
        ]
        let names = [
            "hw.perflevel0.name": "Super", "hw.perflevel1.name": "Performance",
            "hw.perflevel2.name": "Efficiency",
        ]
        let result = ProcessorTopology.read(
            integer: { integers[$0] },
            string: {
                missing && $0 == "hw.perflevel1.name" ? nil : names[$0]
            }, fallback: 1)
        #expect(result.logicalCPUCount == 12)
        #expect(result.performanceCPUCount == (missing ? nil : 6))
        let unavailable = ProcessorTopology.read(integer: { _ in nil }, string: { _ in nil }, fallback: 8)
        #expect(unavailable == ProcessorTopology(logicalCPUCount: 8))
    }

    @Test(arguments: [
        (
            [
                ProcessorTopology.Level(name: "Performance", logicalCPUCount: 4),
                .init(name: "Efficiency", logicalCPUCount: 4),
            ], 8, 4
        ),
        (
            [
                .init(name: "Efficiency", logicalCPUCount: 6),
                .init(name: "Super", logicalCPUCount: 2), .init(name: "Performance", logicalCPUCount: 4),
            ], 12, 6
        ),
        (
            [.init(name: "Super", logicalCPUCount: 6), .init(name: "Performance", logicalCPUCount: 12)], 18,
            18
        ),
    ])
    func namesDeterminePerformancePopulation(levels: [ProcessorTopology.Level], total: Int, expected: Int) {
        #expect(ProcessorTopology(logicalCPUCount: total, levels: levels).performanceCPUCount == expected)
    }

    @Test(
        arguments: [
            [], [.init(name: "Standard", logicalCPUCount: 8)],
            [.init(name: "Future", logicalCPUCount: 4), .init(name: "Performance", logicalCPUCount: 4)],
            [.init(name: "Performance", logicalCPUCount: 4)],
            [.init(name: "Performance", logicalCPUCount: 0), .init(name: "Efficiency", logicalCPUCount: 8)],
            [.init(name: "Performance", logicalCPUCount: -1), .init(name: "Efficiency", logicalCPUCount: 9)],
            [.init(name: "Performance", logicalCPUCount: Int.max)],
            [.init(name: "Efficiency", logicalCPUCount: 8)],
        ] as [[ProcessorTopology.Level]])
    func incompleteOrUnknownTopologyDoesNotGuess(levels: [ProcessorTopology.Level]) {
        #expect(ProcessorTopology(logicalCPUCount: 8, levels: levels).performanceCPUCount == nil)
    }
}
