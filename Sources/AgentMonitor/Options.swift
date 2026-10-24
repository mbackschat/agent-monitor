import AgentMonitorPresentation
import ArgumentParser

enum GroupOption: String, ExpressibleByArgument { case none, session }

/// Reusing the same group preserves flags consumed by Argument Parser's root command.
struct ColorOption: ParsableArguments {
    @Flag(help: "Disable colors in text, TUI and action output, like NO_COLOR. JSON is never colored.")
    var noColor = false
}

struct ReportOptions: ParsableArguments {
    @Option(
        name: .customLong("cpu"),
        help:
            "Show CPU above this percentage; 100 means one occupied core. Default: 0. Both thresholds at zero show every observed process."
    )
    var requestedCPU: Double?

    var cpu: Double { requestedCPU ?? 0 }

    @Option(
        name: .customLong("memory-gb"),
        help:
            "Show physical footprint above this many decimal GB. Default: 0. Both thresholds at zero show every observed process."
    )
    var requestedMemoryGB: Double?

    var memoryGB: Double { requestedMemoryGB ?? 0 }

    @Option(
        name: .customLong("interval"),
        help:
            "Requested acquisition period in seconds, from 0.1 to 60. Default: 0.1; scan overruns delay collection."
    )
    var requestedInterval: Double?

    var interval: Double { requestedInterval ?? 0.1 }

    @Option(
        name: .customLong("samples"),
        help: "Number of reports; 0 watches until Ctrl-C. Default: 1, or unlimited with --tui.")
    var sampleLimit: Int?

    var samples: Int { sampleLimit ?? (tui ? 0 : 1) }

    @Flag(
        name: [.long, .customLong("tui", withSingleDash: true)],
        help:
            "Live terminal report in Stable order; requires an interactive terminal. See agent-monitor guide tui for all keys."
    )
    var tui = false

    @Option(
        name: .customLong("group"),
        help:
            "Group text/TUI by launch session: none or session. TUI: g toggles grouping; left/right collapses/expands a session or process details. Totals include all observed session members, independent of display filters. Not available with --json or --json-schema. Default: none."
    )
    var requestedGroup: GroupOption?

    var group: GroupOption { requestedGroup ?? .none }

    var grouping: ReportGrouping { group == .session ? .session : .none }

    @Flag(
        help:
            "Include unrelated and unattributed processes; display thresholds and same-user scope still apply."
    )
    var allProcesses = false

    @Flag(help: "Include command arguments; these can contain secrets.")
    var commands = false

    @OptionGroup var color: ColorOption

    var noColor: Bool { color.noColor }

    var isSpecified: Bool {
        requestedCPU != nil || requestedMemoryGB != nil || requestedInterval != nil || sampleLimit != nil
            || requestedGroup != nil || tui || allProcesses || commands || noColor
    }

    mutating func validate() throws {
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

/// Argument Parser 1.8.2's OptionGroup.init(from:) reuses previously decoded groups.
/// Sharing this group preserves output flags that the parent parser consumes before descent.
struct JSONOptions: ParsableArguments {
    @Flag(
        help:
            "Emit machine JSON: reports use JSONL schema version 5; CPU diagnosis uses one version 1 document."
    )
    var json = false

    @Flag(help: "Print this command's JSON Schema and exit without collection.")
    var jsonSchema = false
}

struct Options: ParsableArguments {
    @OptionGroup var report: ReportOptions
    @OptionGroup var output: JSONOptions

    var cpu: Double { report.cpu }
    var memoryGB: Double { report.memoryGB }
    var interval: Double { report.interval }
    var samples: Int { report.samples }
    var tui: Bool { report.tui }
    var group: GroupOption { report.group }
    var grouping: ReportGrouping { report.grouping }
    var allProcesses: Bool { report.allProcesses }
    var commands: Bool { report.commands }
    var noColor: Bool { report.noColor }
    var json: Bool { output.json }
    var jsonSchema: Bool { output.jsonSchema }

    mutating func validate() throws {
        guard group == .none || (!json && !jsonSchema) else {
            throw ValidationError("--group session is for text/TUI; JSONL retains individual process records")
        }
        guard [json, jsonSchema, tui].filter({ $0 }).count <= 1 else {
            throw ValidationError("--tui, --json and --json-schema are separate output modes")
        }
    }
}
