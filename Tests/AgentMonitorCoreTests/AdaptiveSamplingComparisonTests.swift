import Foundation
import Testing

@testable import AgentMonitorCore

private struct AdaptiveComparisonRecord: Encodable {
    struct Coverage: Encodable {
        var durationSeconds: Double
        var population: Int
        var identities: Int
        var acceptedCPU: Double
        var identitiesLostAgainstMinimum: Int
        var identitiesLostAgainstMaximum: Int
        var cpuLostAgainstMinimum: Double
        var cpuGainedAgainstMinimum: Double
        var cpuLostAgainstMaximum: Double
        var cpuGainedAgainstMaximum: Double
    }
    var scenario: String
    var arm: String
    var maximum: Double
    var window: Double
    var horizon: Double
    var scanSeconds: Double
    var scans: Int
    var settledScans: Int
    var timeAtMinimum: Double
    var timeAtMaximum: Double
    var overrideFractions: [String: Double]
    var intervalBandFractions: [String: Double]
    var acceptedCPU: Double
    var unseenCPU: Double
    var unreadableCPU: Double
    var tailCPU: Double
    var initialCPU: Double
    var coverage: [Coverage]
}

private func comparisonScenarios() -> [AdaptiveWorkloadScenario] {
    var scenarios: [AdaptiveWorkloadScenario] = []
    for maximum in [0.25, 0.625] {
        for count in [4, 16, 32] {
            for rate in [0.0015, 0.004] {
                let lives = (0..<count).map {
                    AdaptiveWorkloadLife(pid: Int32(100 + $0), birth: -120, end: 180, cpu: .steady(rate))
                }
                scenarios.append(
                    .init(
                        name: "idle-\(count)-lifetimes-\(rate)", lives: lives, horizon: 180, maximum: maximum)
                )
            }
        }
        for duration in [0.05, 0.2, 0.5, 1.0] {
            // Ten phases cover one closed-panel gap; repeated bursts also test retained activity.
            let lives = (0..<30).map { index in
                let birth = 80 + Double(index / 10) * 40 + Double(index % 10) * 0.0625 + 0.017
                return AdaptiveWorkloadLife(pid: Int32(100 + index), birth: birth, end: birth + duration)
            }
            scenarios.append(.init(name: "bursts-\(duration)", lives: lives, maximum: maximum))
        }
    }
    for period in [30.0, 60, 120] {
        let lives = (0..<4).map { index in
            let birth = 65.017 + Double(index) * period
            return AdaptiveWorkloadLife(pid: Int32(100 + index), birth: birth, end: birth + 0.2)
        }
        scenarios.append(.init(name: "sparse-200ms-every-\(period)", lives: lives, horizon: 480))
    }
    for rate in [5.0, 10, 30] {
        for duration in [0.02, 0.2, 2.0] {
            let lives = (0..<Int(rate * 3)).map { index in
                let birth = 0.017 + Double(index) * 60 / rate
                return AdaptiveWorkloadLife(
                    pid: Int32(100 + index), birth: birth, end: birth + duration,
                    cpu: .steady(0.005), resolution: .pending)
            }
            scenarios.append(.init(name: "pending-churn-\(rate)-per-minute-\(duration)", lives: lives))
        }
    }
    for delay in [0.0, 1.0, 10.0] {
        let lives = (0..<60).map { index in
            let birth = 0.017 + Double(index) * 3
            return AdaptiveWorkloadLife(
                pid: Int32(100 + index), birth: birth, end: birth + 0.2,
                cpu: .steady(0.01), resolution: .negative, resolutionDelay: delay)
        }
        scenarios.append(.init(name: "negative-churn-delay-\(delay)", lives: lives))
    }
    for (amount, period) in [(0.001, 5.0), (0.030, 10.0)] {
        scenarios.append(
            .init(
                name: "heartbeat-\(amount)-per-\(period)",
                lives: [
                    .init(pid: 1, birth: -120, end: 240, cpu: .heartbeat(amount: amount, period: period))
                ]))
    }
    scenarios.append(
        .init(
            name: "new-idle-sessions",
            lives: (0..<16).map {
                .init(pid: Int32(100 + $0), birth: 0.01, end: 300, cpu: .steady(0.0015))
            }, horizon: 300))
    scenarios.append(
        .init(
            name: "pending-startup-negatives",
            lives: (0..<16).map {
                .init(
                    pid: Int32(100 + $0), birth: -120, end: 240, cpu: .steady(0.01), resolution: .negative,
                    resolutionDelay: 150)
            }))
    scenarios.append(
        .init(
            name: "recovered-30s",
            lives: [
                .init(pid: 1, birth: -120, end: 240, cpu: .steady(0.002), failures: 65..<95)
            ]))
    for relax in [false, true] {
        scenarios.append(
            .init(
                name: "persistent-failure-relax-\(relax)",
                lives: [
                    .init(pid: 1, birth: -120, end: 240, cpu: .steady(0.002), failures: 65..<241)
                ],
                relaxPersistentFailures: relax))
    }
    for maximum in [1.0, 2.5, 5, 12.5, 15, 37.5] {
        scenarios.append(
            .init(
                name: "long-preset-\(maximum)",
                lives: [
                    .init(pid: 1, birth: -120, end: 300, cpu: .steady(0.002))
                ], horizon: 300, maximum: maximum))
    }
    scenarios.append(
        .init(
            name: "window-shorter-than-maximum",
            lives: [
                .init(pid: 1, birth: -120, end: 240, cpu: .steady(0.002))
            ], maximum: 60, window: 1))
    for scale in [0.5, 1.0, 2.0] {
        var calibration = AdaptiveSamplingPrototype.Calibration()
        calibration.cpuHigh *= scale
        calibration.arrivalsHigh *= scale
        calibration.excess *= scale
        calibration.sustained *= scale
        calibration.lookback *= scale
        var lives = [
            AdaptiveWorkloadLife(
                pid: 1, birth: -120, end: 240,
                cpu: .heartbeat(amount: 0.030, period: 10))
        ]
        lives += (0..<12).map {
            let birth = 80.017 + Double($0) * 10
            return .init(pid: Int32(100 + $0), birth: birth, end: birth + 0.2, cpu: .steady(0.1))
        }
        scenarios.append(.init(name: "calibration-scale-\(scale)", lives: lives, calibration: calibration))
    }
    scenarios.append(
        .init(
            name: "unverified-helper-races",
            lives: (0..<8).map {
                let birth = Double($0) * 30 + 0.017
                return .init(pid: Int32(100 + $0), birth: birth, end: birth + 0.02, helper: true)
            }))
    scenarios.append(
        .init(
            name: "exec-reuse-scope",
            lives: [
                .init(pid: 1, birth: -120, end: 240, cpu: .steady(1), inScope: false),
                .init(pid: 2, birth: 65.017, end: 65.217, execAt: 65.1),
                .init(pid: 2, birth: 66.017, end: 67.017),
            ]))
    return scenarios
}

@Suite struct AdaptiveSamplingComparisonTests {
    @Test(.timeLimit(.minutes(10)))
    func boundedScenarioAndParameterSweep() async throws {
        for scenario in comparisonScenarios() {
            var results: [AdaptiveWorkloadArm: AdaptiveWorkloadResult] = [:]
            for arm in AdaptiveWorkloadArm.allCases {
                results[arm] = try await runAdaptiveWorkload(scenario, arm: arm)
            }
            let minimum = try #require(results[.fixedMinimum])
            let maximum = try #require(results[.fixedMaximum])
            for arm in AdaptiveWorkloadArm.allCases {
                let result = try #require(results[arm])
                let range = 0.0..<scenario.horizon
                let partition = result.partition(scenario)
                let durations = Dictionary(grouping: scenario.lives.filter(\.inScope)) {
                    (($0.end - $0.birth) * 1_000).rounded() / 1_000
                }
                let coverage = durations.keys.sorted().map { duration -> AdaptiveComparisonRecord.Coverage in
                    let lives = durations[duration] ?? []
                    let losses = lives.map {
                        (minimum.accepted[$0.identity] ?? 0) - (result.accepted[$0.identity] ?? 0)
                    }
                    let maximumLosses = lives.map {
                        (maximum.accepted[$0.identity] ?? 0) - (result.accepted[$0.identity] ?? 0)
                    }
                    return .init(
                        durationSeconds: duration, population: lives.count,
                        identities: lives.filter { result.identities.contains($0.identity) }.count,
                        acceptedCPU: lives.reduce(0) { $0 + (result.accepted[$1.identity] ?? 0) },
                        identitiesLostAgainstMinimum: lives.filter {
                            minimum.identities.contains($0.identity)
                                && !result.identities.contains($0.identity)
                        }.count,
                        identitiesLostAgainstMaximum: lives.filter {
                            maximum.identities.contains($0.identity)
                                && !result.identities.contains($0.identity)
                        }.count,
                        cpuLostAgainstMinimum: losses.reduce(0) { $0 + max(0, $1) },
                        cpuGainedAgainstMinimum: losses.reduce(0) { $0 + max(0, -$1) },
                        cpuLostAgainstMaximum: maximumLosses.reduce(0) { $0 + max(0, $1) },
                        cpuGainedAgainstMaximum: maximumLosses.reduce(0) { $0 + max(0, -$1) })
                }
                var reasons: [String: Double] = [:]
                for reason in [
                    AdaptiveSamplingPrototype.Reason.uncertainty, .lifecycle, .recovery, .excess, .sustained,
                ] {
                    reasons[reason.rawValue] =
                        arm == .adaptive
                        ? result.fraction(in: range) { $0.decision.reasons.contains(reason) } : 0
                }
                var bands: [String: Double] = [:]
                for (lower, upper) in [
                    (0.1, 0.15), (0.15, 0.25), (0.25, 0.625), (0.625, 1), (1.0, 5), (5.0, 15), (15.0, 61),
                ] {
                    bands["[\(lower),\(upper))"] = result.fraction(in: range) {
                        (lower..<upper).contains($0.requested)
                    }
                }
                let record = AdaptiveComparisonRecord(
                    scenario: scenario.name, arm: arm.rawValue,
                    maximum: scenario.maximum, window: scenario.window, horizon: scenario.horizon,
                    scanSeconds: scenario.scanSeconds,
                    scans: result.ticks.count,
                    settledScans: result.scans(in: (scenario.horizon - 120)..<scenario.horizon),
                    timeAtMinimum: result.fraction(in: range) { abs($0.requested - 0.1) < 1e-9 },
                    timeAtMaximum: result.fraction(in: range) { abs($0.requested - scenario.maximum) < 1e-9 },
                    overrideFractions: reasons, intervalBandFractions: bands,
                    acceptedCPU: partition.accepted, unseenCPU: partition.unseen,
                    unreadableCPU: partition.unreadable,
                    tailCPU: partition.tail, initialCPU: partition.initial,
                    coverage: coverage)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                print("ADAPTIVE_RESULT " + String(decoding: try encoder.encode(record), as: UTF8.self))
            }
        }
    }
}
