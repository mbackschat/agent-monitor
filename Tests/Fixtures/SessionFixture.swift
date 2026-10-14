import Darwin
import Foundation

// A disposable process fixture, not an agent emulator. Marker semantics come from
// Codex 0.162.1; the oracle is the explicit launch ledger in verify-poc.py.
let args = CommandLine.arguments
guard args.count == 5 else { exit(2) }
let mode = args[1]
let session = args[2]
let ready = args[3]
let behavior = args[4]

if mode == "root" {
    let directory = URL(fileURLWithPath: ready).deletingLastPathComponent()
    let locks = directory.appendingPathComponent("thread-writer-locks")
    try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
    let lock = locks.appendingPathComponent("\(session).lock")
    FileManager.default.createFile(atPath: lock.path, contents: Data())
    let handle = try FileHandle(forWritingTo: lock)
    guard flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { exit(3) }
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: args[0]).deletingLastPathComponent().appendingPathComponent(
        "worker")
    worker.arguments = ["worker", session, ready, behavior]
    var environment = ProcessInfo.processInfo.environment.filter {
        !$0.key.hasPrefix("CODEX_") && !$0.key.hasPrefix("CLAUDE_CODE_")
    }
    if behavior == "claude" {
        environment["CLAUDE_CODE_SESSION_ID"] = session
    } else if behavior != "scrubbed" {
        environment["CODEX_THREAD_ID"] = session
        environment["CODEX_SESSION_ID"] = session
    }
    worker.environment = environment
    try worker.run()
    if behavior == "orphan" {
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        exit(0)
    }
    worker.waitUntilExit()
    try handle.close()
} else {
    if behavior == "orphan" { _ = setsid() }
    let allocation = behavior == "small" ? 4096 : 32 * 1024 * 1024
    let memory = UnsafeMutableRawPointer.allocate(byteCount: allocation, alignment: 4096)
    defer { memory.deallocate() }
    for offset in stride(from: 0, to: allocation, by: 4096) {
        memory.storeBytes(of: UInt8(truncatingIfNeeded: offset / 4096), toByteOffset: offset, as: UInt8.self)
    }
    try Data(String(getpid()).utf8).write(to: URL(fileURLWithPath: ready), options: .atomic)
    let deadline = Date().addingTimeInterval(20)
    let stop = URL(fileURLWithPath: ready).deletingLastPathComponent().appendingPathComponent("stop")
    var checksum: UInt64 = 1
    while Date() < deadline, !FileManager.default.fileExists(atPath: stop.path) {
        if behavior == "cpu" {
            let slice = Date().addingTimeInterval(0.025)
            repeat {
                for _ in 0..<10_000 { checksum = checksum &* 1_664_525 &+ 1_013_904_223 }
            } while Date() < slice
            Thread.sleep(forTimeInterval: 0.025)
        } else {
            Thread.sleep(forTimeInterval: 0.05)
        }
        memory.storeBytes(of: checksum, as: UInt64.self)
    }
    try Data("done".utf8).write(to: URL(fileURLWithPath: ready + ".done"), options: .atomic)
}
