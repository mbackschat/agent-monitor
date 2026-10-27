import Darwin

struct SamplingSession: Sendable {
    private var value: LiveInterval.Value
    private var controller: AdaptiveSamplingController
    private var evidence = SamplingEvidence()
    private var control: AdaptiveSamplingController.Decision
    private(set) var decision: SamplingDecision
    private var policyChanges = 0

    init(_ value: LiveInterval.Value, at now: Double) {
        self.value = value
        let settings = value.settings
        let maximum = settings.maximum(panelVisible: value.panelVisible)
        controller = AdaptiveSamplingController(maximum: maximum, window: settings.window)
        controller.restart(
            minimum: settings.minimum, window: settings.window, enabled: settings.enabled, at: now)
        control = .init(requested: settings.enabled ? settings.minimum : maximum, base: settings.minimum)
        decision = SamplingDecision(
            mode: settings.enabled ? .adaptive : .fixed,
            requestedSeconds: control.requested, baseSeconds: settings.minimum,
            minimumSeconds: settings.minimum, maximumSeconds: maximum)
    }

    mutating func synchronize(_ next: LiveInterval.Value, at now: Double, inspection: Bool) throws {
        guard next.settings.isValid else { throw MonitoringError.invalidConfiguration }
        if next != value {
            let previous = value.settings
            let settings = next.settings
            controller.changeMaximum(settings.maximum(panelVisible: next.panelVisible))
            if previous.minimum != settings.minimum || previous.window != settings.window
                || previous.enabled != settings.enabled
            {
                controller.restart(
                    minimum: settings.minimum, window: settings.window, enabled: settings.enabled, at: now)
                control = .init(requested: settings.minimum, base: settings.minimum)
                if previous.enabled != settings.enabled { evidence = SamplingEvidence() }
            } else if next.openings != value.openings {
                controller.openPanel(maximum: settings.maximum(panelVisible: next.panelVisible))
            }
            value = next
            policyChanges += 1
        }
        refreshDecision(inspection: inspection)
    }

    mutating func observe(
        _ scan: CounterScan, snapshot: ProcessSnapshot, rows: [HeavyProcess], monitor: inout Monitor,
        carried: [HeldInspectionObservation], excluding: Set<Int32>, at now: Double, inspection: Bool
    ) {
        guard value.settings.enabled else {
            refreshDecision(inspection: inspection)
            return
        }
        var observations = monitor.samplingObservations(
            snapshot, rows: rows, collectorPID: Int32(getpid()), excluding: excluding)
        for held in carried {
            let sample = held.sample
            let helper =
                sample.parentPID == getpid()
                || monitor.samplingCollectorOwned(
                    held.row.attribution.ancestry, collectorPID: Int32(getpid()))
            observations.append(
                SamplingObservation(
                    pid: sample.identity.pid, identity: sample.identity,
                    birth: sample.startedAt, eligible: !helper && !excluding.contains(sample.identity.pid),
                    countersAvailable: true, historical: true))
        }
        let knownFailures = observations.filter { !$0.countersAvailable }.count
        let input = evidence.ingest(
            observations, contributions: scan.contributions, listedAt: snapshot.listedAt,
            closedAt: now, window: value.settings.window,
            unidentifiedFailures: snapshot.unreadableCount > knownFailures)
        control = controller.observe(input.aggregate, uncertain: input.uncertain, inspection: inspection)
        refreshDecision(inspection: inspection)
    }

    mutating func takePolicyChanges() -> Int {
        defer { policyChanges = 0 }
        return policyChanges
    }

    private mutating func refreshDecision(inspection: Bool) {
        let settings = value.settings
        var overrides = settings.enabled ? control.reasons : []
        overrides.remove(.inspection)
        if inspection { overrides.insert(.inspection) }
        let maximum = settings.maximum(panelVisible: value.panelVisible)
        decision = SamplingDecision(
            mode: settings.enabled ? .adaptive : .fixed,
            requestedSeconds: overrides.isEmpty
                ? (settings.enabled ? controller.base : maximum) : settings.minimum,
            baseSeconds: controller.base, minimumSeconds: settings.minimum, maximumSeconds: maximum,
            rollingCPURate: control.rolling.cpu, youngCPURate: control.rolling.youngCPU,
            arrivalRate: control.rolling.arrivals, rollingSpanSeconds: control.rolling.span,
            recentCPURate: control.recent.cpu, recentSpanSeconds: control.recent.span, overrides: overrides)
    }
}
