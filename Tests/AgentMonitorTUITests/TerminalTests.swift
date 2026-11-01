import Darwin
import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@Test
func terminalRefreshDisclosureResizeAndRestoration() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 100, height: 24), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let pid = try launch(binary, terminal: terminal.slave)
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("Updates: 1") && $0.contains("fixture-42")
    }
    try writeAllBytes(Array("ht".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Memory[h]") && $0.contains("1h[t]") && $0.contains("2.4 GB") }
    try writeAllBytes(Array("hht".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("CPU[h]") && $0.contains("10m[t]") }
    try writeAllBytes(Array("\u{1b}[C\u{1b}[Cn".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID ↑") && $0.contains("Details min") && !$0.contains("Runtime: 1234")
    }
    try writeAllBytes(Array("i".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Runtime: 1234") && $0.contains("PID 42 |")
            && $0.range(of: "Updates: ([2-9]|[1-9][0-9]+)( |\n)", options: .regularExpression) != nil
            && dividerRow($0) != nil
    }
    for width in [120, 200, 80, 100] {
        var resized = winsize(ws_row: 24, ws_col: UInt16(width), ws_xpixel: 0, ws_ypixel: 0)
        try #require(ioctl(terminal.slave, TIOCSWINSZ, &resized) == 0)
        screen = ANSIVisibleScreen(size: .init(width: width, height: 24))
        try #require(kill(pid, SIGWINCH) == 0)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            let rows = $0.split(separator: "\n", omittingEmptySubsequences: false)
            guard let header = rows.firstIndex(where: { $0.contains("CPU%") }),
                let divider = dividerRow($0),
                let footer = rows.lastIndex(where: { $0.contains("v view") })
            else { return false }
            return $0.contains("PID 42 |") && header < divider && divider < footer
                && $0.contains("v view") && $0.contains("g group") && $0.contains("? help")
        }
    }
    try writeAllBytes(Array("c".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("CPU ↓") }
    try writeAllBytes(Array("o".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Stable order") && $0.contains("PID 42 |") }
    try writeAllBytes(Array("n".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID ↑") && $0.contains("PID 42 |")
    }
    try writeAllBytes(Array("r".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID ↓") && $0.contains("PID 42 |")
    }
    for (key, label) in [
        ("+", "Details | pane 55%"), ("M", "Details max"), ("i", "Details min"),
        ("=", "Details | pane 55%"), ("-", "Details | pane 50%"),
    ] {
        try writeAllBytes(Array(key.utf8), to: terminal.master)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            $0.contains(label) && dividerRow($0) != nil
                && (key != "M" || !$0.contains("fixture-84"))
                && (key != "i" || !$0.contains("PID 42 |"))
        }
    }
    var size = winsize(ws_row: 16, ws_col: 60, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &size) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 60, height: 16))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID ↓") && $0.contains("PID 42 |") && $0.contains("unresolved")
            && dividerRow($0) != nil
    }
    try writeAllBytes(Array(String(repeating: "\u{1b}[6~", count: 4).utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("x read arguments on demand") && !$0.contains("PID 42 |")
    }
    try writeAllBytes(Array("[".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Candidates:") && !$0.contains("PID 42 |") }
    try writeAllBytes(Array(String(repeating: "\u{1b}[5~", count: 4).utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID 42 |")
    }
    try writeAllBytes(Array("\u{1b}[D\u{1b}[Di".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("fixture-42") && $0.contains("Details min") && !$0.contains("Runtime: 1234")
    }
    // Complete identity/resource blocks need eight rows for two expanded singleton groups.
    // Exercise bulk disclosure with room for all rows, then restore the small inspection viewport.
    size.ws_row = 24
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &size) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 60, height: 24))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("fixture-42") && $0.contains("fixture-84") && $0.contains("q/Ctrl-C quit") }
    try writeAllBytes(Array("g".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("2 launch groups") && $0.contains("▸") && !$0.contains("fixture-42")
    }
    try writeAllBytes(Array("\u{1b}[1;2C".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("fixture-42") && $0.contains("fixture-84") && $0.contains("▾")
            && $0.contains("└─") && $0.contains("#1")
    }
    try writeAllBytes(Array("\u{1b}[1;2D".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { !$0.contains("fixture-42") && !$0.contains("fixture-84") && $0.contains("▸") }
    try writeAllBytes(Array("\u{1b}[C\u{1b}[C".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("▾") && $0.contains("fixture-42") && !$0.contains("fixture-84")
    }
    try writeAllBytes(Array("\u{1b}[Bi".utf8), to: terminal.master)
    size.ws_row = 16
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &size) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 60, height: 16))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID 42 |") && dividerRow($0) != nil
    }
    try writeAllBytes(Array("g".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("fixture-42") && !$0.contains("launch groups") && $0.contains("Details | pane 50%")
    }
    try writeAllBytes(Array("i".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("fixture-42") && $0.contains("fixture-84") && $0.contains("Details min") }
    for (keys, filter, empty) in [
        ("44" + String(repeating: "2", count: 10), "CPU > 100.00% OR footprint > 2.00 GB", true),
        (String(repeating: "1", count: 10), "footprint > 2.00 GB", true),
        ("3", "footprint > 1.00 GB", false),
        ("3", "All observed processes", false),
    ] {
        try writeAllBytes(Array(keys.utf8), to: terminal.master)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            $0.components(separatedBy: "\n").contains(filter)
                && !$0.contains("pending")
                && $0.contains("No processes match") == empty
                && (empty || ($0.contains("fixture-42") && $0.contains("fixture-84")))
                && $0.contains("v view") && $0.contains("g group") && $0.contains("? help")
        }
    }
    try writeAllBytes([3], to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}

private func assertCleanExit(
    _ pid: pid_t, terminal: RealTerminalPTYPair, original: termios, reaped: inout Bool
) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    var status: Int32 = 0
    var cleanup: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 8192)
    while ContinuousClock.now < deadline {
        // TerminalPOSIXController.restore uses TCSAFLUSH: the PTY peer must
        // drain pending output before terminal restoration can finish.
        let count = read(terminal.master, &buffer, buffer.count)
        if count > 0 { cleanup.append(contentsOf: buffer.prefix(count)) }
        let result = waitpid(pid, &status, WNOHANG)
        try #require(result >= 0)
        if result == pid {
            reaped = true
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(reaped, "Owned fixture must exit within four seconds of quitting")
    #expect(status == 0)
    let cleanupText = String(decoding: cleanup, as: UTF8.self)
    #expect(cleanupText.contains("\u{1B}[?1049l"))
    #expect(cleanupText.contains("\u{1B}[?25h"))
    var restored = termios()
    try #require(tcgetattr(terminal.slave, &restored) == 0)
    #expect(restored.c_lflag == original.c_lflag)
    #expect(restored.c_iflag == original.c_iflag)
    #expect(restored.c_oflag == original.c_oflag)
    #expect(restored.c_cflag == original.c_cflag)
}

private func launch(
    _ binary: String, terminal: Int32, environment additions: [String: String] = [:],
    removingEnvironment: Set<String> = []
) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?
    try #require(posix_spawn_file_actions_init(&actions) == 0)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for descriptor: Int32 in 0...2 {
        try #require(posix_spawn_file_actions_adddup2(&actions, terminal, descriptor) == 0)
    }
    let environment = ProcessInfo.processInfo.environment
        .filter { !removingEnvironment.contains($0.key) }
        .merging(["TERM": "xterm-256color"]) { _, new in new }
        .merging(additions) { _, new in new }
    var arguments = [strdup(binary), nil]
    var variables = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        for argument in arguments { free(argument) }
        for variable in variables { free(variable) }
    }
    var pid: pid_t = 0
    try #require(posix_spawn(&pid, binary, &actions, nil, &arguments, &variables) == 0)
    return pid
}

private func dividerRow(_ text: String) -> Int? {
    text.split(separator: "\n", omittingEmptySubsequences: false).firstIndex { $0.contains("─ Details") }
}

@Test func terminalHelpAndDiagnosticsScrollAndReturnToPausedSelection() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 120, height: 24), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let pid = try launch(binary, terminal: terminal.slave)
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 120, height: 24))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) { $0.contains("fixture-42") && $0.contains("? help") }
    try writeAllBytes(Array("pi?".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Keyboard shortcuts") && $0.contains("Esc back") }
    try writeAllBytes(Array("G".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Help & glossary") && $0.contains("Processes / Procs") && $0.contains("Esc back") }
    var small = winsize(ws_row: 12, ws_col: 40, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &small) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 40, height: 12))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Help & glossary") && $0.contains("D diagnostics")
            && $0.contains("Processes / Procs")
    }
    for (down, up) in [([UInt8(100)], [UInt8(117)]), ([UInt8(4)], [UInt8(21)])] {
        try writeAllBytes(down, to: terminal.master)
        _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
            $0.contains("5–12/")
        }
        try writeAllBytes(up, to: terminal.master)
        _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
            $0.contains("1–8/")
        }
    }
    try writeAllBytes([32], to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("5–12/") && !$0.contains("Processes / Procs")
    }
    try writeAllBytes(Array("\u{1b}[32;2u".utf8), to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("1–8/") && $0.contains("Processes / Procs")
    }
    try writeAllBytes(Array("\u{1b}[6~".utf8), to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("9–16/")
    }
    try writeAllBytes(Array("\u{1b}[5~".utf8), to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("1–8/") && $0.contains("Processes / Procs")
    }
    try writeAllBytes(Array("]".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Help & glossary") && !$0.contains("Processes / Procs") }
    try writeAllBytes(Array("[".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Processes / Procs") }
    try writeAllBytes(Array(String(repeating: "\u{1b}[6~", count: 30).utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Esc back") && !$0.contains("Processes / Procs") }
    try writeAllBytes(Array("D".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Diagnostics") && $0.contains("CPU: host") && $0.contains("Esc back") }
    try writeAllBytes(Array("kspd".utf8), to: terminal.master)
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("PAUSED") && !$0.contains("Diagnostics") }
    small.ws_row = 24
    small.ws_col = 120
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &small) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 120, height: 24))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("PAUSED") && $0.contains("PID 42 |") && !$0.contains("Terminate selected process?") }
    try writeAllBytes(Array("q".utf8), to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}

@Test func terminalAdaptiveIntervalKeysPreserveFullSourceSettingsWhilePaused() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 120, height: 24), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = directory.appendingPathComponent("sampling.json")
    let pid = try launch(
        binary, terminal: terminal.slave,
        environment: ["AGENT_MONITOR_SAMPLING_FIXTURE": settings.path])
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 120, height: 24))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) { $0.contains("fixture-42") && $0.contains("acquire max 1 s") }
    try await expectSourceSamplingSettings(at: settings, maximum: 1)
    try writeAllBytes(Array("p>".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("PAUSED") && $0.contains("acquire max 0.5 s") }
    try await expectSourceSamplingSettings(at: settings, maximum: 0.5)
    try writeAllBytes(Array(">c".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("CPU ↓") && $0.contains("acquire max 0.5 s") }
    try await expectSourceSamplingSettings(at: settings, maximum: 0.5)
    try writeAllBytes(Array((String(repeating: "<", count: 10) + "m").utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("PAUSED") && $0.contains("Memory ↓") && $0.contains("acquire max 10 s") }
    try await expectSourceSamplingSettings(at: settings, maximum: 10)
    try writeAllBytes(Array("q".utf8), to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}

private func expectSourceSamplingSettings(at url: URL, maximum: Double) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while ContinuousClock.now < deadline {
        if let data = try? Data(contentsOf: url),
            let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            settings["visibleMaximum"] as? Double == maximum
        {
            #expect(settings["enabled"] as? Bool == true)
            #expect(settings["minimum"] as? Double == 0.4)
            #expect(settings["closedMultiplier"] as? Double == 2.5)
            #expect(settings["window"] as? Double == 17)
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Fake source did not observe visible maximum \(maximum) within four seconds")
}

@Test(arguments: [false, true])
func terminalActionsRequireConfirmationAndPasteCannotSubmit(quitWhileUndersized: Bool) async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 100, height: 24), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let termination = directory.appendingPathComponent("termination.txt")
    let pid = try launch(
        binary, terminal: terminal.slave,
        environment: ["AGENT_MONITOR_TERMINATION_FIXTURE": termination.path])
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("fixture-42")
    }
    try writeAllBytes(Array("k".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Terminate selected process?") && $0.contains("PID 42")
    }
    // Escape acknowledges the preceding paste at a fixed size; a leaked confirmation
    // is detected by the owned action record even if its result was dismissed.
    try writeAllBytes(Array("\u{1b}[200~\u{19}q\u{1b}[201~\u{1b}".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Stable order") && !$0.contains("Terminate selected process?") }
    #expect(!FileManager.default.fileExists(atPath: termination.path))
    try writeAllBytes(Array("k".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Terminate selected process?") }
    var small = winsize(ws_row: 7, ws_col: 30, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &small) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 30, height: 7))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Resize to 40x8")
    }
    if quitWhileUndersized {
        // Keep the viewport small until shutdown: a sleep before resizing cannot prove
        // that the confirmation key has already passed the runtime's dispatch queue.
        try writeAllBytes([25, 3], to: terminal.master)
        try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
        #expect(!FileManager.default.fileExists(atPath: termination.path))
        return
    }
    var restored = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &restored) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Terminate selected process?") && !$0.contains("SIGTERM accepted")
    }
    try writeAllBytes([25], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("SIGTERM accepted for PID 42")
    }
    #expect(try String(contentsOf: termination, encoding: .utf8) == "42")
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Stable order")
    }
    try writeAllBytes(Array("s".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Messaging is unavailable") }
    try writeAllBytes(Array("\u{1b}[200~qks\u{19}\u{1b}[201~".utf8), to: terminal.master)
    try writeAllBytes(Array("f".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Action result") && $0.contains("Selected the session on ttys001 in Terminal")
    }
    // ESC immediately followed by a key reads as an Alt sequence, so wait for the panel to close.
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Stable order") && !$0.contains("Action result")
    }
    try writeAllBytes(Array(".".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains(">★i ") && !$0.contains("PAUSED") }
    try writeAllBytes(Array(".".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("> i ") && !$0.contains("★") && !$0.contains("PAUSED") }
    try writeAllBytes(Array("p".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED")
    }
    try writeAllBytes(Array(">p".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("every 0.5 s") && !$0.contains("PAUSED")
    }
    try writeAllBytes([3], to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)

}

@Test func terminalDiagnosisUsesFakesAndPreservesPausedReportAcrossCancelAndResize() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 100, height: 24), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    // Gate the owned source so PTY scheduling cannot skip the transient collecting state.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = directory.appendingPathComponent("release-diagnosis")
    let pid = try launch(
        binary, terminal: terminal.slave, environment: ["AGENT_MONITOR_DIAGNOSIS_GATE": gate.path])
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("fixture-42")
    }
    try writeAllBytes(Array("p".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED")
    }
    try writeAllBytes(Array("I".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("CPU diagnosis") && $0.contains("collecting")
    }
    try writeAllBytes(Array("ksf".utf8), to: terminal.master)
    var small = winsize(ws_row: 7, ws_col: 30, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &small) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 30, height: 7))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Resize to 40x8") && $0.contains("x cancel")
    }
    try writeAllBytes(Array("xd".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("cancelled")
    }
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Agent Monitor") && !$0.contains("diagnosis")
    }
    var large = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &large) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED") && $0.contains("Stable order") && $0.contains("I investigate")
    }
    try Data().write(to: gate)
    try writeAllBytes(Array("I".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("completed") && $0.contains("Monitor helper") && $0.contains("diagnosis-worker")
    }
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED") && $0.contains("Stable order") && $0.contains("I investigate")
    }
    try FileManager.default.removeItem(at: gate)
    try writeAllBytes(Array("I".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("CPU diagnosis") && $0.contains("collecting")
    }
    try writeAllBytes(Array("q".utf8), to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}

@Test func terminalOverviewKeepsDetailsInPlaceAndExplicitlySwitchesViews() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 120, height: 32), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let pid = try launch(
        binary, terminal: terminal.slave, environment: ["AGENT_MONITOR_OVERVIEW_FIXTURE": "1"])
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 120, height: 32))
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(10)
    ) {
        $0.contains("Main contributors") && $0.contains("overview-project")
    }
    for hidden in [true, false] {
        try writeAllBytes(Array("H".utf8), to: terminal.master)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) { $0.contains("H show no longer observed") == hidden }
    }
    try writeAllBytes(Array("8".utf8), to: terminal.master)
    try writeAllBytes(Array("b".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Overall CPU · 0–100%") && $0.contains("Main contributors") }
    for key in ["S"] {
        try writeAllBytes(Array(key.utf8), to: terminal.master)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            !$0.contains("overview-project") && $0.contains("Overall CPU") && $0.contains("── S▸ Sessions")

        }
        try writeAllBytes(Array(key.utf8), to: terminal.master)
        _ = try await waitForScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) { $0.contains("overview-project") && $0.contains("S▾ Sessions") }
    }
    try writeAllBytes(Array("i".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("Exact session:") && $0.contains("DETAILS ●") }
    for (key, label) in [("+", "55%"), ("M", "max"), ("=", "55%"), ("-", "50%")] {
        try writeAllBytes(Array(key.utf8), to: terminal.master)
        _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
            $0.contains("DETAILS ●") && $0.contains(label)
        }
    }
    try writeAllBytes(Array("orn".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Main contributors") && $0.contains(" | Stable | ")
            && $0.contains("Exact session:") && $0.contains("DETAILS ●")
    }
    try writeAllBytes([9], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("DETAILS ○")
    }
    try writeAllBytes([9], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("DETAILS ●")
    }
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { !$0.contains("Exact session:") }
    try writeAllBytes(Array("\u{1b}[C\u{1b}[B\u{1b}[C\u{1b}[B\u{1b}[Ci".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("DETAILS ● node · PID 42") && $0.contains("/fixture/node") }
    try writeAllBytes([32], to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.range(of: "Lifetime: +PID 42", options: .regularExpression) != nil
            && $0.contains("DETAILS ● node · PID 42")
    }
    try writeAllBytes(Array("p".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED") && $0.range(of: "Lifetime: +PID 42", options: .regularExpression) != nil
    }
    try writeAllBytes(Array("\r".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.range(of: "Lifetime: +PID 42", options: .regularExpression) != nil
            && $0.contains("Main contributors") && $0.contains("DETAILS")
    }
    try writeAllBytes(Array("v".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("PID 42 |") && !$0.contains("Main contributors") }
    try writeAllBytes(Array("Mx".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("[2] two words") && $0.contains("read on demand") && $0.contains("PAUSED") }
    try writeAllBytes(Array("x".utf8), to: terminal.master)
    _ = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("x read arguments on demand") && !$0.contains("[2] two words") }
    try writeAllBytes(Array("q".utf8), to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}

@Test(arguments: [false, true], [("compact", 0.2), ("auto", 0.2), ("compact", 4.5), ("stacked", 4.5)])
func terminalChartsPreserveCompactHeightAndOverflowInColorAndMonochrome(
    noColor: Bool, scenario: (String, Double)
) async throws {
    let (chartMode, cpuPerSecond) = scenario
    let compact = chartMode != "stacked"
    let overflow = cpuPerSecond > 1
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 160, height: 32), stallBudget: nil)
    defer { terminal.close() }
    var original = termios()
    try #require(tcgetattr(terminal.slave, &original) == 0)
    let pid = try launch(
        binary, terminal: terminal.slave,
        environment: [
            "AGENT_MONITOR_OVERVIEW_FIXTURE": "1", "AGENT_MONITOR_CHART_FIXTURE": chartMode,
            "AGENT_MONITOR_CPU_FIXTURE": String(cpuPerSecond),
            "TERM_PROGRAM": "Apple_Terminal", "TMUX": "synthetic-font-unavailable",
        ].merging(noColor ? ["NO_COLOR": "1"] : [:]) { _, new in new },
        removingEnvironment: ["NO_COLOR"])
    var reaped = false
    defer {
        if !reaped {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
    var screen = ANSIVisibleScreen(size: .init(width: 160, height: 32))
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(10)) {
        $0.contains("overview-project") && $0.contains("Overall CPU")
    }
    try writeAllBytes(Array("b".utf8), to: terminal.master)
    let glyph = overflow ? (noColor ? "↑" : "█") : "▂"
    let rendered = try await waitForScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(5)
    ) {
        $0.contains("0–100%") && $0.contains(String(repeating: glyph, count: 2))
    }
    let plottedRows = rendered.components(separatedBy: "\n").enumerated().filter {
        $0.element.contains(String(repeating: glyph, count: 2))
    }
    #expect(plottedRows.count == (compact || noColor ? 2 : 6))
    #expect(plottedRows.first?.offset == (compact ? 2 : 0))
    #expect(plottedRows.contains { $0.element.contains("codex") })
    #expect(rendered.contains("compact") == compact)
    try writeAllBytes(Array("m".utf8), to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("Memory ↓") && $0.contains("Memory 400.0 MB")
    }
    try writeAllBytes(Array("?".utf8), to: terminal.master)
    _ = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)) {
        $0.contains("Keyboard shortcuts")
    }
    try writeAllBytes(Array("q".utf8), to: terminal.master)
    try await assertCleanExit(pid, terminal: terminal, original: original, reaped: &reaped)
}
