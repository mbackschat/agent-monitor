import AgentMonitorCore
import AgentMonitorPresentation
import AgentMonitorTUI
import ArgumentParser
import Darwin
import Foundation

@main
struct AgentMonitorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-monitor",
        abstract: "Trace heavy CPU and memory usage to coding-agent sessions on macOS.",
        discussion: """
            CPU OR memory must exceed the threshold. Only the current user's processes
            are inspected. CPU is averaged between snapshots; memory is a snapshot.
            Without options, one report follows a one-second baseline interval.
            Only agent-associated heavy consumers appear by default; --all-processes includes others.
            Unresolved agent sessions stay visible; nonterminal origins are labeled separately.
            Session markers show launch origin, not who currently uses a shared daemon.

            Examples:
              agent-monitor --json --samples 0 --interval 2
              agent-monitor --json-schema
              agent-monitor --tui --group session
              agent-monitor --all-processes --cpu 40 --memory-gb 0.5
              agent-monitor message --pid 42001 --text "Why is this so busy?"
            """,
        version: "0.1.0",
        subcommands: [KillCommand.self, MessageCommand.self, FocusCommand.self]
    )

    @OptionGroup var options: Options

    mutating func run() async throws {
        do {
            try await Self.run(options)
        } catch is CancellationError {
            return
        }
    }

    private static func run(_ options: Options) async throws {
        if options.jsonSchema {
            try FileHandle.standardOutput.write(contentsOf: JSONReport.schema())
            return
        }
        if options.tui, isatty(STDIN_FILENO) != 1 || isatty(STDOUT_FILENO) != 1 {
            throw ValidationError("--tui requires interactive stdin and stdout; use --json for pipes")
        }
        let configuration = try MonitoringConfiguration(
            thresholds: Thresholds(
                cpuPercent: options.cpu, memoryBytes: UInt64(options.memoryGB * 1_000_000_000)),
            intervalSeconds: options.interval, samples: options.samples, includeCommands: options.commands,
            scope: options.allProcesses ? .allProcesses : .agentsOnly)
        let session = MonitoringSession(
            configuration: configuration, reader: try NativeProcessReader(), excluding: [getpid()])
        if options.tui {
            try await TerminalReport.run(session: session, grouping: options.grouping)
            return
        }
        try await session.run { snapshot in
            if options.json {
                try FileHandle.standardOutput.write(contentsOf: JSONReport.encodeLine(snapshot))
            } else {
                print(TextReport.render(snapshot, grouping: options.grouping))
            }
        }
    }
}
