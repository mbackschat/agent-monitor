#!/usr/bin/env python3
"""Exercise the built monitor against disposable, labeled terminal process trees."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent
MONITOR = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / ".build/out/Products/Debug/agent-monitor"


def wait_for_file(path, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            try:
                return int(path.read_text())
            except (ValueError, FileNotFoundError):
                pass
        time.sleep(0.02)
    raise AssertionError(f"Fixture did not become ready: {path.name}")


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    check(MONITOR.is_file(), "Build agent-monitor before running this check")
    with tempfile.TemporaryDirectory(prefix="agent-monitor-poc-") as scratch:
        scratch = Path(scratch)
        binary = scratch / "codex"
        compile_result = subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-O",
            "-module-cache-path", str(ROOT / ".build/module-cache"),
            str(ROOT / "Tests/Fixtures/SessionFixture.swift"), "-o", str(binary),
        ], capture_output=True, text=True, timeout=90)
        check(compile_result.returncode == 0, compile_result.stderr)
        shutil.copy2(binary, scratch / "worker")
        shutil.copy2(binary, scratch / "claude")
        roots, ready_files, terminals, ledger = [], [], [], {}
        try:
            for index, behavior in enumerate(["normal", "normal", "scrubbed", "orphan", "small", "cpu", "claude"], start=1):
                session = f"{index:08d}-1111-4111-8111-111111111111"
                ready = scratch / f"ready-{index}"
                master, slave = os.openpty()
                terminals.append(master)

                def terminal_session():
                    os.setsid()
                    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

                root = subprocess.Popen(
                    [str(scratch / "claude" if behavior == "claude" else binary), "root", session, str(ready), behavior], cwd=scratch,
                    stdin=slave, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                    preexec_fn=terminal_session,
                )
                roots.append(root)
                os.close(slave)
                pid = wait_for_file(ready)
                ready_files.append(ready)
                if behavior == "orphan":
                    check(root.wait(timeout=5) == 0, "Orphan fixture launcher failed")
                ledger[pid] = (session, behavior, root.pid)

            result = subprocess.run([
                str(MONITOR), "--json", "--memory-gb", "0.025", "--cpu", "20", "--interval", "0.5",
            ], capture_output=True, text=True, timeout=15)
            check(result.returncode == 0, result.stderr)
            report = json.loads(result.stdout)
            rows = {row["process"]["pid"]: row for row in report["findings"]}
            for pid, (session, behavior, root_pid) in ledger.items():
                if behavior == "small":
                    check(pid not in rows, "A low-load worker leaked into the findings")
                    continue
                check(pid in rows, f"Missing heavy {behavior} worker")
                row = rows[pid]
                attribution = row["attribution"]
                check(attribution.get("threadID") == session, f"Incorrect session for {behavior} worker")
                check(attribution.get("provider") == ("claude" if behavior == "claude" else "codex"), "Incorrect provider")
                check(row["footprintBytes"] > 25_000_000, "Expected touched memory missing")
                if behavior != "orphan":
                    check(attribution.get("runtime", {}).get("pid") == root_pid, "Incorrect runtime")
                    check(attribution["context"] == "terminal", "Terminal context missing")
                if behavior == "scrubbed":
                    check(attribution["evidence"] == "writerLock", "Writer-lock fallback was not exercised")
                if behavior == "orphan":
                    check(attribution["evidence"] == "marker", "Detached marker attribution was not exercised")
                if behavior == "cpu":
                    check(20 < row["cpuPercent"] < 120, "CPU normalization or threshold detection failed")
                check("command" not in row, "Arguments should not be retained by default")
            print("PASS: 6 heavy workers mapped to exact Codex/Claude sessions; low-load worker excluded.")
            print("PASS: same-directory sessions, terminal roots, writer-lock fallback, orphan markers, CPU and footprint.")
        finally:
            # A private stop file avoids signaling detached workers by recyclable PID.
            (scratch / "stop").touch()
            for process in roots:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=5)
                if process.stderr:
                    process.stderr.close()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and any(not Path(str(p) + ".done").exists() for p in ready_files):
                time.sleep(0.02)
            for descriptor in terminals:
                os.close(descriptor)


if __name__ == "__main__":
    main()
