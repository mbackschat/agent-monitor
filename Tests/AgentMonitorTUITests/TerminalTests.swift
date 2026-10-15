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
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("Updates: 1") && $0.contains("fixture-42")
    }
    try writeAllBytes([13], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Runtime: 1234") && $0.contains("PID 42 |") && $0.contains("Updates: 2")
            && dividerRow($0) == 11
    }
    for (width, headerRows, footerRows, divider) in [
        (120, 1, 2, 11), (200, 1, 2, 11), (80, 3, 4, 11), (100, 2, 3, 11),
    ] {
        var resized = winsize(ws_row: 24, ws_col: UInt16(width), ws_xpixel: 0, ws_ypixel: 0)
        try #require(ioctl(terminal.slave, TIOCSWINSZ, &resized) == 0)
        screen = ANSIVisibleScreen(size: .init(width: width, height: 24))
        try #require(kill(pid, SIGWINCH) == 0)
        _ = try await waitForANSIVisibleScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            let rows = $0.split(separator: "\n", omittingEmptySubsequences: false)
            return $0.contains("PID 42 |") && dividerRow($0) == divider
                && rows.indices.contains(headerRows) && rows[headerRows].contains("CPU%")
                && rows.indices.contains(24 - footerRows) && rows[24 - footerRows].contains("↑/↓ select")
                && $0.contains("1/2 CPU -/+10%") && $0.contains("3/4 GB -/+1")
        }
    }
    try writeAllBytes(Array("n".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID ascending") && $0.contains("PID 42 |")
    }
    try writeAllBytes(Array("r".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID descending") && $0.contains("PID 42 |")
    }
    for (key, label, divider) in [
        ("+", "Details 55%", 11), ("9", "Details max", 2), ("0", "Details min", 20),
        ("=", "Details 55%", 11), ("-", "Details 50%", 11),
    ] {
        try writeAllBytes(Array(key.utf8), to: terminal.master)
        _ = try await waitForANSIVisibleScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            $0.contains(label) && dividerRow($0) == divider
                && (key != "9" || !$0.contains("fixture-84"))
                && (key != "0" || !$0.contains("PID 42 |"))
        }
    }
    var size = winsize(ws_row: 16, ws_col: 60, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &size) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 60, height: 16))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID descending") && $0.contains("PID 42 |") && $0.contains("unresolved")
            && dividerRow($0) == 7
    }
    try writeAllBytes(Array(String(repeating: "]", count: 20).utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Candidates:") && !$0.contains("PID 42 |")
    }
    try writeAllBytes(Array(String(repeating: "[", count: 20).utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID 42 |")
    }
    try writeAllBytes([13], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("fixture-42") && !$0.contains("Runtime: 1234")
    }
    try writeAllBytes(Array("g".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("2 launch groups") && $0.contains("[+]") && !$0.contains("fixture-42")
    }
    try writeAllBytes([13], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("[-]") && $0.contains("fixture-42") && !$0.contains("fixture-84")
    }
    try writeAllBytes(Array("\u{1b}[B\r".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PID 42 |") && dividerRow($0) == 7
    }
    try writeAllBytes(Array("g".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("fixture-42") && $0.contains("fixture-84") && !$0.contains("launch groups")
    }
    for (keys, cpu, memory, empty) in [
        ("4" + String(repeating: "2", count: 10), "125.00", "2.00", true),
        (String(repeating: "1", count: 10), "25.00", "2.00", false),
        ("3", "25.00", "1.00", false),
    ] {
        try writeAllBytes(Array(keys.utf8), to: terminal.master)
        _ = try await waitForANSIVisibleScreen(
            on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
        ) {
            $0.contains("CPU > \(cpu)% OR GB > \(memory)") && !$0.contains("pending")
                && $0.contains("No heavy processes") == empty
                && (empty || ($0.contains("fixture-42") && $0.contains("fixture-84")))
                && $0.contains("1/2 CPU -/+10%") && $0.contains("3/4 GB -/+1")
        }
    }
    try writeAllBytes([3], to: terminal.master)
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
    try #require(reaped, "Child must exit within four seconds of Ctrl-C")
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

private func launch(_ binary: String, terminal: Int32) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?
    try #require(posix_spawn_file_actions_init(&actions) == 0)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for descriptor: Int32 in 0...2 {
        try #require(posix_spawn_file_actions_adddup2(&actions, terminal, descriptor) == 0)
    }
    let environment = ProcessInfo.processInfo.environment.merging(["TERM": "xterm-256color"]) { _, new in new
    }
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

@Test func terminalActionsRequireConfirmationAndPasteCannotSubmit() async throws {
    let binary =
        ProcessInfo.processInfo.environment["AGENT_MONITOR_TUI_FIXTURE"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/monitor-tui-fixture").path
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 100, height: 24), stallBudget: nil)
    defer { terminal.close() }
    let pid = try launch(binary, terminal: terminal.slave)
    defer {
        kill(pid, SIGKILL)
        waitpid(pid, nil, 0)
    }
    var screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(8)
    ) {
        $0.contains("fixture-42")
    }
    try writeAllBytes(Array("k".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Terminate selected process?") && $0.contains("PID 42")
    }
    var small = winsize(ws_row: 7, ws_col: 30, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &small) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 30, height: 7))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Resize to 40x8")
    }
    try writeAllBytes([25], to: terminal.master)
    try await Task.sleep(for: .milliseconds(100))
    var restored = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
    try #require(ioctl(terminal.slave, TIOCSWINSZ, &restored) == 0)
    screen = ANSIVisibleScreen(size: .init(width: 100, height: 24))
    try #require(kill(pid, SIGWINCH) == 0)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Terminate selected process?") && !$0.contains("SIGTERM accepted")
    }
    try writeAllBytes([25], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("SIGTERM accepted for PID 42")
    }
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("CPU descending")
    }
    try writeAllBytes(Array("s".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Message agent") && $0.contains("Recipient: Root agent")
    }
    try writeAllBytes(Array("\u{1b}[200~q\nPlease investigate\u{19}\u{1b}[201~".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Message agent") && $0.contains("Please investigate") && !$0.contains("Message queued")
    }
    try writeAllBytes([9, 13], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Review exact message") && $0.contains("Recipient: Selected agent")
            && $0.contains("selected process PID 42 (fixture-42)")
    }
    try writeAllBytes([25], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Message queued for 11111111") && $0.contains("not confirmed")
    }
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("CPU descending") && !$0.contains("Action result")
    }
    try writeAllBytes(Array("f".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("Action result") && $0.contains("Selected the session on ttys001 in Terminal")
    }
    // ESC immediately followed by a key reads as an Alt sequence, so wait for the panel to close.
    try writeAllBytes([27], to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("CPU descending") && !$0.contains("Action result")
    }
    try writeAllBytes(Array(" ".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { $0.contains("@") && !$0.contains("PAUSED") }
    try writeAllBytes(Array(" ".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) { !$0.contains("@") && !$0.contains("PAUSED") }
    try writeAllBytes(Array("p".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("PAUSED")
    }
    try writeAllBytes(Array(">p".utf8), to: terminal.master)
    _ = try await waitForANSIVisibleScreen(
        on: terminal.master, screen: &screen, deadline: .now() + .seconds(4)
    ) {
        $0.contains("every 0.5 s") && !$0.contains("PAUSED")
    }
}
