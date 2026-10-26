import AgentMonitorCore
import Darwin
import Foundation
import Synchronization

@main enum CaptureCommand {
    static let usage = """
        Usage: monitor-workload-capture OUTPUT.jsonl [SECONDS [MAX_MIB]]
        Explicitly record current-user process observations at 100 ms; no provider queries.
        Defaults: 60 seconds, \(CaptureOptions.defaultMaximumMiB) MiB. Maximum: 300 seconds, \(CaptureOptions.maximumMiB) MiB.
        OUTPUT must not exist. Ctrl-C writes a cancellation footer.
        The first time/size limit stops recording. An early file-limit stop exits with status 2.
        This is partial polling evidence, not complete worker/session accounting.
        """

    static func main() {
        do { exit(try execute()) } catch {
            try? FileHandle.standardError.write(contentsOf: Data("Recording failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func execute() throws -> Int32 {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty, arguments != ["--help"] else {
            print(usage)
            return 0
        }
        guard arguments.count <= 3, !arguments[0].hasPrefix("-"),
            let seconds = Double(arguments.count > 1 ? arguments[1] : "60"),
            let mib = Int(arguments.count > 2 ? arguments[2] : String(CaptureOptions.defaultMaximumMiB)),
            (1...CaptureOptions.maximumMiB).contains(mib)
        else { throw CaptureError.invalidOptions }
        let options = try CaptureOptions(seconds: seconds, maximumBytes: mib * 1024 * 1024)
        let output = try CaptureFile(path: arguments[0])
        let reader = try NativeProcessReader()
        let stopping = Mutex(false)
        let signals = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { stopping.withLock { $0 = true } }
            source.resume()
            return source
        }
        defer {
            for source in signals { source.cancel() }
        }
        let result = try Capture.run(
            options: options,
            now: { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9 },
            sleep: { Thread.sleep(forTimeInterval: $0) },
            cpu: { Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9 },
            cancelled: { stopping.withLock { $0 } },
            read: { try reader.snapshot(excluding: [getpid()]) },
            write: { try output.handle.write(contentsOf: $0) })
        try output.handle.synchronize()
        try output.handle.close()
        try FileHandle.standardError.write(
            contentsOf: Data((result.statusLine(requestedSeconds: options.seconds) + "\n").utf8))
        return result.exitStatus
    }
}

final class CaptureFile {
    let handle: FileHandle

    init(path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
