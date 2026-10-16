import Darwin
import Foundation

/// Confined to one action task; deadlines and output limits also bound a broken provider CLI.
final class BoundedCommand {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: ContinuousClock.Instant
    private var pending = Data()
    private var bytesRead = 0
    private var closed = false
    private let tool: String

    init(executable: URL, arguments: [String], timeout: TimeInterval, tool: String) throws {
        deadline = .now.advanced(by: .seconds(timeout))
        self.tool = tool
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            throw ActionFailure("Cannot start \(tool). Ensure its CLI is on PATH.")
        }
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
    }

    func receive(count: Int) throws -> Data {
        while pending.count < count {
            guard try read() else { throw ActionFailure("\(tool) connection closed.") }
        }
        let data = Data(pending.prefix(count))
        pending.removeFirst(count)
        return data
    }

    func receive(until delimiter: Data, limit: Int) throws -> Data {
        while true {
            if let range = pending.range(of: delimiter) {
                let size = pending.distance(from: pending.startIndex, to: range.upperBound)
                guard size <= limit else { throw ActionFailure("\(tool) handshake exceeded the size limit.") }
                return try receive(count: size)
            }
            guard pending.count < limit else {
                throw ActionFailure("\(tool) handshake exceeded the size limit.")
            }
            guard try read() else { throw ActionFailure("\(tool) connection closed.") }
        }
    }

    func finish() throws {
        _ = try readOutput()
    }

    /// Standard output after successful exit, within the same deadline and size bound.
    func readOutput() throws -> Data {
        try? input.fileHandleForWriting.close()
        while try read() {}
        while process.isRunning {
            try checkDeadline()
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ActionFailure("\(tool) command failed.") }
        defer { pending.removeAll() }
        return pending
    }

    func write(_ data: Data) throws {
        try checkDeadline()
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func checkDeadline() throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ActionFailure("\(tool) request timed out.") }
    }

    private func read() throws -> Bool {
        try checkDeadline()
        var descriptor = pollfd(
            fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 50)
        if ready < 0 {
            if errno == EINTR { return true }
            throw ActionFailure("Cannot read \(tool) response.")
        }
        guard ready > 0 else { return true }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(descriptor.fd, &buffer, buffer.count)
        if count == 0 { return false }
        if count < 0 {
            if errno == EAGAIN || errno == EINTR { return true }
            throw ActionFailure("Cannot read \(tool) response.")
        }
        bytesRead += count
        guard bytesRead <= 1_048_576 else { throw ActionFailure("\(tool) response exceeded the size limit.") }
        pending.append(contentsOf: buffer.prefix(count))
        return true
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let end = ContinuousClock.now.advanced(by: .milliseconds(200))
            while process.isRunning, ContinuousClock.now < end { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
}
