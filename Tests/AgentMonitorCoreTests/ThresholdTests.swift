import AgentMonitorCore
import Testing

@Test func zeroDisablesEachResourceFilterIndependently() {
    let cpu = Thresholds(cpuPercent: 25)
    #expect(!cpu.includes(cpu: 10, footprint: 2_000_000_000))
    #expect(!cpu.includes(cpu: nil, footprint: 2_000_000_000))
    #expect(!cpu.includes(cpu: 25, footprint: nil))
    #expect(cpu.includes(cpu: 26, footprint: nil))
    let memory = Thresholds(memoryBytes: 1_000_000_000)
    #expect(!memory.includes(cpu: 100, footprint: 100))
    #expect(!memory.includes(cpu: 100, footprint: nil))
    #expect(!memory.includes(cpu: nil, footprint: 1_000_000_000))
    #expect(memory.includes(cpu: nil, footprint: 1_000_000_001))
    #expect(Thresholds().includes(cpu: nil, footprint: nil))
    #expect(Thresholds().includes(cpu: 0, footprint: 0))
    #expect(Thresholds.heavy.includes(cpu: 26, footprint: 100))
    #expect(Thresholds.heavy.includes(cpu: 0, footprint: 2_000_000_000))
    #expect(!Thresholds.heavy.includes(cpu: 0, footprint: 100))
}
