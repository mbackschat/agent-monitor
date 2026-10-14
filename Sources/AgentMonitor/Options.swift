import AgentMonitorPresentation
import ArgumentParser

enum GroupOption: String, ExpressibleByArgument { case none, session }

struct Options: ParsableArguments {
    @Option(help: "Show CPU above this percentage; 100 means one occupied core.")
    var cpu: Double = 25

    @Option(name: .customLong("memory-gb"), help: "Show physical footprint above this many decimal GB.")
    var memoryGB: Double = 1

    @Option(help: "Seconds to wait between samples, from 0.1 to 60.")
    var interval: Double = 1

    @Option(
        name: .customLong("samples"),
        help: "Number of reports; 0 watches until Ctrl-C. Default: 1, or unlimited with --tui.")
    var sampleLimit: Int?

    var samples: Int { sampleLimit ?? (tui ? 0 : 1) }

    @Flag(
        name: [.long, .customLong("tui", withSingleDash: true)],
        help:
            "Live terminal report. Keys: arrows select; Enter details; g group; 1/2 lower/raise CPU by 10 percentage points; 3/4 lower/raise footprint by 1 GB; c/m/p sort CPU/memory/PID; r reverse; [/] scroll details; -/+ shrink/grow details by 5 percentage points (10-90%); 0 minimize; 9 maximize; = restore the chosen split (initially 50%); q quits. Requires an interactive terminal."
    )
    var tui = false

    @Option(
        help:
            "Group text/TUI by launch session: none or session. TUI: g toggles grouping; Enter expands a session or opens process details. Totals cover displayed heavy processes only. Not available with --json or --json-schema."
    )
    var group: GroupOption = .none

    var grouping: ReportGrouping { group == .session ? .session : .none }

    @Flag(help: "Emit JSONL: one complete JSON object per line/report, suitable for streaming.")
    var json = false

    @Flag(help: "Print the JSON Schema for one report and exit without sampling.")
    var jsonSchema = false

    @Flag(
        help:
            "Include unrelated and unattributed processes; heavy thresholds and same-user scope still apply.")
    var allProcesses = false

    @Flag(help: "Include command arguments; these can contain secrets.")
    var commands = false

    mutating func validate() throws {
        guard group == .none || (!json && !jsonSchema) else {
            throw ValidationError("--group session is for text/TUI; JSONL retains individual process records")
        }
        guard [json, jsonSchema, tui].filter({ $0 }).count <= 1 else {
            throw ValidationError("--tui, --json and --json-schema are separate output modes")
        }
        guard cpu.isFinite, cpu >= 0 else {
            throw ValidationError("--cpu requires a finite, nonnegative number")
        }
        guard memoryGB.isFinite, memoryGB >= 0,
            memoryGB < Double(UInt64.max) / 1_000_000_000
        else {
            throw ValidationError("--memory-gb must be finite, nonnegative, and fit in UInt64 bytes")
        }
        guard interval.isFinite, (0.1...60).contains(interval) else {
            throw ValidationError("--interval must be between 0.1 and 60 seconds")
        }
        guard samples >= 0 else {
            throw ValidationError("--samples requires an integer >= 0")
        }
    }
}
