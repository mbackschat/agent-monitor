import AgentMonitorPresentation
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@MainActor @Suite struct CommandInspectionTests {
    @Test func argumentsRequireAnExplicitRequestAndLeaveWithInspection() async throws {
        let calls = Mutex(0)
        let controller = CommandInspectionController { _ in
            calls.withLock { $0 += 1 }
            return ["java", "-Xmx2g", "value with spaces"]
        }
        let row = commandRow()
        var state = LiveReportState()
        state.receive(
            MonitoringSnapshot(
                cpuAccounting: CPUAccounting(
                    hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 50,
                    unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
                timestamp: Date(), intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
                sampledProcessCount: 1, unreadableProcessCount: 0, findings: [row]))
        state.select(.process(row.process))
        state.setDisclosure(expanded: true)
        #expect(controller.state == nil)
        #expect(calls.withLock { $0 } == 0)
        #expect(controller.start(try #require(state.commandInspectionTarget)))
        await controller.wait()
        #expect(controller.state?.arguments == ["java", "-Xmx2g", "value with spaces"])
        #expect(calls.withLock { $0 } == 1)
        state.commandInspection = controller.state
        state.maximizeDetails()
        let text = LiveReportLayout.lines(state: state, width: 120, height: 60).map(\.text).joined(
            separator: "\n")
        #expect(text.contains("[2] value with spaces"))
        #expect(text.contains("read on demand"))
        state.setDisclosure(expanded: false)
        controller.reconcile(with: state)
        #expect(controller.state == nil)
    }

    @Test func closedInspectionCannotReceiveALateResultOrQueueAnotherRead() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let controller = CommandInspectionController { _ in
            for await _ in gate.stream { break }
            return ["private argument"]
        }
        let row = commandRow()
        #expect(controller.start(row))
        #expect(!controller.start(row))
        controller.dismiss()
        gate.continuation.finish()
        await controller.wait()
        #expect(controller.state == nil)
        #expect(!controller.isReading)
    }

    @Test func unavailableReadDoesNotBorrowCachedArguments() async throws {
        let controller = CommandInspectionController { _ in nil }
        #expect(controller.start(commandRow()))
        await controller.wait()
        #expect(controller.state?.arguments == nil)
        #expect(controller.state?.status == .unavailable)
    }
}

private func commandRow() -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: 42, startMicroseconds: 1), executable: "/bin/java", name: "java",
        cpuPercent: 50, footprintBytes: 1_000, cwd: "/fixture", command: nil,
        metadataStatus: .markerRead,
        attribution: Attribution(
            provider: .codex, evidence: .marker, context: .unverified,
            threadID: "session", rootSessionID: nil, runtime: nil, terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
}
