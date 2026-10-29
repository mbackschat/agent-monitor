import Foundation
import IOKit
import Darwin

struct Lifetime: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    let uid: UInt32
}
struct CounterKey: Hashable {
    let registryID: UInt64
    let api: String
}
struct Counter {
    let value: UInt64
    let pid: Int32
    let lifetime: Lifetime
}
struct Observation {
    var counters: [CounterKey: Counter] = [:]
    var registryIDs: Set<UInt64> = []
    var pids: Set<Int32> = []
    var fields: Set<String> = []
    var apiLabels: Set<String> = []
    var metrics: [String: Int] = [:]
    var hostValues: [String: [Double]] = [:]
    mutating func count(_ name: String, _ n: Int = 1) { metrics[name, default: 0] += n }
}
func property(_ entry: io_registry_entry_t, _ key: String) -> CFTypeRef? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}
func lifetime(_ pid: Int32) -> Lifetime? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Lifetime(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec, uid: info.pbi_uid)
}
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
func sysctlString(_ key: String) -> String {
    var size = 0
    guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return "unavailable" }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
    return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}
func readClient(_ entry: io_registry_entry_t, into result: inout Observation) {
    result.count("clientEntries")
    var registryID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS else {
        result.count("registryIDFailures"); return
    }
    guard result.registryIDs.insert(registryID).inserted else {
        result.count("duplicateRegistryVisits"); return
    }
    guard let creator = property(entry, "IOUserClientCreator") as? String else {
        result.count("creatorMissingOrWrongType"); return
    }
    let tokens = creator.split(separator: " ", maxSplits: 2)
    guard tokens.count >= 2, tokens[0] == "pid", let pid = Int32(tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: ","))) else {
        result.count("creatorUnparsed"); return
    }
    result.pids.insert(pid)
    let before = lifetime(pid)
    let usage = property(entry, "AppUsage")
    let after = lifetime(pid)
    if before == nil || after == nil { result.count("lifetimeReadFailures") }
    else if before != after { result.count("lifetimeChangedWithinRead") }
    else if before!.uid == getuid() { result.count("verifiedSameUserClientEntries") }
    else { result.count("verifiedOtherUserClientEntries") }
    guard let records = usage as? [[String: Any]] else {
        result.count("usageMissingOrWrongType"); return
    }
    result.count("usageRecords", records.count)
    var byAPI: [String: [UInt64]] = [:]
    for record in records {
        for (key, value) in record {
            result.fields.insert("\(key):\(String(describing: type(of: value)))")
        }
        guard let api = record["API"] as? String else { result.count("apiMissingOrWrongType"); continue }
        result.apiLabels.insert(api)
        guard let number = record["accumulatedGPUTime"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0 else {
            result.count("counterMissingOrWrongType"); continue
        }
        byAPI[api, default: []].append(number.uint64Value)
    }
    for (api, values) in byAPI {
        guard values.count == 1 else {
            result.count("ambiguousAPIRecordGroups")
            result.count("recordsInAmbiguousGroups", values.count)
            continue
        }
        guard let before, before == after else { continue }
        result.counters[CounterKey(registryID: registryID, api: api)] = Counter(value: values[0], pid: pid, lifetime: before)
    }
}
func sample() -> Observation {
    var result = Observation()
    var roots: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &roots)
    guard status == KERN_SUCCESS else {
        result.count("rootMatchingFailureCode", Int(status)); return result
    }
    defer { IOObjectRelease(roots) }
    while case let root = IOIteratorNext(roots), root != 0 {
        defer { IOObjectRelease(root) }
        result.count("accelerators")
        if let stats = property(root, "PerformanceStatistics") as? [String: Any] {
            result.count("hostStatisticsDictionaries")
            for key in ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %", "In use system memory"] {
                if let value = stats[key] as? NSNumber {
                    result.hostValues[key, default: []].append(value.doubleValue)
                }
            }
        } else { result.count("hostStatisticsMissingOrWrongType") }
        var descendants: io_iterator_t = 0
        let childStatus = IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &descendants)
        guard childStatus == KERN_SUCCESS else { result.count("descendantIteratorFailures"); continue }
        defer { IOObjectRelease(descendants) }
        while case let entry = IOIteratorNext(descendants), entry != 0 {
            defer { IOObjectRelease(entry) }
            result.count("descendantsVisited")
            if IOObjectConformsTo(entry, "AGXDeviceUserClient") != 0 {
                readClient(entry, into: &result)
            }
        }
    }
    return result
}
let start = ProcessInfo.processInfo.systemUptime
var previous: Observation?
var sampleRows: [[String: Any]] = []
var allFields: Set<String> = []
var allAPIs: Set<String> = []
for index in 0..<12 {
    if index > 0 { Thread.sleep(forTimeInterval: 1) }
    let wallStart = ProcessInfo.processInfo.systemUptime
    if wallStart - start > 28 { break }
    let cpuStart = cpuSeconds()
    let current = sample()
    let wallEnd = ProcessInfo.processInfo.systemUptime
    let cpuEnd = cpuSeconds()
    allFields.formUnion(current.fields)
    allAPIs.formUnion(current.apiLabels)
    var row: [String: Any] = [
        "sample": index,
        "offsetSeconds": wallEnd - start,
        "readerWallMilliseconds": (wallEnd - wallStart) * 1000,
        "readerCPUMilliseconds": (cpuEnd - cpuStart) * 1000,
        "uniqueRegistryEntries": current.registryIDs.count,
        "uniqueCreatorPIDs": current.pids.count,
        "uniqueAPICountersWithVerifiedLifetime": current.counters.count,
        "counts": current.metrics,
        "hostReportedValues": current.hostValues
    ]
    if let previous {
        var matched = 0, rising = 0, reset = 0, changedLifetime = 0
        var positiveRawDelta: UInt64 = 0
        for (key, value) in current.counters {
            guard let old = previous.counters[key] else { continue }
            guard old.pid == value.pid && old.lifetime == value.lifetime else { changedLifetime += 1; continue }
            matched += 1
            if value.value < old.value { reset += 1 }
            else if value.value > old.value { rising += 1; positiveRawDelta += value.value - old.value }
        }
        row["matchedUniqueAPICounters"] = matched
        row["risingUniqueAPICounters"] = rising
        row["decreasingUniqueAPICounters"] = reset
        row["counterLifetimeChanges"] = changedLifetime
        row["positiveRawDeltaUniqueAPICounters"] = positiveRawDelta
        row["newRegistryEntries"] = current.registryIDs.subtracting(previous.registryIDs).count
        row["disappearedRegistryEntries"] = previous.registryIDs.subtracting(current.registryIDs).count
    }
    sampleRows.append(row)
    previous = current
}
let output: [String: Any] = [
    "dateUTC": ISO8601DateFormatter().string(from: Date()),
    "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    "osBuild": sysctlString("kern.osversion"),
    "hardware": sysctlString("machdep.cpu.brand_string"),
    "unprivileged": getuid() != 0 && geteuid() != 0,
    "durationSeconds": ProcessInfo.processInfo.systemUptime - start,
    "sampleCount": sampleRows.count,
    "usageFieldTypes": allFields.sorted(),
    "apiLabels": allAPIs.sorted(),
    "samples": sampleRows,
    "limits": ["Raw counters have no independently verified unit or GPU capacity semantics in this probe.", "Only one record per API per registry entry is matched; repeated API groups are excluded because array identity is ambiguous.", "No attribution to agent/session is attempted.", "No raw PID, registry ID, lifetime, name, path or per-process counter is emitted.", "No synthetic GPU workload, provider query, task port, private framework, root or permission change is used."]
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
