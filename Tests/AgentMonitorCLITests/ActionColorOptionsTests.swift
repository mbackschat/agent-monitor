import ArgumentParser
import Testing

@testable import AgentMonitor

@Suite struct ActionColorOptionsTests {
    @Test(arguments: ["kill", "message", "focus"], [true, false])
    func colorFlagSurvivesRootParsing(command: String, beforeCommand: Bool) throws {
        var arguments = [command, "--pid", "42"]
        if command == "message" { arguments += ["--text", "parser fixture"] }
        arguments.insert("--no-color", at: beforeCommand ? 0 : arguments.count)
        let parsed = try AgentMonitorCommand.parseAsRoot(arguments)
        switch parsed {
        case let action as KillCommand: #expect(action.color.noColor)
        case let action as MessageCommand: #expect(action.color.noColor)
        case let action as FocusCommand: #expect(action.color.noColor)
        default: Issue.record("Expected an action command")
        }
    }

    @Test func colorDefaultAndReportFlagRemainUnchanged() throws {
        let action = try #require(
            AgentMonitorCommand.parseAsRoot(["focus", "--pid", "42"]) as? FocusCommand)
        #expect(!action.color.noColor)
        #expect(try Options.parse(["--no-color"]).noColor)
        #expect(try !Options.parse([]).noColor)
    }
}
