#!/usr/bin/env python3
"""Measure a bounded macOS monitor watch using native physical footprint and Mach CPU ticks."""

import argparse
import ctypes
import json
import hashlib
from datetime import datetime, timezone
import select
import statistics
import subprocess
import time


class RUsage(ctypes.Structure):
    # macOS SDK sys/resource.h, rusage_info_v2; CPU fields are Mach ticks.
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user", "system", "idle_wakes", "interrupt_wakes", "pageins", "wired",
            "rss", "footprint", "start", "exit", "child_user", "child_system",
            "child_idle", "child_interrupt", "child_pageins", "child_elapsed",
            "disk_read", "disk_written",
        )
    ]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    parser.add_argument("--seconds", type=int, default=600)
    parser.add_argument("--output", required=True, help="JSON measurement result path")
    args = parser.parse_args()
    if args.seconds < 10:
        parser.error("--seconds must be at least 10")
    native = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    native.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(RUsage)]
    timebase = Timebase()
    assert native.mach_timebase_info(ctypes.byref(timebase)) == 0 and timebase.denom
    scale = timebase.numer / timebase.denom / 1e9
    with open(args.binary, "rb") as binary_file:
        digest = hashlib.sha256()
        for chunk in iter(lambda: binary_file.read(1024 * 1024), b""):
            digest.update(chunk)
        binary_hash = digest.hexdigest()
    started_at = datetime.now(timezone.utc).isoformat()
    process = subprocess.Popen(
        [args.binary, "--json", "--samples", "0", "--interval", "1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
    )
    started = time.monotonic()
    points, counts, codex, workers = [], [], [], []
    reports = churn_count = 0
    next_churn = 0
    try:
        while time.monotonic() - started < args.seconds:
            elapsed = time.monotonic() - started
            assert process.poll() is None, process.stderr.read()
            if elapsed >= next_churn:
                workers = [worker for worker in workers if worker.poll() is None]
                workers += [subprocess.Popen(["/bin/sleep", "3"]) for _ in range(6)]
                churn_count += 6
                next_churn += 30
            if select.select([process.stdout], [], [], 1)[0]:
                line = process.stdout.readline()
                assert line, "Monitor ended unexpectedly"
                report = json.loads(line)
                reports += 1
                counts.append(report["sampledProcessCount"])
                for row in report["findings"]:
                    owner = row["attribution"]
                    if owner.get("provider") == "codex" and owner["context"] == "terminal":
                        codex.append({"timestamp": report["timestamp"], "finding": row})
            usage = RUsage()
            assert native.proc_pid_rusage(process.pid, 2, ctypes.byref(usage)) == 0
            points.append({"seconds": round(time.monotonic() - started, 3),
                           "cpuSeconds": (usage.user + usage.system) * scale,
                           "footprintBytes": usage.footprint})
        elapsed = points[-1]["seconds"]
        footprints = [point["footprintBytes"] for point in points]
        tail = [point for point in points if point["seconds"] >= elapsed - 60]
        warm = [point for point in points if 30 <= point["seconds"] <= 60] or points[:1]
        summary = {"startedAt": started_at, "binarySHA256": binary_hash, "durationSeconds": elapsed, "reports": reports,
                   "cpuPercentOneCore": 100 * points[-1]["cpuSeconds"] / elapsed,
                   "firstFootprintBytes": footprints[0], "peakFootprintBytes": max(footprints),
                   "lastFootprintBytes": footprints[-1],
                   "warmMedianFootprintBytes": statistics.median(p["footprintBytes"] for p in warm),
                   "lastMinuteMedianFootprintBytes": statistics.median(p["footprintBytes"] for p in tail),
                   "sampledProcessCountRange": [min(counts), max(counts)],
                   "spawnedShortLivedProcesses": churn_count,
                   "terminalCodexHeavyObservations": len(codex)}
        with open(args.output, "w") as output:
            json.dump({"summary": summary, "measurements": points, "terminalCodex": codex}, output, indent=2)
        print(json.dumps(summary, indent=2))
    finally:
        process.terminate()
        process.communicate(timeout=10)
        for worker in workers:
            if worker.poll() is None:
                worker.terminate()
            worker.wait(timeout=5)


if __name__ == "__main__":
    main()
