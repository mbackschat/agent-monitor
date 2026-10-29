import Darwin
import Foundation

/// A helper confined to one serial owner, with deadlines and output limits.
/// Production runs fixed local Terminal automation; provider listing fixtures use disposable test programs.
package final class BoundedCommand {
    private let process = Process()
    private let output = Pipe()
    private let deadline: ContinuousClock.Instant
    private var pending = Data()
    private var bytesRead = 0
    private var closed = false
    private let tool: String
    private let checkCancellation: @Sendable () throws -> Void

    /// `environment` overlays the inherited environment.
    package init(
        executable: URL, arguments: [String], environment: [String: String] = [:], timeout: TimeInterval,
        tool: String,
        checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }
    ) throws {
        deadline = .now.advanced(by: .seconds(timeout))
        self.tool = tool
        self.checkCancellation = checkCancellation
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try checkCancellation()
        do { try process.run() } catch {
            throw BoundedCommandFailure("Cannot start \(tool). Ensure its CLI is on PATH.")
        }
        try? output.fileHandleForWriting.close()
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
    }

    /// Standard output after successful exit, within the same deadline and size bound.
    package func readOutput() throws -> Data {
        while try read() {}
        while process.isRunning {
            try checkDeadline()
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BoundedCommandFailure("\(tool) command failed.") }
        defer { pending.removeAll() }
        return pending
    }

    private func checkDeadline() throws {
        try checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw BoundedCommandFailure("\(tool) request timed out.")
        }
    }

    private func read() throws -> Bool {
        try checkDeadline()
        var descriptor = pollfd(
            fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 50)
        if ready < 0 {
            if errno == EINTR { return true }
            throw BoundedCommandFailure("Cannot read \(tool) response.")
        }
        guard ready > 0 else { return true }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(descriptor.fd, &buffer, buffer.count)
        if count == 0 { return false }
        if count < 0 {
            if errno == EAGAIN || errno == EINTR { return true }
            throw BoundedCommandFailure("Cannot read \(tool) response.")
        }
        bytesRead += count
        guard bytesRead <= 1_048_576 else {
            throw BoundedCommandFailure("\(tool) response exceeded the size limit.")
        }
        pending.append(contentsOf: buffer.prefix(count))
        return true
    }

    package func close() {
        guard !closed else { return }
        closed = true
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

package struct BoundedCommandFailure: Error, LocalizedError, Sendable {
    package let message: String
    package init(_ message: String) { self.message = message }
    package var errorDescription: String? { message }
}
