import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Testing

@Suite @MainActor struct InteractiveDiagnosisTests {
    @Test func cancellationIsImmediateAndDrainsBeforeRerunWithoutLatePublication() async {
        let gate = DiagnosisGate()
        let controller = CPUDiagnosisController(source: { try await gate.run() })
        #expect(controller.start())
        await gate.waitUntilStarted()
        #expect(controller.state.phase == .collecting)
        controller.cancel()
        #expect(controller.state.phase == .cancelled)
        #expect(controller.state.isRunning)
        #expect(!controller.start())
        controller.dismiss()
        #expect(controller.state.phase == .hidden)
        await gate.release(diagnosisPresentationFixture())
        await controller.waitForCompletion()
        #expect(controller.state.phase == .hidden)
        #expect(!controller.state.isRunning)
        #expect(controller.state.content.isEmpty)
    }

    @Test func rerunDiscardsOldResultsAndFailureDoesNotRestoreThem() async {
        let gate = DiagnosisGate()
        let controller = CPUDiagnosisController(source: { try await gate.run() })
        #expect(controller.start())
        await gate.waitUntilStarted()
        await gate.release(diagnosisPresentationFixture())
        await controller.waitForCompletion()
        #expect(controller.state.phase == .completed)
        #expect(controller.state.content.map(\.text).joined().contains("42001"))
        #expect(controller.start())
        #expect(!controller.state.content.map(\.text).joined().contains("42001"))
        await gate.waitUntilStarted()
        await gate.fail()
        await controller.waitForCompletion()
        #expect(controller.state.phase == .failed)
        #expect(controller.state.lines.map(\.text).joined().contains("collectionFailed"))
        #expect(!controller.state.content.map(\.text).joined().contains("42001"))
    }

    @Test func resultFormattingPreservesEvidenceAndKeepsHelperFlagOutOfCLI() async throws {
        let value = diagnosisPresentationFixture(available: true, helper: true, cpuCount: nil)
        let controller = CPUDiagnosisController(source: { value })
        #expect(controller.start())
        await controller.waitForCompletion()
        let text = controller.state.lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("Monitor helper"))
        #expect(text.contains("hostCapacityChanged"))
        #expect(!text.contains("of 800%"))
        #expect(text.contains("3/3 intervals"))
        #expect(text.contains("121.875% of the window"))
        #expect(text.contains(String(UInt64.max)))
        #expect(text.contains("11111111-1111-4111-8111-111111111111"))
        #expect(text.contains("not proof of exit"))
        #expect(text.contains("shared daemons"))
        #expect(!DiagnosisText.render(value).contains("Monitor helper"))
        #expect(!String(decoding: try JSONDiagnosis.encode(value), as: UTF8.self).contains("isMonitorHelper"))
        for width in [40, 60, 120] {
            var state = LiveReportState()
            state.diagnosis = controller.state
            let first = LiveReportLayout.lines(state: state, width: width, height: 12)
            #expect(first.count == 12)
            #expect(first.allSatisfy { TerminalCells.width($0.text) <= width })
            state.scrollDiagnosis(by: 10_000, width: width, height: 12)
            #expect(LiveReportLayout.lines(state: state, width: width, height: 12) != first)
            let small = LiveReportLayout.lines(state: state, width: 30, height: 5).map(\.text).joined()
            #expect(small.contains("Resize"))
            #expect(small.contains("Esc back") && small.contains("x cancel"))
        }
    }

    @Test func controllerPublicationDoesNotOverwriteViewportScroll() async {
        let value = diagnosisPresentationFixture(available: true)
        let controller = CPUDiagnosisController(source: { value })
        controller.start()
        await controller.waitForCompletion()
        var live = LiveReportState()
        live.diagnosis = controller.state
        live.scrollDiagnosis(by: 5, width: 40, height: 8)
        let offset = live.diagnosisOffset
        #expect(offset > 0)
        live.diagnosis = controller.state
        #expect(live.diagnosisOffset == offset)
        controller.start()
        live.diagnosis = controller.state
        #expect(live.diagnosisOffset == 0)
        await controller.stop()
    }

    @Test func liveFooterExplainsCleanupUntilAnotherDiagnosisCanStart() async {
        let gate = DiagnosisGate()
        let controller = CPUDiagnosisController(source: { try await gate.run() })
        controller.start()
        await gate.waitUntilStarted()
        controller.dismiss()
        #expect(!controller.start())
        var live = LiveReportState()
        live.diagnosis = controller.state
        for (width, height) in [(40, 8), (60, 12), (100, 24)] {
            let lines = LiveReportLayout.lines(state: live, width: width, height: height)
            #expect(
                lines.contains { $0.text.contains("diagnosis cleanup in progress") && $0.style == .muted })
            #expect(!lines.contains { $0.text.contains("d CPU diagnosis") })
            #expect(lines.contains { $0.text.contains("q/Ctrl-C quit") })
            if height < 24 { #expect(lines.contains { $0.text.contains("Resize for all keys") }) }
        }
        await gate.release(diagnosisPresentationFixture())
        await controller.waitForCompletion()
        live.diagnosis = controller.state
        let lines = LiveReportLayout.lines(state: live, width: 100, height: 24)
        #expect(lines.contains { $0.text.contains("d CPU diagnosis") })
        #expect(!lines.contains { $0.text.contains("cleanup in progress") })
    }

    @Test func guidanceExplainsWhenToRunAndHowToReadTheFixedResult() async throws {
        let controller = CPUDiagnosisController(source: { diagnosisPresentationFixture(available: true) })
        controller.start()
        let collecting = controller.state.lines.map(\.text).joined(separator: "\n")
        #expect(collecting.contains("slowdown"))
        #expect(collecting.contains("earlier"))
        #expect(controller.state.reportText == nil)
        await controller.waitForCompletion()
        let copied = try #require(controller.state.reportText)
        #expect(copied.contains("CPU-seconds"))
        #expect(copied.contains("live table"))
        #expect(copied.contains("coverage"))
        #expect(copied.contains(String(UInt64.max)))
        controller.dismiss()
        #expect(controller.state.reportText == nil)
    }

    @Test func stopCancelsAndWaitsForOwnedWork() async {
        let gate = DiagnosisGate()
        let controller = CPUDiagnosisController(source: { try await gate.run() })
        #expect(controller.start())
        await gate.waitUntilStarted()
        controller.dismiss()
        await gate.release(diagnosisPresentationFixture())
        await controller.stop()
        #expect(!controller.state.isRunning)
        #expect(controller.state.phase == .hidden)
    }
}

private actor DiagnosisGate {
    private var continuation: CheckedContinuation<CPUDiagnosis, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    func run() async throws -> CPUDiagnosis {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release(_ value: CPUDiagnosis) {
        continuation?.resume(returning: value)
        continuation = nil
    }
    func fail() {
        continuation?.resume(throwing: CPUDiagnosisError.collectionFailed)
        continuation = nil
    }
}
