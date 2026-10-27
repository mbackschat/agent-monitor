import AgentMonitorCore
import AgentMonitorPresentation
import ArgumentParser
import Testing

@testable import AgentMonitor

@Suite struct AdaptiveSamplingOptionsTests {
    @Test func defaultOffPreservesExplicitIntervalsAndUnlimitedTUIReports() throws {
        let defaults = try Options.parse(["--tui"])
        #expect(defaults.sampling == SamplingSettings())
        #expect(defaults.samples == 0)
        let fixed = try #require(Options.parse(["--tui", "--interval", "1"]).sampling)
        #expect(!fixed.enabled)
        #expect(fixed.visibleMaximum == 1)
        #expect(try Options.parse([]).sampling == nil)
        #expect(try Options.parse(["--json", "--interval", "2"]).sampling == nil)
    }

    @Test func enablingUsesTheIntervalAsTheVisibleMaximum() throws {
        let settings = try #require(
            Options.parse([
                "--tui", "--adaptive-sampling", "--interval=1", "--sampling-minimum=0.25",
                "--sampling-window=30",
            ]).sampling)
        #expect(settings.enabled)
        #expect(settings.minimum == 0.25)
        #expect(settings.visibleMaximum == 1)
        #expect(settings.window == 30)
        #expect(settings.closedMultiplier == 1)
    }

    @Test func boundsAndWindowDoNotImplicitlyEnableAdaptation() throws {
        for flags in [[], ["--no-adaptive-sampling"]] {
            let settings = try #require(
                Options.parse(
                    [
                        "--tui", "--interval", "2", "--sampling-minimum", "0.5", "--sampling-window", "1",
                    ] + flags
                ).sampling)
            #expect(!settings.enabled)
            #expect(settings.minimum == 0.5)
            #expect(settings.visibleMaximum == 2)
            #expect(settings.window == 1)
        }
    }

    @Test func explicitOffIsRetainedAsAPresentReportOption() throws {
        var report = try ReportOptions.parse(["--tui", "--no-adaptive-sampling"])
        report.tui = false
        #expect(report.isSpecified)
    }

    @Test(arguments: [
        ["--adaptive-sampling"], ["--no-adaptive-sampling"], ["--sampling-minimum", "0.1"],
        ["--sampling-window", "60"], ["--json", "--no-adaptive-sampling"],
        ["--tui", "--adaptive-sampling", "--no-adaptive-sampling"],
        ["--tui", "--no-adaptive-sampling", "--adaptive-sampling"],
        ["--tui", "--sampling-minimum", "0.25"],
        ["--tui", "--sampling-minimum", "0.01"],
        ["--tui", "--sampling-minimum", "nan"],
        ["--tui", "--sampling-window", "0"], ["--tui", "--sampling-window", "301"],
        ["--tui", "--sampling-window", "inf"],
    ]) func invalidSettingsAreRejectedTogether(arguments: [String]) {
        #expect(throws: (any Error).self) { try Options.parse(arguments) }
    }

    @Test(arguments: [
        ["diagnose", "cpu", "--tui", "--no-adaptive-sampling"],
        ["--tui", "--no-adaptive-sampling", "diagnose", "cpu"],
        ["diagnose", "cpu", "--tui", "--sampling-minimum", "0.1"],
        ["diagnose", "cpu", "--tui", "--sampling-window", "60"],
    ]) func explicitOffAndDefaultValuedSettingsRemainReportOptions(arguments: [String]) {
        #expect(throws: (any Error).self) { try AgentMonitorCommand.parseAsRoot(arguments) }
    }

    @Test func generatedHelpStatesTheModeAndBounds() {
        let help = AgentMonitorCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(
            separator: " ")
        for flag in [
            "--adaptive-sampling", "--no-adaptive-sampling", "--sampling-minimum", "--sampling-window",
        ] {
            #expect(help.contains(flag))
        }
        #expect(help.contains("visible maximum"))
        #expect(help.contains("Default: off"))
        #expect(AgentGuide.render(.tui).contains("visible maximum"))
    }
}

@Suite struct AdaptiveSamplingPresentationTests {
    @Test func stateUsesAndPreservesCompleteSettingsAcrossCollectionReset() {
        let settings = SamplingSettings(
            enabled: true, minimum: 0.25, visibleMaximum: 5, closedMultiplier: 2.5, window: 30)
        var state = LiveReportState(interval: 1, sampling: settings)
        #expect(state.interval == 5)
        #expect(state.samplingSettings == settings)
        state.resetCollection()
        #expect(state.samplingSettings == settings)
    }

    @Test func intervalChangesPreserveAdaptiveConfigurationAndRejectInvalidBounds() {
        let settings = SamplingSettings(
            enabled: true, minimum: 0.5, visibleMaximum: 5, closedMultiplier: 2.5, window: 30)
        var state = LiveReportState(sampling: settings)
        state.setInterval(2)
        #expect(state.interval == 2)
        #expect(state.samplingSettings.minimum == 0.5)
        #expect(state.samplingSettings.closedMultiplier == 2.5)
        #expect(state.samplingSettings.window == 30)
        #expect(state.samplingSettings.enabled)
        for invalid in [0.25, 30, .infinity, .nan] {
            state.setInterval(invalid)
            #expect(state.interval == 2)
        }
    }

    @Test func invalidSettingsLeaveThePreviousConfigurationUntouched() {
        var state = LiveReportState(interval: 1)
        let initial = state.samplingSettings
        var invalid = initial
        invalid.minimum = 2
        let invalidAccepted = state.setSamplingSettings(invalid)
        #expect(!invalidAccepted)
        #expect(state.samplingSettings == initial)
        let valid = SamplingSettings(enabled: true, visibleMaximum: 2)
        let validAccepted = state.setSamplingSettings(valid)
        #expect(validAccepted)
        #expect(state.samplingSettings == valid)
    }

    @Test func intervalStepsRespectTheMinimumAndDerivedClosedMaximumEvenWhenDisabled() {
        var state = LiveReportState(
            sampling: SamplingSettings(minimum: 0.4, visibleMaximum: 0.5, closedMultiplier: 2.5))
        state.adjustInterval(.faster)
        #expect(state.interval == 0.5)
        for _ in 0..<10 { state.adjustInterval(.slower) }
        #expect(state.interval == 10)
        state.adjustInterval(.slower)
        #expect(state.interval == 10)
        state.setInterval(3)
        state.adjustInterval(.faster)
        #expect(state.interval == 2)
        state.adjustInterval(.slower)
        #expect(state.interval == 5)
    }

    @Test func adaptiveHeaderIdentifiesTheConfiguredMaximum() {
        let state = LiveReportState(sampling: SamplingSettings(enabled: true, visibleMaximum: 2))
        let lines = LiveReportLayout.lines(state: state, width: 120, height: 24)
        #expect(lines.first?.text.contains("max 2 s") == true)
        #expect(lines.first?.text.contains("every 2 s") == false)
    }
}
