import CoreFoundation
import Darwin
import Foundation
import IOKit
import Metal
import Synchronization

enum Failure: Error {
    case invalid(String)
    case bound(String)
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func bounded(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.bound(message) }
}
enum Mode: Equatable {
    case preflight, worker, observer
    static func parse(_ arguments: [String], authorized: Bool) throws -> Mode {
        switch arguments {
        case [], ["--self-test"]: return .preflight
        case ["--authorized-worker"] where authorized: return .worker
        case ["--authorized-observer"] where authorized: return .observer
        default: throw Failure.invalid("explicit authorized mode required")
        }
    }
}
func emit(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try bounded(data.count <= 1_048_576, "output line cap")
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
func checkedSum(_ values: [UInt64]) throws -> UInt64 {
    try values.reduce(0) { total, value in
        let (sum, overflow) = total.addingReportingOverflow(value)
        try require(!overflow, "counter overflow")
        return sum
    }
}
struct NumberReading {
    let json: [String: Any]
    let integer: UInt64?
    let available: Bool
}
func number(_ value: Any?, integerRequired: Bool) -> NumberReading {
    guard let value else {
        return NumberReading(json: ["status": "unavailable", "reason": "missing"], integer: nil, available: false)
    }
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {
        return NumberReading(json: ["status": "unavailable", "reason": "not_numeric_or_boolean"], integer: nil, available: false)
    }
    let encoding = String(cString: n.objCType)
    var row: [String: Any] = ["objcType": encoding]
    if ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(encoding) {
        row["decimal"] = n.stringValue
        if let exact = UInt64(n.stringValue) {
            row["status"] = "available"
            return NumberReading(json: row, integer: exact, available: true)
        }
        row["reason"] = "negative_or_out_of_uint64_range"
    } else if ["f", "d"].contains(encoding) {
        let exact = n.doubleValue
        row["decimal"] = String(exact)
        row["doubleBitPatternHex"] = String(exact.bitPattern, radix: 16)
        if exact.isFinite && exact >= 0 && !integerRequired {
            row["status"] = "available"
            return NumberReading(json: row, integer: nil, available: true)
        }
        row["reason"] = integerRequired ? "integer_counter_required" : "negative_or_nonfinite"
    } else {
        row["reason"] = "unsupported_numeric_encoding"
    }
    row["status"] = "unavailable"
    return NumberReading(json: row, integer: nil, available: false)
}
struct UsageReading {
    let rows: [[String: Any]]
    let total: UInt64?
    let reason: String?
}
func decodeUsage(_ raw: Any?) throws -> UsageReading {
    guard let raw else { return UsageReading(rows: [], total: nil, reason: "AppUsage_missing") }
    guard let records = raw as? [Any] else { return UsageReading(rows: [], total: nil, reason: "AppUsage_not_array") }
    try bounded(records.count <= 128, "record cap")
    var rows: [[String: Any]] = [], counters: [UInt64] = []
    var complete = true
    for (index, rawRecord) in records.enumerated() {
        guard let record = rawRecord as? [String: Any] else {
            rows.append(["arrayIndex": index, "status": "unavailable", "reason": "record_not_dictionary"])
            complete = false
            continue
        }
        try bounded(record.count <= 32 && record.keys.allSatisfy { $0.utf8.count <= 128 }, "record field cap")
        let counter = number(record["accumulatedGPUTime"], integerRequired: true)
        let submitted = number(record["lastSubmittedTime"], integerRequired: false)
        var row: [String: Any] = ["arrayIndex": index, "fieldNames": record.keys.sorted(),
            "accumulatedGPUTime": counter.json, "lastSubmittedTime": submitted.json]
        if let api = record["API"] as? String, api.utf8.count <= 64 {
            row["API"] = api
            row["status"] = api == "Metal" && counter.available && submitted.available ? "available" : "unavailable"
            if api != "Metal" { row["reason"] = "unsupported_API" }
        } else {
            row["status"] = "unavailable"
            row["reason"] = "invalid_API"
        }
        if row["status"] as? String == "available", let value = counter.integer { counters.append(value) }
        else { complete = false }
        rows.append(row)
    }
    guard complete else { return UsageReading(rows: rows, total: nil, reason: "one_or_more_records_unavailable") }
    do { return UsageReading(rows: rows, total: try checkedSum(counters), reason: nil) }
    catch { return UsageReading(rows: rows, total: nil, reason: "counter_sum_overflow") }
}
struct Birth: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    let uid: UInt32
}
func birth(_ pid: Int32) throws -> Birth {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    errno = 0
    let returned = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    let errorCode = errno
    try require(returned == size, "birth_read_failed_bytes_\(returned)_errno_\(errorCode)")
    try require(info.pbi_uid == getuid(), "wrong_owner")
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
struct Ordinals {
    private var map: [UInt64: Int] = [:]
    mutating func get(_ registryID: UInt64) throws -> Int {
        if let value = map[registryID] { return value }
        try bounded(map.count < 32, "run client identity cap")
        let value = map.count + 1
        map[registryID] = value
        return value
    }
}
func inventory(_ entry: io_registry_entry_t) throws -> [String: Any] {
    var name = [CChar](repeating: 0, count: 128)
    let classCode = IOObjectGetClass(entry, &name)
    var row: [String: Any] = ["classReturnCode": classCode]
    if classCode == KERN_SUCCESS { row["className"] = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } }
    var properties: Unmanaged<CFMutableDictionary>?
    let code = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
    row["propertyKeysReturnCode"] = code
    guard code == KERN_SUCCESS, let retained = properties?.takeRetainedValue() else {
        row["propertyKeysStatus"] = "unavailable"
        return row
    }
    // Public IOKit materializes values before keys can be bounded; this is not a heap ceiling.
    let dictionary = retained as NSDictionary
    try bounded(dictionary.count <= 128, "property key count cap")
    guard let keys = dictionary.allKeys as? [String] else {
        row["propertyKeysStatus"] = "unavailable"
        return row
    }
    try bounded(keys.allSatisfy { $0.utf8.count <= 128 }, "property key length cap")
    row["propertyKeys"] = keys.sorted()
    row["propertyKeysStatus"] = "available"
    return row
}
func sample(_ pid: Int32, expected: Birth, ordinals: inout Ordinals) throws -> [String: Any] {
    try require(try birth(pid) == expected, "worker_lifetime_changed_before_read")
    var entries: io_iterator_t = 0
    let code = IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &entries)
    try require(code == KERN_SUCCESS, "registry_enumeration_failed")
    defer { IOObjectRelease(entries) }
    var visits = 0, recordCount = 0
    var clients: [[String: Any]] = []
    var seen = Set<UInt64>()
    while case let entry = IOIteratorNext(entries), entry != 0 {
        defer { IOObjectRelease(entry) }
        visits += 1
        try bounded(visits <= 100_000, "registry traversal cap")
        guard IOObjectConformsTo(entry, "IOUserClient") != 0,
            creatorPID(property(entry, "IOUserClientCreator")) == pid else { continue }
        try bounded(clients.count < 16, "snapshot client cap")
        var registryID: UInt64 = 0
        try require(IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS, "registry_ID_unavailable")
        try require(seen.insert(registryID).inserted, "duplicate_registry_visit")
        var row = try inventory(entry)
        row["clientOrdinal"] = try ordinals.get(registryID)
        if IOObjectConformsTo(entry, "AGXDeviceUserClient") != 0 {
            let usage = try decodeUsage(property(entry, "AppUsage"))
            row["recordsInArrayOrder"] = usage.rows
            row["recordCount"] = usage.rows.count
            recordCount += usage.rows.count
            try bounded(recordCount <= 128, "snapshot total record cap")
            if let total = usage.total { row["aggregateRawCounter"] = String(total); row["usageStatus"] = "available" }
            else { row["usageStatus"] = "unavailable"; row["usageReason"] = usage.reason }
        } else {
            row["usageStatus"] = "not_requested_for_other_class"
        }
        try require(creatorPID(property(entry, "IOUserClientCreator")) == pid, "creator_changed_within_read")
        clients.append(row)
    }
    try require(IOIteratorIsValid(entries) != 0, "registry_iterator_invalidated")
    try require(try birth(pid) == expected, "worker_lifetime_changed_after_read")
    return ["status": "available", "lifetimeVerified": true, "ownClients": clients, "clientCount": clients.count,
        "recordCount": recordCount, "inventoryScope": "creator-associated IOUserClient entries in IOService plane"]
}
func observe() throws {
    guard let line = readLine(), let pid = Int32(line), pid > 0 else { throw Failure.invalid("missing_worker_PID") }
    let expected = try birth(pid)
    let start = ProcessInfo.processInfo.systemUptime
    var ordinals = Ordinals(), reads = 0
    try emit(["ready": true])
    while let label = readLine(), label != "quit" {
        reads += 1
        try bounded(reads <= 64 && label.utf8.count <= 128, "observation cap")
        let begin = ProcessInfo.processInfo.systemUptime
        var row: [String: Any]
        do { row = try autoreleasepool { try sample(pid, expected: expected, ordinals: &ordinals) } }
        catch Failure.invalid(let reason) { row = ["status": "unavailable", "reason": reason, "lifetimeVerified": false] }
        row["label"] = label
        row["readStartSeconds"] = begin - start
        row["readEndSeconds"] = ProcessInfo.processInfo.systemUptime - start
        try emit(row)
    }
}
func taskGPU() -> [String: Any] {
    var info = task_power_info_v2_data_t()
    let requested = mach_msg_type_number_t(MemoryLayout<task_power_info_v2_data_t>.size / MemoryLayout<integer_t>.size)
    var count = requested
    let code = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(requested)) {
            task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
        }
    }
    var result: [String: Any] = ["kernReturn": code, "requestedWordCount": requested, "returnedWordCount": count,
        "scope": "worker_self", "status": "unavailable"]
    if code == KERN_SUCCESS && count == requested {
        result["status"] = "available"
        result["taskGPUUtilisationRaw"] = String(info.gpu_energy.task_gpu_utilisation)
    } else { result["reason"] = code == KERN_SUCCESS ? "unexpected_word_count" : "task_info_failed" }
    return result
}
func checkpoint(_ label: String, _ fields: [String: Any] = [:]) throws {
    try emit(fields.merging(["label": label, "selfTaskGPU": taskGPU()]) { _, new in new })
    try require(readLine() == "continue", "observer acknowledgement missing")
}
func reference(_ input: UInt32) -> UInt32 {
    var x = input
    for _ in 0..<256 { x = (x &* 1_664_525) &+ 1_013_904_223; x ^= x >> 13 }
    return x
}
func duration(_ begin: Double, _ end: Double) -> Double? {
    guard begin.isFinite && end.isFinite && begin > 0 && end > begin else { return nil }
    return end - begin
}
struct Timings {
    var valid = 0, invalid = 0
    var total = 0.0, minimum = Double.infinity, maximum = 0.0
    var first: Double?
    mutating func append(_ value: Double?, isFirst: Bool) {
        if let value, value.isFinite && value > 0 {
            valid += 1; total += value; minimum = min(minimum, value); maximum = max(maximum, value)
            if isFirst { first = value }
        } else { invalid += 1 }
    }
    var json: [String: Any] {
        var row: [String: Any] = ["validCount": valid, "invalidCount": invalid,
            "status": valid == 0 ? "unavailable" : invalid == 0 ? "available" : "partial"]
        if invalid > 0 { row["reason"] = "missing_nonfinite_or_unordered_timestamp" }
        if valid > 0 { row["sumSeconds"] = total; row["minimumSeconds"] = minimum; row["maximumSeconds"] = maximum }
        if let first { row["firstCommandSeconds"] = first }
        else { row["firstCommandStatus"] = "unavailable" }
        return row
    }
}
func worker() throws {
    try require(getuid() != 0 && geteuid() != 0, "worker must be unprivileged")
    try checkpoint("before_device")
    guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.invalid("no_Metal_device") }
    try checkpoint("after_device", ["device": device.name])
    let setupStart = ProcessInfo.processInfo.systemUptime
    let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void finite_work(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            uint x = values[i];
            for (uint j = 0; j < 256; ++j) { x = x * 1664525u + 1013904223u; x ^= x >> 13; }
            values[i] = x;
        }
        """
    let library = try device.makeLibrary(source: source, options: nil)
    guard let function = library.makeFunction(name: "finite_work"),
        let buffer = device.makeBuffer(length: 4096 * MemoryLayout<UInt32>.size, options: .storageModeShared)
    else { throw Failure.invalid("setup_allocation_failed") }
    let pipeline = try device.makeComputePipelineState(function: function)
    let input = (0..<4096).map { UInt32($0) ^ 0xA5A5_1234 }, expected = input.map(reference)
    try checkpoint("before_queue_a_creation", ["setupSeconds": ProcessInfo.processInfo.systemUptime - setupStart,
        "explicitDataBufferBytes": buffer.length])
    guard let queueA = device.makeCommandQueue() else { throw Failure.invalid("queue_A_failed") }
    try checkpoint("after_queue_a_before_work")
    var lastGPUEnd = 0.0, allSubmissions = 0
    func batch(_ queue: MTLCommandQueue, _ label: String) throws {
        try checkpoint("before_\(label)")
        let wallStart = ProcessInfo.processInfo.systemUptime
        var gpu = Timings(), kernel = Timings(), host = Timings(), callback = Timings()
        var overlaps = 0, intervalEnd = 0.0, union = 0.0
        for index in 0..<64 {
            try bounded(allSubmissions < 384, "submission cap")
            try autoreleasepool {
                let values = buffer.contents().bindMemory(to: UInt32.self, capacity: 4096)
                for element in 0..<4096 { values[element] = input[element] }
                guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder()
                else { throw Failure.invalid("command_allocation_failed") }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: 4096, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding()
                let callbackTime = Mutex<Double?>(nil)
                command.addCompletedHandler { _ in
                    callbackTime.withLock { $0 = ProcessInfo.processInfo.systemUptime }
                }
                let commit = ProcessInfo.processInfo.systemUptime
                command.commit()
                allSubmissions += 1
                command.waitUntilCompleted()
                let completed = ProcessInfo.processInfo.systemUptime
                try require(command.status == .completed && command.error == nil, "command_failed")
                for element in 0..<4096 { try require(values[element] == expected[element], "output_mismatch") }
                host.append(duration(commit, completed), isFirst: index == 0)
                callback.append(callbackTime.withLock { $0.flatMap { duration(commit, $0) } }, isFirst: index == 0)
                let gpuDuration = duration(command.gpuStartTime, command.gpuEndTime)
                gpu.append(gpuDuration, isFirst: index == 0)
                kernel.append(duration(command.kernelStartTime, command.kernelEndTime), isFirst: index == 0)
                if gpuDuration != nil {
                    if command.gpuStartTime < lastGPUEnd { overlaps += 1 }
                    union += max(0, command.gpuEndTime - max(command.gpuStartTime, intervalEnd))
                    intervalEnd = max(intervalEnd, command.gpuEndTime)
                    lastGPUEnd = max(lastGPUEnd, command.gpuEndTime)
                }
            }
            if index == 0 { try checkpoint("first_\(label)", ["hostCommitToWaitReturn": host.json, "hostCommitToCompletionHandler": callback.json,
                    "gpu": gpu.json, "kernel": kernel.json]) }
        }
        try withExtendedLifetime(queue) {
            var fields: [String: Any] = ["submissions": 64, "outputsVerified": true, "gpu": gpu.json,
                "kernel": kernel.json, "hostCommitToWaitReturn": host.json,
                "hostCommitToCompletionHandler": callback.json, "gpuTimestampOverlaps": overlaps,
                "gpuUnionStatus": gpu.valid == 0 ? "unavailable" : gpu.invalid == 0 ? "available" : "partial",
                "batchWallSecondsIncludingFirstRead": ProcessInfo.processInfo.systemUptime - wallStart]
            if gpu.valid > 0 { fields["gpuValidIntervalUnionSeconds"] = union }
            try checkpoint("after_\(label)", fields)
        }
    }
    try batch(queueA, "a1")
    try checkpoint("before_queue_b_creation")
    try autoreleasepool {
        guard let queueB = device.makeCommandQueue() else { throw Failure.invalid("queue_B_failed") }
        try checkpoint("after_queue_b_before_work")
        try batch(queueB, "b1")
        try withExtendedLifetime(queueB) { try batch(queueA, "a2") }
    }
    try checkpoint("after_b_release")
    try checkpoint("before_queue_bprime_creation")
    try autoreleasepool {
        guard let queueBPrime = device.makeCommandQueue() else { throw Failure.invalid("queue_Bprime_failed") }
        try checkpoint("after_queue_bprime_before_work")
        try batch(queueBPrime, "bprime")
        try withExtendedLifetime(queueBPrime) { try batch(queueA, "a3") }
    }
    try checkpoint("after_bprime_release")
    try checkpoint("before_queue_c_creation")
    try autoreleasepool {
        guard let queueC = device.makeCommandQueue() else { throw Failure.invalid("queue_C_failed") }
        try checkpoint("after_queue_c_before_work")
        try batch(queueC, "c1")
        try withExtendedLifetime(queueC) {
            try checkpoint("before_cooldown", ["totalSubmissions": allSubmissions])
            Thread.sleep(forTimeInterval: 1)
            try withExtendedLifetime(queueA) { try checkpoint("after_cooldown") }
        }
    }
}
func selfTest() throws {
    try require(try Mode.parse([], authorized: false) == .preflight, "default_mode")
    for mode in ["--authorized-worker", "--authorized-observer"] {
        do { _ = try Mode.parse([mode], authorized: false); throw Failure.bound("native mode admitted") }
        catch Failure.invalid {}
    }
    try require(number(NSNumber(value: UInt64.max), integerRequired: true).integer == UInt64.max, "uint64 precision")
    for invalid: Any in [true, -1, 1.5, Double.nan, "3"] {
        try require(!number(invalid, integerRequired: true).available, "invalid numeric accepted")
    }
    try require(number(NSNumber(value: 1.5), integerRequired: false).available, "finite float timestamp rejected")
    try require(number(nil, integerRequired: true).integer == nil, "missing counter became zero")
    try require(try decodeUsage(nil).total == nil, "missing usage became zero")
    try require(try decodeUsage([]).total == 0, "valid empty schema")
    let record: [String: Any] = ["API": "Metal", "accumulatedGPUTime": UInt64(7), "lastSubmittedTime": UInt64(9)]
    try require(try decodeUsage([record]).total == 7, "record decode")
    let missingTimestamp: [String: Any] = ["API": "Metal", "accumulatedGPUTime": UInt64(7)]
    try require(try decodeUsage([missingTimestamp]).total == nil, "missing timestamp silently accepted")
    do { _ = try decodeUsage(Array(repeating: record, count: 129)); throw Failure.invalid("record cap failed") }
    catch Failure.bound {}
    do { _ = try checkedSum([UInt64.max, 1]); throw Failure.bound("overflow accepted") }
    catch Failure.invalid {}
    var ordinals = Ordinals()
    try require(try ordinals.get(900) == ordinals.get(900), "ordinal unstable")
    try require(try ordinals.get(901) != ordinals.get(900), "ordinal collision")
    for id in 1000..<1030 { _ = try ordinals.get(UInt64(id)) }
    do { _ = try ordinals.get(2000); throw Failure.invalid("ordinal cap failed") }
    catch Failure.bound {}
    try require(duration(0, 1) == nil && duration(2, 1) == nil && duration(1, 2) == 1, "timestamp validation")
    var timings = Timings()
    try require(timings.json["status"] as? String == "unavailable", "empty timing implies measured zero")
    timings.append(0.01, isFirst: true); timings.append(nil, isFirst: false)
    try require(timings.valid == 1 && timings.invalid == 1 && timings.first == 0.01, "timing summary")
    try require(reference(0) == 426546178, "CPU reference vector")
    try emit(["offlineChecks": "passed", "nativeWorkerOrObserverStarted": false])
}
do {
    let authorized = ProcessInfo.processInfo.environment["AGENT_MONITOR_GPU_CALIBRATION"] == "explicit"
    switch try Mode.parse(Array(CommandLine.arguments.dropFirst()), authorized: authorized) {
    case .preflight: try selfTest()
    case .worker: try worker()
    case .observer: try observe()
    }
} catch {
    FileHandle.standardError.write(Data("calibration failed: \(error)\n".utf8))
    exit(1)
}
