import AgentMonitorCore
import AppKit
import Darwin
import Foundation

public enum NativeActions {
    public static func inspect(_ expected: HeavyProcess) throws -> HeavyProcess {
        let monitor = try observe(expected)
        guard let current = monitor.finding(for: expected.process) else {
            throw ActionFailure("Process is no longer available. Select it again.")
        }
        try validate(expected)
        return current
    }

    /// Claude exports each session's inbox beside its session marker, so read it from the marker
    /// that attributes the process now, never from a cached row or the runtime's own environment.
    public static func claudeInbox(for expected: HeavyProcess) throws -> String {
        let monitor = try observe(expected)
        guard let marker = monitor.attributingMarker(for: expected.process), marker.provider == .claude,
            marker.threadID == expected.attribution.threadID, let inbox = marker.inboxSocket
        else { throw ActionFailure("Claude session inbox is unavailable. Nothing was sent.") }
        try validate(expected)
        return inbox
    }

    /// The current lifetime of a PID, attributed independently of display thresholds, for
    /// command-line actions that start from a PID rather than a selected row.
    public static func process(pid: Int32) throws -> HeavyProcess {
        guard pid > 1, pid != getpid() else { throw ActionFailure("Refusing this protected PID.") }
        let reader = try NativeProcessReader()
        let samples = try reader.snapshot().samples
        guard let sample = samples.first(where: { $0.identity.pid == pid }) else {
            throw ActionFailure("No process with PID \(pid) owned by your user is running.")
        }
        guard
            let row = observe(sample.identity, reader: reader, samples: samples).finding(for: sample.identity)
        else { throw ActionFailure("Process \(pid) exited.") }
        return row
    }

    private static func observe(_ expected: HeavyProcess) throws -> Monitor {
        try validate(expected)
        let reader = try NativeProcessReader()
        return observe(expected.process, reader: reader, samples: try reader.snapshot().samples)
    }

    private static func observe(
        _ identity: ProcessIdentity, reader: NativeProcessReader, samples: [ProcessSample]
    )
        -> Monitor
    {
        var monitor = Monitor()
        monitor.ingest(samples)
        monitor.enrich(for: [identity]) { reader.metadata(for: $0) }
        return monitor
    }

    /// The runtime's current controlling terminal and the nearest regular application above it.
    /// Agent tool subprocesses can lack a terminal, so the runtime, not the workload, is the subject.
    public static func terminalHost(for runtime: ProcessIdentity) throws -> TerminalHost {
        guard let info = bsdInfo(runtime.pid), start(info) == runtime.startMicroseconds,
            info.pbi_uid == getuid()
        else { throw ActionFailure("The agent runtime exited or changed. Select the process again.") }
        var name = [CChar](repeating: 0, count: 128)
        guard info.e_tdev != 0, info.e_tdev != UInt32.max,
            devname_r(Int32(bitPattern: info.e_tdev), S_IFCHR, &name, Int32(name.count)) != nil
        else { throw ActionFailure("The agent runtime has no terminal.") }
        let tty =
            "/dev/" + string(name)
        var device = stat()
        guard TerminalHost.isDevicePath(tty), stat(tty, &device) == 0,
            UInt32(bitPattern: device.st_rdev) == info.e_tdev
        else { throw ActionFailure("The agent runtime's terminal cannot be identified.") }
        var child = (pid: runtime.pid, start: start(info), parent: Int32(bitPattern: info.pbi_ppid))
        // Helpers such as an editor's terminal process are bundled but not regular apps; keep
        // walking to the application that owns windows.
        while child.parent > 1, let parent = lineage(of: child.parent), parent.start <= child.start {
            let pid = child.parent
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return TerminalHost(
                    tty: tty,
                    application: HostApplication(
                        pid: pid, bundleIdentifier: app.bundleIdentifier,
                        name: app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"))
            }
            child = (pid, parent.start, parent.parent)
        }
        throw ActionFailure(
            "No application hosts this terminal directly, for example under tmux, screen, or ssh. Nothing was focused."
        )
    }

    /// Parent PID and start time of any user's process. proc_pidinfo refuses other users' processes
    /// with EPERM, such as the root-owned `login` above every Terminal.app shell (observed
    /// 2026-10-15, macOS 27); the `KERN_PROC_PID` sysctl that `ps` uses does not.
    static func lineage(of pid: Int32) -> (parent: Int32, start: UInt64)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride else {
            return nil
        }
        let start = info.kp_proc.p_starttime
        return (info.kp_eproc.e_ppid, UInt64(start.tv_sec) * 1_000_000 + UInt64(start.tv_usec))
    }

    /// Since macOS 14 activation is a request the system may decline; true only means it was made.
    /// https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14
    public static func activate(_ application: HostApplication) -> Bool {
        NSRunningApplication(processIdentifier: application.pid)?.activate(options: []) ?? false
    }

    public static func terminate(_ expected: HeavyProcess) throws {
        try validate(expected)
        // macOS has no pidfd signal operation: lifetime check and kill are not atomic.
        // See docs/research/session-actions.md, process termination contract.
        guard Darwin.kill(expected.process.pid, SIGTERM) == 0 else {
            throw ActionFailure("SIGTERM failed: \(String(cString: strerror(errno))).")
        }
    }

    static func validate(_ expected: HeavyProcess) throws {
        let pid = expected.process.pid
        guard pid > 1, pid != getpid() else { throw ActionFailure("Refusing this protected PID.") }
        guard let info = bsdInfo(pid) else { throw ActionFailure("Process exited or cannot be inspected.") }
        guard info.pbi_uid == getuid(), info.pbi_ruid == getuid() else {
            throw ActionFailure("Only processes owned by your user can be acted on.")
        }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard start(info) == expected.process.startMicroseconds,
            proc_pidpath(pid, &path, UInt32(path.count)) > 0,
            string(path) == expected.executable
        else {
            throw ActionFailure("Process identity changed. Select it again.")
        }
    }

    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func start(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }
}
