import AgentMonitorCore
import AgentMonitorPresentation
import ArgumentParser
import Foundation

struct GuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guide",
        abstract: "Local workflow and interpretation guidance; no collection or provider queries.")

    @OptionGroup(visibility: .private) var report: ReportOptions
    @OptionGroup(visibility: .private) var output: JSONOptions

    @Argument(help: "Optional topic: semantics, diagnostics, actions or tui.")
    var topic: String?

    mutating func validate() throws {
        guard !report.isSpecified, !output.json, !output.jsonSchema else {
            throw ValidationError("guide accepts only an optional topic; report options do not apply")
        }
        if let topic, AgentGuide.Topic(rawValue: topic) == nil {
            throw ValidationError("guide topic must be semantics, diagnostics, actions or tui")
        }
    }

    var rendered: String { AgentGuide.render(topic.flatMap(AgentGuide.Topic.init(rawValue:))) }
    mutating func run() { print(rendered) }
}

struct DiagnoseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose", abstract: "Collect a finite resource diagnosis.",
        subcommands: [DiagnoseCPUCommand.self])
}

struct DiagnoseCPUCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cpu",
        abstract: "Rank the top ten observed CPU contributors over three one-second waits.",
        discussion:
            "Scans and bounded provider lookups add time. Includes readable current-user lifetimes, excluding this monitor. See agent-monitor guide semantics for coverage and attribution limits."
    )

    @OptionGroup var output: JSONOptions
    @OptionGroup(visibility: .private) var report: ReportOptions

    var json: Bool { output.json }
    var jsonSchema: Bool { output.jsonSchema }

    mutating func validate() throws {
        guard !report.isSpecified else {
            throw ValidationError("diagnose cpu has fixed defaults; report options do not apply")
        }
        guard !(json && jsonSchema) else {
            throw ValidationError("--json and --json-schema are separate output modes")
        }
    }

    mutating func run() async throws {
        if jsonSchema {
            try FileHandle.standardOutput.write(contentsOf: JSONDiagnosis.schema())
            return
        }
        try await Self.execute(
            json: json,
            collect: CPUDiagnosisSession.collectLocal,
            output: { try FileHandle.standardOutput.write(contentsOf: $0) },
            error: { try FileHandle.standardError.write(contentsOf: $0) })
    }

    static func execute(
        json: Bool, collect: @Sendable () async throws -> CPUDiagnosis,
        output: @Sendable (Data) throws -> Void, error writeError: @Sendable (Data) throws -> Void
    ) async throws {
        let data: Data
        do {
            let result = try await collect()
            data = try json ? JSONDiagnosis.encode(result) : Data(DiagnosisText.render(result).utf8)
        } catch CPUDiagnosisError.collectionFailed {
            try writeError(Data((DiagnosisText.collectionFailure + "\n").utf8))
            throw ExitCode.failure
        }
        var line = data
        line.append(10)
        try output(line)
    }
}
