import AgentMonitorCore
import AgentMonitorPresentation
import AgentMonitorTUI
import ArgumentParser
import Testing

@testable import AgentMonitor

@Test func versionRequestExitsSuccessfullyWithoutRunningTheMonitor() {
    do {
        _ = try AgentMonitorCommand.parse(["--version"])
        Issue.record("Expected the version request to exit before monitoring")
    } catch {
        #expect(AgentMonitorCommand.exitCode(for: error) == .success)
        #expect(AgentMonitorCommand.message(for: error) == AgentMonitorVersion.current)
    }
    #expect(AgentMonitorCommand.helpMessage().contains("--version"))
}

@Test func unrelatedProcessesRequireExplicitOptIn() throws {
    #expect(try !Options.parse([]).allProcesses)
    #expect(try Options.parse(["--all-processes"]).allProcesses)
}

@Test func generatedHelpDocumentsEveryPublicOptionAndSamplingSemantics() {
    let help = AgentMonitorCommand.helpMessage()
    for option in [
        "--cpu", "--memory-gb", "--interval", "--samples", "--json", "--json-schema", "--all-processes",
        "--commands", "--tui", "-tui", "--group", "--help",
    ] {
        #expect(help.contains(option))
    }
    let normalized = help.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    #expect(normalized.contains("CPU is averaged between snapshots"))
    #expect(normalized.contains("JSONL schema version 3"))
    #expect(normalized.contains("host occupancy beside your measured processes"))
    #expect(AgentGuide.render(.tui).contains("0 minimizes; 9 maximizes; = restores the chosen split"))
}

@Test func optionsAcceptEqualsSyntaxAndPreserveDefaults() throws {
    let defaults = try Options.parse([])
    #expect(defaults.cpu == 25)
    #expect(defaults.memoryGB == 1)
    #expect(defaults.interval == 1)
    #expect(defaults.samples == 1)
    #expect(!defaults.json)
    #expect(!defaults.commands)
    let options = try Options.parse(["--cpu=40", "--memory-gb=0.5", "--interval=2", "--samples=0"])
    #expect(options.cpu == 40)
    #expect(options.memoryGB == 0.5)
    #expect(options.interval == 2)
    #expect(options.samples == 0)
}

@Test func optionsAcceptExplicitThresholdsAndJSON() throws {
    let value = try Options.parse([
        "--cpu", "40", "--memory-gb", "0.1", "--interval", "0.5", "--samples", "3", "--json",
    ])
    #expect(value.cpu == 40)
    #expect(value.memoryGB == 0.1)
    #expect(value.interval == 0.5)
    #expect(value.samples == 3)
    #expect(value.json)
}

@Test(arguments: [
    ["--cpu", "nan"], ["--cpu", "-1"], ["--memory-gb", "inf"],
    ["--memory-gb", "1e30"], ["--interval", "0"], ["--samples", "-1"],
    ["--cpu"], ["--mystery"], ["--interval", "1000"],
])
func invalidOptionsThrow(arguments: [String]) {
    #expect(throws: (any Error).self) { try Options.parse(arguments) }
}

@Test func tuiIsExplicitContinuousByDefaultAndMutuallyExclusiveWithMachineOutput() throws {
    #expect(try Options.parse([]).samples == 1)
    #expect(try !Options.parse([]).tui)
    #expect(try Options.parse(["--tui"]).samples == 0)
    #expect(try Options.parse(["-tui"]).tui)
    #expect(try Options.parse(["--tui", "--samples", "2"]).samples == 2)
    #expect(throws: (any Error).self) { try Options.parse(["--tui", "--json"]) }
    #expect(throws: (any Error).self) { try Options.parse(["--tui", "--json-schema"]) }
}

@Test func helpDocumentsLiveThresholdSteps() {
    let help = AgentGuide.render(.tui)
    #expect(help.contains("1/2 lower/raise CPU by 10 percentage points"))
    #expect(help.contains("3/4 lower/raise footprint by 1 GB"))
}

// NO_COLOR is set when present and non-empty (https://no-color.org); pipes stay plain.
@Test(arguments: [
    (false, [String: String](), true, true), (true, [:], true, false),
    (false, ["NO_COLOR": "1"], true, false),
    (false, ["NO_COLOR": ""], true, true), (false, [:], false, false),
])
func colorFollowsTheFlagNoColorAndTheTerminal(
    flag: Bool, environment: [String: String], terminal: Bool, expected: Bool
) {
    #expect(ColorPolicy.enabled(noColor: flag, environment: environment, isTerminal: terminal) == expected)
}

@Test func noColorIsAcceptedEverywhereIncludingJSON() throws {
    #expect(try Options.parse(["--no-color"]).noColor)
    #expect(try Options.parse(["--json", "--no-color"]).noColor)
    #expect(try !Options.parse([]).noColor)
    for command in [
        ["kill", "--pid", "42"], ["focus", "--pid", "42"], ["message", "--pid", "42", "--text", "x"],
    ] {
        _ = try AgentMonitorCommand.parseAsRoot(command + ["--no-color"])
    }
    #expect(AgentMonitorCommand.helpMessage().contains("--no-color"))
}

@Test func disabledColorReachesTheTUIHostAsNoColor() {
    #expect(
        TerminalReport.hostEnvironment(color: false, base: ["TERM": "xterm"]) == [
            "TERM": "xterm", "NO_COLOR": "1",
        ])
    #expect(TerminalReport.hostEnvironment(color: true, base: ["TERM": "xterm"]) == ["TERM": "xterm"])
}

@Test func liveTUIRefreshDefaultsToFiveSecondsWithoutChangingBatchOrExplicitIntervals() throws {
    #expect(try Options.parse(["--tui"]).interval == 5)
    #expect(try Options.parse(["--tui", "--interval", "1"]).interval == 1)
    #expect(try Options.parse(["--json"]).interval == 1)
    #expect(try Options.parse([]).interval == 1)
}
