import AgentMonitorCore
import Darwin
import Foundation

public enum NativeActions {
    public static func inspect(_ expected: HeavyProcess) throws -> HeavyProcess {
        try validate(expected)
        let reader = try NativeProcessReader()
        let samples = try reader.snapshot().samples
        let byPID = Dictionary(uniqueKeysWithValues: samples.map { ($0.identity.pid, $0) })
        var chain: [ProcessSample] = []
        var next = byPID[expected.process.pid]
        var seen: Set<ProcessIdentity> = []
        while let sample = next, seen.insert(sample.identity).inserted {
            chain.append(sample)
            guard let parent = byPID[sample.parentPID],
                parent.identity.startMicroseconds <= sample.identity.startMicroseconds
            else { break }
            next = parent
        }
        var monitor = Monitor()
        monitor.ingest(chain)
        for sample in chain { monitor.enrich(reader.metadata(for: sample), for: sample.identity) }
        guard let current = monitor.finding(for: expected.process) else {
            throw ActionFailure("Process is no longer available. Select it again.")
        }
        try validate(expected)
        return current
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
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            throw ActionFailure("Process exited or cannot be inspected.")
        }
        guard info.pbi_uid == getuid(), info.pbi_ruid == getuid() else {
            throw ActionFailure("Only processes owned by your user can be acted on.")
        }
        let start = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard start == expected.process.startMicroseconds,
            proc_pidpath(pid, &path, UInt32(path.count)) > 0,
            String(cString: path) == expected.executable
        else {
            throw ActionFailure("Process identity changed. Select it again.")
        }
    }
}
