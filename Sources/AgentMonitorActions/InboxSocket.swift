import Darwin
import Foundation

/// One bounded line handoff to a Claude session inbox. The inbox sends no acknowledgment; it
/// closes the connection after routing the line (observed with Claude Code 2.1.300, 2026-10-14),
/// so end-of-stream is the strongest acceptance signal and still says nothing about delivery.
enum InboxSocket {
    static let notSent = ActionFailure("Claude session inbox is unavailable. Nothing was sent.")
    static let uncertain = ActionFailure(
        "Inbox acceptance could not be confirmed. Check the Claude session before retrying; the message may have been accepted."
    )

    static func post(_ line: Data, to path: String, timeout: TimeInterval) throws {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw notSent }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        try connect(descriptor, path, deadline)

        var offset = 0
        while offset < line.count {
            guard wait(descriptor, Int16(POLLOUT), deadline) else { throw offset == 0 ? notSent : uncertain }
            let count = line.withUnsafeBytes {
                write(descriptor, $0.baseAddress! + offset, line.count - offset)
            }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw offset == 0 ? notSent : uncertain
            }
            offset += count
        }
        _ = shutdown(descriptor, SHUT_WR)
        var buffer = [UInt8](repeating: 0, count: 4096)
        var unexpected = 0
        while true {
            guard wait(descriptor, Int16(POLLIN), deadline) else { throw uncertain }
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { return }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw uncertain
            }
            unexpected += count
            guard unexpected <= 65_536 else { throw uncertain }
        }
    }

    private static func connect(_ descriptor: Int32, _ path: String, _ deadline: ContinuousClock.Instant)
        throws
    {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw notSent }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result != 0 else { return }
        guard errno == EINPROGRESS, wait(descriptor, Int16(POLLOUT), deadline) else { throw notSent }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
            throw notSent
        }
    }

    private static func wait(_ descriptor: Int32, _ events: Int16, _ deadline: ContinuousClock.Instant)
        -> Bool
    {
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return false }
            var target = pollfd(fd: descriptor, events: events, revents: 0)
            let ready = poll(&target, 1, Int32(min(50, max(1, remaining / .milliseconds(1)))))
            if ready > 0 { return true }
            if ready < 0, errno != EINTR { return false }
        }
    }
}
