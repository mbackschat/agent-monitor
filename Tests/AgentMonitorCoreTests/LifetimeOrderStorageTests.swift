import Testing

@testable import AgentMonitorCore

@Suite struct LifetimeOrderStorageTests {
    @Test(arguments: [128, 8192])
    func sparseBatchesReleaseTheirOriginalPopulationBuffers(limit: Int) {
        let population = limit == 128 ? 100 : 650
        let scans = limit == 128 ? 500 : 5000
        var order = ObservedLifetimeOrder()
        var seen: [ProcessIdentity: UInt64] = [:]
        var maximumCapacity = 0
        for scan in 0..<scans {
            let sequence = UInt64(scan)
            let identities =
                (1...population).map { ProcessIdentity(pid: Int32($0), startMicroseconds: 1) }
                + (0..<2).map { ProcessIdentity(pid: Int32(1000 + scan * 2 + $0), startMicroseconds: 1) }
            for identity in identities { seen[identity] = sequence }
            order.observe(identities, sequence: sequence)
            while seen.count > limit {
                guard let oldest = order.oldest(lastSeen: { seen[$0] }) else {
                    Issue.record("An overfull lifetime cache must have an eviction candidate")
                    return
                }
                seen[oldest] = nil
            }
            order.trim(capacity: limit, lastSeen: { seen[$0] })
            #expect(order.retainedReferenceCount <= limit * 2)
            maximumCapacity = max(maximumCapacity, order.retainedIdentityCapacity)
        }
        #expect(maximumCapacity <= limit * 4)
        #expect(seen.count == limit)
    }
}
