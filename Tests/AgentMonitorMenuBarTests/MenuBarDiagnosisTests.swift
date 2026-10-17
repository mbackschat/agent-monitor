import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func nativeDiagnosisRespectsOpenActionAndPauseBoundaries() async throws {
    let snapshot = try menuBarFixture(pids: [42])
    let model = MenuBarModel(
        diagnosisSource: { try await menuBarDiagnosisFixture() },
        source: { _, _, _, receive in
            try await receive(snapshot)
        })
    model.setLiveIcon(false)
    #expect(!model.beginDiagnosis())
    model.open()
    await model.waitForCollection()
    model.selectRow(.process(snapshot.findings[0].process))
    model.toggleFreeze()
    let frozen = model.report
    _ = model.report.beginAction(.terminate)
    try #require(model.report.actionPanel != nil)
    #expect(!model.beginDiagnosis())
    _ = model.report.actionInput(.escape)
    #expect(model.beginDiagnosis())
    #expect(!model.handleShortcut("p", row: nil))
    #expect(!model.canBegin(.terminate, row: .process(snapshot.findings[0].process)))
    await model.diagnosis.waitForCompletion()
    #expect(model.diagnosis.state.phase == .completed)
    #expect(model.report.snapshot == frozen.snapshot)
    #expect(model.report.history == frozen.history)
    #expect(model.report.frozen)
    #expect(model.report.selection == frozen.selection)
    model.diagnosis.dismiss()
    #expect(model.report.frozen)
    await model.stop()
}

@Test @MainActor func nativeDismissReopenCannotReceiveAnOldDiagnosis() async throws {
    let gate = NativeDiagnosisGate()
    let model = MenuBarModel(diagnosisSource: { try await gate.run() }, source: { _, _, _, _ in })
    model.open()
    #expect(model.beginDiagnosis())
    await gate.waitUntilStarted()
    model.close()
    #expect(model.diagnosis.state.phase == .hidden)
    model.open()
    #expect(!model.beginDiagnosis())
    await gate.release(try await menuBarDiagnosisFixture())
    await model.diagnosis.waitForCompletion()
    #expect(model.diagnosis.state.phase == .hidden)
    #expect(model.diagnosis.state.content.isEmpty)
    await model.stop()
}

@Test @MainActor func detachmentKeepsDiagnosisButClosingTheDetachedWindowCancelsIt() async throws {
    let gate = NativeDiagnosisGate()
    let model = MenuBarModel(diagnosisSource: { try await gate.run() }, source: { _, _, _, _ in })
    let delegate = MenuBarDelegate(model: model)
    model.open()
    #expect(model.beginDiagnosis())
    await gate.waitUntilStarted()
    delegate.popoverWillClose(
        Notification(
            name: NSPopover.willCloseNotification,
            userInfo: [NSPopover.closeReasonUserInfoKey: NSPopover.CloseReason.detachToWindow.rawValue]))
    #expect(model.isOpen)
    #expect(model.diagnosis.state.phase == .collecting)
    delegate.popoverWillClose(
        Notification(
            name: NSPopover.willCloseNotification,
            userInfo: [NSPopover.closeReasonUserInfoKey: NSPopover.CloseReason.standard.rawValue]))
    #expect(!model.isOpen)
    #expect(model.diagnosis.state.phase == .hidden)
    await gate.release(try await menuBarDiagnosisFixture())
    await model.stop()
}

func menuBarDiagnosisFixture(processCount: Int = 1) async throws -> CPUDiagnosis {
    let reader = NativeDiagnosisFixture(processCount: processCount)
    return try await CPUDiagnosisSession(reader: reader, clock: reader, excluding: [99], monitorPID: 99).run()
}

private final class NativeDiagnosisFixture: DiagnosisReading, SamplingClock, Sendable {
    private let index = Mutex(0)
    let processCount: Int

    init(processCount: Int) { self.processCount = processCount }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let tick = index.withLock { value in
            defer { value += 1 }
            return value
        }
        let samples = (0..<processCount).map { offset in
            let name = offset == 0 ? "compiler" : "worker"
            return ProcessSample(
                identity: ProcessIdentity(pid: 42001 + Int32(offset), startMicroseconds: 1), parentPID: 99,
                executable: "/fixture/" + name, name: name, sampledAt: 10 + Double(tick),
                cpuSeconds: Double(tick) / Double(offset + 1), footprintBytes: 1_200_000)
        }
        return ProcessSnapshot(
            samples: samples, enumeratedCount: samples.count, unreadableCount: 0,
            listedAt: 10 + Double(tick), scanSeconds: 0.05, hostCounters: nil, logicalCPUCount: 8)
    }
    func observation(for sample: ProcessSample) -> DiagnosisObservation { .observed(ProcessMetadata()) }
    func isCurrent(_ sample: ProcessSample) -> Bool { true }
    func wait(seconds: Double) async throws { try Task.checkCancellation() }
    func now() -> Date { Date(timeIntervalSince1970: 100 + Double(index.withLock { $0 })) }
}

private actor NativeDiagnosisGate {
    private var continuation: CheckedContinuation<CPUDiagnosis, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    func run() async throws -> CPUDiagnosis {
        try await withCheckedThrowingContinuation {
            continuation = $0
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
}

@Test(arguments: [DiagnosisViewState.Phase.collecting, .completed, .failed, .cancelled], [false, true])
@MainActor func nativeDiagnosisPanelKeepsItsSize(phase: DiagnosisViewState.Phase, dark: Bool) async throws {
    let gate = NativeDiagnosisGate()
    let model = MenuBarModel(
        diagnosisSource: {
            switch phase {
            case .completed: return try await menuBarDiagnosisFixture(processCount: 2)
            case .failed: throw CPUDiagnosisError.collectionFailed
            default: return try await gate.run()
            }
        }, source: { _, _, _, _ in })
    model.open()
    #expect(model.beginDiagnosis())
    switch phase {
    case .collecting, .cancelled:
        await gate.waitUntilStarted()
        if phase == .cancelled { model.diagnosis.cancel() }
    default: await model.diagnosis.waitForCompletion()
    }
    #expect(model.diagnosis.state.phase == phase)
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize == NSSize(width: 420, height: 560))
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_DIAGNOSIS_PREVIEW_DIRECTORY"] {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                "diagnosis-\(phase.rawValue)-\(dark ? "dark" : "light").png"))
    }
    if phase == .collecting || phase == .cancelled { await gate.release(try await menuBarDiagnosisFixture()) }
    await model.stop()
}

@Test @MainActor func diagnosisCopiesOnlyTheCompletedFixedReportAndClearsStatusOnRerun() async throws {
    let gate = NativeDiagnosisGate()
    let model = MenuBarModel(diagnosisSource: { try await gate.run() }, source: { _, _, _, _ in })
    var copied: [String] = []
    func copy() -> Bool {
        model.copyDiagnosisReport(using: {
            copied.append($0)
            return true
        })
    }
    #expect(!copy())
    model.open()
    #expect(model.beginDiagnosis())
    await gate.waitUntilStarted()
    #expect(!copy())
    #expect(copied.isEmpty)
    await gate.release(try await menuBarDiagnosisFixture())
    await model.diagnosis.waitForCompletion()
    #expect(copy())
    let text = try #require(copied.first)
    #expect(text == model.diagnosis.state.reportText)
    #expect(text.contains("42001/1 [Monitor helper]"))
    #expect(text.contains("CPU diagnosis:") && text.contains("Host coverage:"))
    #expect(text.contains("not proof of current use"))
    #expect(text.contains("CPU-s"))
    #expect(model.diagnosisCopyStatus == "Copied")
    let failedCopy = model.copyDiagnosisReport(using: { _ in false })
    #expect(!failedCopy)
    #expect(model.diagnosisCopyStatus == "Copy failed")
    #expect(model.beginDiagnosis())
    await gate.waitUntilStarted()
    #expect(model.diagnosisCopyStatus == nil)
    #expect(!copy())
    model.diagnosis.cancel()
    #expect(!copy())
    await gate.release(try await menuBarDiagnosisFixture())
    await model.diagnosis.waitForCompletion()
    model.close()
    #expect(!copy())
    #expect(copied.count == 1)
    await model.stop()
}

@Test(arguments: [false, true])
@MainActor func diagnosisContributorCardsWrapWithinThePanel(dark: Bool) async throws {
    let controller = CPUDiagnosisController(source: { try await menuBarDiagnosisFixture(processCount: 2) })
    controller.start()
    await controller.waitForCompletion()
    let sections = controller.state.sections.filter { $0.kind == .contributor }
    #expect(sections.count == 2)
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: VStack(spacing: 12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { entry in
                MenuBarDiagnosisSection(section: entry.element)
            }
        }.padding(16).frame(width: 420).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width == 420)
    #expect(host.fittingSize.height > 200)
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_DIAGNOSIS_PREVIEW_DIRECTORY"] {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                "diagnosis-contributors-\(dark ? "dark" : "light").png"))
    }
}
