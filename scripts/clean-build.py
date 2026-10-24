#!/usr/bin/env python3
"""Run probes in disposable storage and remove abandoned, unlocked scratch runs."""

import argparse
import fcntl
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent / '.build' / 'scratch'
LOCK = '.cleanup-lock'


def clean(root: Path, age_seconds: float, apply: bool) -> list[Path]:
    if root.is_symlink():
        raise ValueError('Scratch root must not be a symlink')
    if not root.exists():
        return []
    candidates = []
    for path in sorted(root.glob('run-*')):
        lock_path = path / LOCK
        if path.is_symlink() or not path.is_dir() or lock_path.is_symlink() or not lock_path.is_file():
            continue
        if time.time() - lock_path.stat().st_mtime < age_seconds:
            continue
        try:
            with lock_path.open('r+') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue
                candidates.append(path)
                if apply:
                    shutil.rmtree(path)
        except FileNotFoundError:
            continue
    return candidates


def run(root: Path, command: list[str]) -> int:
    if root.is_symlink():
        raise ValueError('Scratch root must not be a symlink')
    root.mkdir(parents=True, exist_ok=True)
    clean(root, 7 * 86400, True)
    with tempfile.TemporaryDirectory(prefix='run-', dir=root) as folder:
        with (Path(folder) / LOCK).open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            environment = dict(os.environ, AGENT_MONITOR_SCRATCH=folder)
            # The command retains the lease even if this wrapper is forcibly killed.
            process = subprocess.Popen(
                command, env=environment, start_new_session=True, pass_fds=(lock.fileno(),))
            try:
                return process.wait()
            except BaseException:
                # Only the command's owned process group may outlive this scratch directory.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    prune = commands.add_parser('clean', help='List abandoned scratch runs; deletion requires --apply')
    prune.add_argument('--apply', action='store_true')
    prune.add_argument('--older-than-days', type=float, default=7)
    execute = commands.add_parser('run', help='Set AGENT_MONITOR_SCRATCH for a command, then remove it')
    execute.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.mode == 'run':
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        if not command:
            parser.error('run requires a command')
        return run(ROOT, command)
    if args.older_than_days < 0:
        parser.error('--older-than-days must be nonnegative')
    paths = clean(ROOT, args.older_than_days * 86400, args.apply)
    for path in paths:
        print(('Removed: ' if args.apply else 'Would remove: ') + str(path))
    print(f'{len(paths)} abandoned scratch runs; active builds and app bundles untouched.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
