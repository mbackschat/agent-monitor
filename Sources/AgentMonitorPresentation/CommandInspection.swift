import AgentMonitorCore
import Foundation
import Observation

public struct CommandInspection: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case reading, available, unavailable }
    public let process: ProcessIdentity
    public let executable: String
    public var status: Status
    public var arguments: [String]?
    public var readAt: Date?

    public var summary: String {
        switch status {
        case .reading: return "Arguments · reading…"
        case .unavailable: return "Arguments unavailable · process changed, exited or could not be read"
        case .available:
            return "Arguments · read on demand"
                + (readAt.map { " · " + $0.formatted(date: .omitted, time: .standard) } ?? "")
        }
    }

    public var lines: [String] {
        [summary] + (arguments ?? []).enumerated().map { "[\($0.offset)] \($0.element)" }
    }
}

@MainActor @Observable
public final class CommandInspectionController {
    public typealias Source = @Sendable (HeavyProcess) async throws -> [String]?
    public private(set) var state: CommandInspection?
    public private(set) var isReading = false
    @ObservationIgnored public var onChange: (@MainActor (CommandInspection?) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request: UUID?
    @ObservationIgnored private let source: Source

    public init(source: @escaping Source = NativeProcessReader.inspectCommand) { self.source = source }

    @discardableResult public func start(_ row: HeavyProcess) -> Bool {
        guard !row.isHistorical, !isReading else { return false }
        let token = UUID()
        request = token
        isReading = true
        state = CommandInspection(process: row.process, executable: row.executable, status: .reading)
        onChange?(state)
        task = Task {
            defer { isReading = false }
            let arguments = try? await source(row)
            guard !Task.isCancelled, request == token else { return }
            state?.arguments = arguments
            state?.readAt = Date()
            state?.status = arguments == nil ? .unavailable : .available
            onChange?(state)
        }
        return true
    }

    public func reconcile(with report: LiveReportState) {
        guard let state else { return }
        guard let row = report.commandInspectionTarget,
            row.process == state.process, row.executable == state.executable
        else {
            dismiss()
            return
        }
    }

    public func dismiss() {
        request = nil
        task?.cancel()
        state = nil
        onChange?(nil)
    }

    public func wait() async { await task?.value }
}

extension LiveReportState {
    public var commandInspectionTarget: HeavyProcess? {
        guard !showsOverview, !diagnosis.isVisible, actionPanel == nil,
            let selected, expanded == selected, detailsMode != .minimized
        else { return nil }
        return snapshot?.findings.first { $0.process == selected && !$0.isHistorical }
    }
}
