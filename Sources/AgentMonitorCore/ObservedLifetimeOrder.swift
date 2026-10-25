/// Scan order supplies recency; only identities last observed in the same scan need sorting.
/// Shared by counter baselines and prompt discovery so churn never sorts the entire retained cache.
struct ObservedLifetimeOrder: Sendable {
    private struct Batch: Sendable {
        let sequence: UInt64
        var identities: [ProcessIdentity]
        var ordered = false
    }
    private var batches: [Batch] = []
    private var head = 0
    private(set) var retainedReferenceCount = 0
    private(set) var sortInputCount = 0
    var retainedIdentityCapacity: Int { batches.reduce(0) { $0 + $1.identities.capacity } }

    mutating func observe(_ identities: [ProcessIdentity], sequence: UInt64) {
        guard !identities.isEmpty else { return }
        batches.append(Batch(sequence: sequence, identities: identities))
        retainedReferenceCount += identities.count
    }

    mutating func oldest(lastSeen: (ProcessIdentity) -> UInt64?) -> ProcessIdentity? {
        while head < batches.count {
            let sequence = batches[head].sequence
            if !batches[head].ordered {
                discardStaleReferences(at: head, lastSeen: lastSeen)
                sortInputCount += batches[head].identities.count
                batches[head].identities.sort {
                    if $0.pid != $1.pid { return $0.pid > $1.pid }
                    return $0.startMicroseconds > $1.startMicroseconds
                }
                batches[head].ordered = true
            }
            guard let identity = batches[head].identities.popLast() else {
                head += 1
                continue
            }
            retainedReferenceCount -= 1
            if batches[head].identities.isEmpty { batches[head].identities = [] }
            if lastSeen(identity) == sequence { return identity }
        }
        return nil
    }

    mutating func trim(capacity: Int, lastSeen: (ProcessIdentity) -> UInt64?) {
        // An old missing lifetime can pin the head forever. Linear pruning bounds lazy
        // references to twice the cache cap (BaselineEvictionTests' long-missing guard).
        guard retainedReferenceCount > capacity * 2 || head > 64 else { return }
        for index in head..<batches.count { discardStaleReferences(at: index, lastSeen: lastSeen) }
        batches.removeFirst(head)
        batches.removeAll { $0.identities.isEmpty }
        head = 0
    }

    private mutating func discardStaleReferences(
        at index: Int, lastSeen: (ProcessIdentity) -> UInt64?
    ) {
        let sequence = batches[index].sequence
        let previous = batches[index].identities.count
        batches[index].identities.removeAll { lastSeen($0) != sequence }
        let count = batches[index].identities.count
        retainedReferenceCount -= previous - count
        // removeAll(where:) retains the full scan buffer even when only a few departed
        // lifetimes survive. LifetimeOrderStorageTests bounds allocation, not just count.
        if count == 0 {
            batches[index].identities = []
        } else if batches[index].identities.capacity > count * 2 {
            var compacted: [ProcessIdentity] = []
            compacted.reserveCapacity(count)
            compacted.append(contentsOf: batches[index].identities)
            batches[index].identities = compacted
        }
    }
}
