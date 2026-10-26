import AgentMonitorCore
import Foundation

struct CaptureScan: Encodable {
    let kind = "scan"
    let sequence: Int
    let listedAt: Double
    let listingGapSeconds: Double?
    let scanSeconds: Double
    let enumeratedCount: Int
    let unreadableCount: Int
    let logicalCPUCount: Int
    let listedPIDs: [Int32]?
    let processes: [ProcessRow]
    let outcomes: [Outcome]
    let hostTicks: [[UInt32]]?
    let timing: Timing?

    init(_ snapshot: ProcessSnapshot, sequence: Int, listingGapSeconds: Double?) {
        self.sequence = sequence
        listedAt = snapshot.listedAt
        self.listingGapSeconds = listingGapSeconds
        scanSeconds = snapshot.scanSeconds
        enumeratedCount = snapshot.enumeratedCount
        unreadableCount = snapshot.unreadableCount
        logicalCPUCount = snapshot.logicalCPUCount
        listedPIDs = snapshot.listedPIDs
        processes = snapshot.samples.map(ProcessRow.init)
        outcomes = snapshot.nativeOutcomes.map(Outcome.init)
        hostTicks = snapshot.hostCounters?.processors.map { [$0.user, $0.system, $0.idle, $0.nice] }
        timing = snapshot.nativeTiming.map(Timing.init)
    }

    struct ProcessRow: Encodable {
        let identity: ProcessIdentity
        let parentPID: Int32
        let executable: String
        let name: String
        let startedAt: Double?
        let sampledAt: Double
        let sampledAtTicks: UInt64?
        let startedAtTicks: UInt64?
        let cpuSeconds: Double?
        let rawUserTicks: UInt64?
        let rawSystemTicks: UInt64?
        let numerator: UInt32?
        let denominator: UInt32?
        let footprintBytes: UInt64?
        let kernelPeakFootprintBytes: UInt64?

        init(_ sample: ProcessSample) {
            identity = sample.identity
            parentPID = sample.parentPID
            executable = sample.executable
            name = sample.name
            startedAt = sample.startedAt
            sampledAt = sample.sampledAt
            sampledAtTicks = sample.sampledAtTicks
            startedAtTicks = sample.startedAtTicks
            cpuSeconds = sample.cpuSeconds
            rawUserTicks = sample.rawCPU?.user
            rawSystemTicks = sample.rawCPU?.system
            numerator = sample.rawCPU?.numerator
            denominator = sample.rawCPU?.denominator
            footprintBytes = sample.footprintBytes
            kernelPeakFootprintBytes = sample.kernelPeakFootprintBytes
        }
    }

    struct Outcome: Encodable {
        let pid: Int32
        let identity: ProcessIdentity?
        let verifiedIdentity: ProcessIdentity?
        let operation: String
        let status: String
        let returned: Int32?
        let expected: Int32?
        let errorNumber: Int32?
        let observedAtTicks: UInt64

        init(_ outcome: NativeCounterOutcome) {
            pid = outcome.pid
            identity = outcome.identity
            verifiedIdentity = outcome.verifiedIdentity
            operation =
                switch outcome.operation {
                case .bsdInfo: "bsdInfo"
                case .executablePath: "executablePath"
                case .resourceUsage: "resourceUsage"
                case .identityVerification: "identityVerification"
                }
            status =
                switch outcome.status {
                case .permissionDenied: "permissionDenied"
                case .lookupUnavailable: "lookupUnavailable"
                case .shortRead: "shortRead"
                case .identityMismatch: "identityMismatch"
                case .outOfScopeUser: "outOfScopeUser"
                case .otherFailure: "otherFailure"
                }
            returned = outcome.failure?.returned
            expected = outcome.failure?.expected
            errorNumber = outcome.failure?.errorNumber
            observedAtTicks = outcome.observedAtTicks
        }
    }

    struct Timing: Encodable {
        let startedAbsolute: UInt64
        let listingAbsolute: UInt64
        let listingContinuous: UInt64
        let listingWallTime: Date
        let endedAbsolute: UInt64
        let numerator: UInt32
        let denominator: UInt32

        init(_ timing: NativeScanTiming) {
            startedAbsolute = timing.startedAbsolute
            listingAbsolute = timing.listingAbsolute
            listingContinuous = timing.listingContinuous
            listingWallTime = timing.listingWallTime
            endedAbsolute = timing.endedAbsolute
            numerator = timing.numerator
            denominator = timing.denominator
        }
    }
}
