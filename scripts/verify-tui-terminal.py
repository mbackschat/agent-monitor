#!/usr/bin/env python3
"""Check terminal cleanup and measure a bounded live or fixture UI run on macOS."""

import argparse
import fcntl
import os
import pty
import re
import resource
import select
import signal
import struct
import subprocess
import termios
import time


def verify(binary, duration, color, fixture, group_session=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    original = termios.tcgetattr(slave)
    environment = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
    if color:
        environment.pop("NO_COLOR", None)
    else:
        environment["NO_COLOR"] = "1"
    previous = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    arguments = [binary] if fixture else [binary, "--tui"]
    if group_session:
        arguments += ["--group", "session"]
    process = subprocess.Popen(arguments, stdin=slave, stdout=slave, stderr=slave, env=environment)
    output = bytearray()

    def drain(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            remaining = max(0, deadline - time.monotonic())
            if select.select([master], [], [], remaining)[0]:
                output.extend(os.read(master, 65536))

    try:
        drain(duration)
        assert process.poll() is None, output.decode(errors="replace")
        assert b"Agent Monitor" in output
        if group_session:
            assert b"launch groups" in output, "Session grouping was not enabled at startup"
        enabled_modes = {
            int(mode)
            for match in re.finditer(rb"\x1b\[\?([0-9;]+)h", output)
            for mode in match.group(1).split(b";")
        }
        assert not enabled_modes.intersection({9, 1000, 1001, 1002, 1003, 1006, 1016}), (
            "Mouse reporting prevents native terminal text selection"
        )
        if color:
            os.write(master, b"\x03")
        else:
            process.send_signal(signal.SIGTERM)
        drain(0.3)
        process.wait(timeout=4)
        elapsed = time.monotonic() - started
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        assert process.returncode == 0, process.returncode
        assert termios.tcgetattr(slave) == original, "Terminal attributes changed"
        assert b"\x1b[?1049h" in output and b"\x1b[?1049l" in output
        assert b"\x1b[?25h" in output, "Cursor was not restored"
        has_color = re.search(rb"\x1b\[[0-9;]*(?:38|48);", output) is not None
        assert has_color == color, "Color capability / NO_COLOR mismatch"
        cpu = usage.ru_utime + usage.ru_stime - previous.ru_utime - previous.ru_stime
        mode = "color + Ctrl-C" if color else "NO_COLOR + SIGTERM"
        print(f"PASS {mode}: {cpu:.3f} CPU s / {elapsed:.3f} wall s = {100 * cpu / elapsed:.2f}% of one core")
        print(f"Child peak RSS high-water mark: {usage.ru_maxrss / 1e6:.1f} MB (not physical footprint)")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=4)
        os.close(master)
        os.close(slave)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--fixture", action="store_true", help="Use monitor-tui-fixture instead of the live CLI")
    parser.add_argument("--group-session", action="store_true", help="Check the live CLI's grouped TUI startup")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 60:
        parser.error("--seconds must be between 1 and 60")
    if args.fixture and args.group_session:
        parser.error("--group-session requires the live CLI")
    verify(args.binary, args.seconds, color=True, fixture=args.fixture, group_session=args.group_session)
    verify(args.binary, args.seconds, color=False, fixture=args.fixture, group_session=args.group_session)
