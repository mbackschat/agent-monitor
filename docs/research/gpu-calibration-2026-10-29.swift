import CoreFoundation
import Darwin
import Foundation
import IOKit
import Metal

enum Failure: Error { case invalid(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func emit(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
func checkpoint(_ label: String, _ fields: [String: Any] = [:]) throws {
    try emit(fields.merging(["label": label]) { _, new in new })
    try require(readLine() == "continue", "observer acknowledgement missing")
}
func integer(_ value: Any?) -> UInt64? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
        ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(String(cString: n.objCType))
    else { return nil }
    return UInt64(n.stringValue)
}
func checkedSum(_ values: [UInt64]) throws -> UInt64 {
    try values.reduce(0) { total, value in
        let (sum, overflow) = total.addingReportingOverflow(value)
        try require(!overflow, "counter overflow")
        return sum
    }
}
struct Birth: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    let uid: UInt32
}
func birth(_ pid: Int32) throws -> Birth {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    try require(proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, "birth read failed")
    try require(info.pbi_uid == getuid(), "wrong owner")
    return Birth(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec, uid: info.pbi_uid)
}
func property(_ entry: io_registry_entry_t, _ key: String) -> CFTypeRef? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}
func creatorPID(_ value: CFTypeRef?) -> Int32? {
    guard let text = value as? String, text.utf8.count < 1024 else { return nil }
    let tokens = text.split(separator: " ", maxSplits: 2)
    guard tokens.count >= 2, tokens[0] == "pid" else { return nil }
    return Int32(tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: ",")))
}
struct Reading {
    var clients: [UInt64: [UInt64]] = [:]
    var missingUsage = 0
    var fields = Set<String>()
}
func sample(_ pid: Int32, _ expected: Birth) throws -> Reading {
    try require(try birth(pid) == expected, "worker lifetime changed before read")
    var result = Reading()
    var roots: io_iterator_t = 0
    try require(IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &roots) == KERN_SUCCESS, "accelerator enumeration failed")
    defer { IOObjectRelease(roots) }
    var visits = 0
    while case let root = IOIteratorNext(roots), root != 0 {
        defer { IOObjectRelease(root) }
        var entries: io_iterator_t = 0
        try require(IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &entries) == KERN_SUCCESS, "registry traversal failed")
        defer { IOObjectRelease(entries) }
        while case let entry = IOIteratorNext(entries), entry != 0 {
            defer { IOObjectRelease(entry) }
            visits += 1
            try require(visits <= 100_000, "registry traversal bound")
            guard IOObjectConformsTo(entry, "AGXDeviceUserClient") != 0,
                creatorPID(property(entry, "IOUserClientCreator")) == pid else { continue }
            var id: UInt64 = 0
            try require(IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS, "registry ID unavailable")
            try require(result.clients[id] == nil && result.clients.count < 64, "duplicate client or client bound")
            var values: [UInt64] = []
            if let raw = property(entry, "AppUsage") {
                guard let records = raw as? [[String: Any]], records.count <= 128 else { throw Failure.invalid("invalid AppUsage") }
                for record in records {
                    try require(record.count <= 32, "record field bound")
                    result.fields.formUnion(record.keys)
                    guard record["API"] as? String == "Metal", let value = integer(record["accumulatedGPUTime"]) else { throw Failure.invalid("unsupported record") }
                    values.append(value)
                }
            } else { result.missingUsage += 1 }
            try require(creatorPID(property(entry, "IOUserClientCreator")) == pid, "creator changed within read")
            result.clients[id] = values
        }
        try require(IOIteratorIsValid(entries) != 0, "invalidated traversal")
    }
    try require(try birth(pid) == expected, "worker lifetime changed after read")
    return result
}
func observe() throws {
    guard let line = readLine(), let pid = Int32(line) else { throw Failure.invalid("missing worker PID") }
    let expected = try birth(pid)
    let start = ProcessInfo.processInfo.systemUptime
    var previous: Reading?
    var reads = 0
    try emit(["ready": true])
    while let label = readLine(), label != "quit" {
        reads += 1
        try require(reads <= 64 && label.utf8.count <= 128, "observation bound")
        let begin = ProcessInfo.processInfo.systemUptime
        let current = try sample(pid, expected)
        let end = ProcessInfo.processInfo.systemUptime
        let total = try checkedSum(current.clients.values.flatMap { $0 })
        var row: [String: Any] = ["label": label, "readStartSeconds": begin - start, "readEndSeconds": end - start,
            "clients": current.clients.count, "records": current.clients.values.reduce(0) { $0 + $1.count },
            "recordCountsPerClient": current.clients.values.map(\.count).sorted(), "aggregateRawCounter": total,
            "missingUsage": current.missingUsage, "fields": current.fields.sorted(), "lifetimeVerified": true]
        if let old = previous {
            let oldIDs = Set(old.clients.keys), newIDs = Set(current.clients.keys)
            let common = oldIDs.intersection(newIDs)
            row["newClients"] = newIDs.subtracting(oldIDs).count
            row["departedClients"] = oldIDs.subtracting(newIDs).count
            var decreases = 0, shapes = 0, changed = 0
            var deltas: [UInt64] = []
            for id in common {
                let before = try checkedSum(old.clients[id]!)
                let after = try checkedSum(current.clients[id]!)
                if after < before { decreases += 1 } else { deltas.append(after - before) }
                if old.clients[id]!.count != current.clients[id]!.count { shapes += 1 }
                if old.clients[id]! != current.clients[id]! { changed += 1 }
            }
            row["decreasedClientTotals"] = decreases
            row["changedRecordCounts"] = shapes
            row["changedRecordArrays"] = changed
            if decreases == 0 { row["matchedClientRawDelta"] = try checkedSum(deltas) }
        }
        previous = current
        try emit(row)
    }
}
func reference(_ input: UInt32) -> UInt32 {
    var x = input
    for _ in 0..<256 {
        x = (x &* 1_664_525) &+ 1_013_904_223
        x ^= x >> 13
    }
    return x
}
func worker() throws {
    try require(getuid() != 0 && geteuid() != 0, "worker must be unprivileged")
    try checkpoint("before_device")
    guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.invalid("no Metal device") }
    try checkpoint("after_device", ["device": device.name])
    let setupStart = ProcessInfo.processInfo.systemUptime
    let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void finite_work(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            uint x = values[i];
            for (uint j = 0; j < 256; ++j) {
                x = x * 1664525u + 1013904223u;
                x ^= x >> 13;
            }
            values[i] = x;
        }
        """
    let library = try device.makeLibrary(source: source, options: nil)
    guard let function = library.makeFunction(name: "finite_work"),
        let buffer = device.makeBuffer(length: 4096 * MemoryLayout<UInt32>.size, options: .storageModeShared)
    else { throw Failure.invalid("setup allocation failed") }
    let pipeline = try device.makeComputePipelineState(function: function)
    let input = (0..<4096).map { UInt32($0) ^ 0xA5A5_1234 }
    let expected = input.map(reference)
    let setupSeconds = ProcessInfo.processInfo.systemUptime - setupStart
    guard let queueA = device.makeCommandQueue() else { throw Failure.invalid("queue A failed") }
    try checkpoint("after_queue_a", ["setupSeconds": setupSeconds, "explicitDataBufferBytes": buffer.length])
    var lastEnd = 0.0
    func batch(_ queue: MTLCommandQueue, _ label: String) throws {
        try checkpoint("before_\(label)")
        let wallStart = ProcessInfo.processInfo.systemUptime
        var count = 0, invalidTimes = 0, overlaps = 0
        var elapsed = 0.0, union = 0.0, intervalEnd = 0.0
        while count < 128 && elapsed < 0.2 {
            try autoreleasepool {
                let values = buffer.contents().bindMemory(to: UInt32.self, capacity: 4096)
                for index in 0..<4096 { values[index] = input[index] }
                guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw Failure.invalid("command allocation failed") }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: 4096, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                try require(command.status == .completed && command.error == nil, "command failed")
                for index in 0..<4096 { try require(values[index] == expected[index], "output mismatch") }
                count += 1
                let begin = command.gpuStartTime, end = command.gpuEndTime
                if begin.isFinite && end.isFinite && begin > 0 && end > begin {
                    if begin < lastEnd { overlaps += 1 }
                    elapsed += end - begin
                    union += max(0, end - max(begin, intervalEnd))
                    intervalEnd = max(intervalEnd, end)
                    lastEnd = max(lastEnd, end)
                } else { invalidTimes += 1 }
            }
            if count == 1 { try checkpoint("first_\(label)") }
        }
        try checkpoint("after_\(label)", ["submissions": count, "invalidTimings": invalidTimes, "overlaps": overlaps,
            "metalElapsedSeconds": elapsed, "metalUnionSeconds": union, "batchWallSeconds": ProcessInfo.processInfo.systemUptime - wallStart,
            "outputsVerified": true])
    }
    try batch(queueA, "a1")
    try autoreleasepool {
        guard let queueB = device.makeCommandQueue() else { throw Failure.invalid("queue B failed") }
        try checkpoint("after_queue_b_before_work")
        try batch(queueB, "b")
    }
    try checkpoint("b_application_references_released")
    try batch(queueA, "a2")
    try checkpoint("before_cooldown")
    Thread.sleep(forTimeInterval: 1)
    try checkpoint("after_cooldown")
}
func selfTest() throws {
    try require(integer(NSNumber(value: true)) == nil, "bool accepted")
    try require(integer(NSNumber(value: -1)) == nil, "negative accepted")
    try require(integer(NSNumber(value: Double.nan)) == nil, "NaN accepted")
    try require(integer(NSNumber(value: 1.5)) == nil, "fraction accepted")
    try require(integer(NSNumber(value: UInt64.max)) == UInt64.max, "uint64 lost")
    try require(try checkedSum([1, 2]) == 3, "sum failed")
    do { _ = try checkedSum([UInt64.max, 1]); throw Failure.invalid("overflow accepted") }
    catch Failure.invalid("counter overflow") {}
    try require(reference(0) == 426546178, "independent reference mismatch")
    try emit(["offlineChecks": "passed"])
}
do {
    switch CommandLine.arguments.last {
    case "worker": try worker()
    case "observer": try observe()
    case "self-test": try selfTest()
    default: throw Failure.invalid("explicit mode required")
    }
} catch {
    FileHandle.standardError.write(Data("calibration failed: \(error)\n".utf8))
    exit(1)
}
