#!/usr/bin/env python3
"""Audit build-artifact retention and clean owned, unlocked scratch runs."""

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


def audit(build: Path, age_seconds: float) -> list[tuple[Path, str]]:
    if build.is_symlink():
        raise ValueError('Build root must not be a symlink')
    if not build.exists():
        return []
    deadline = time.time() - age_seconds
    candidates = [(path, 'abandoned scratch run') for path in clean(build / 'scratch', age_seconds, False)]
    for path in sorted(build.glob('*.log')):
        if not path.is_symlink() and path.is_file() and path.stat().st_mtime <= deadline:
            candidates.append((path, 'old validation log; retain findings and remove completed output'))
    for path in sorted(build.glob('*.png')):
        if not path.is_symlink() and path.is_file():
            candidates.append((path, 'review images belong in design-studies, not the build root'))
    linked_products = [(build / name).resolve() for name in ('debug', 'release') if (build / name).is_symlink()]
    for path in [build / 'out', *sorted(build.glob('*-apple-macosx'))]:
        if path.is_dir() and not path.is_symlink() and linked_products:
            if not any(product.is_relative_to(path.resolve()) for product in linked_products):
                # Report only; product links do not establish whether another process uses the tree.
                candidates.append((path, 'unreferenced build tree; verify idle before removal'))
    return candidates


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


def stop(process: subprocess.Popen) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
            return
        except subprocess.TimeoutExpired:
            if sig == signal.SIGKILL:
                raise


def run(root: Path, command: list[str]) -> int:
    if root.is_symlink():
        raise ValueError('Scratch root must not be a symlink')
    root.mkdir(parents=True, exist_ok=True)
    clean(root, 7 * 86400, True)
    folder = Path(tempfile.mkdtemp(prefix='run-', dir=root))
    may_remove = True
    try:
        with (folder / LOCK).open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            environment = dict(os.environ, AGENT_MONITOR_SCRATCH=str(folder))
            # The command retains the lease even if this wrapper is forcibly killed.
            process = subprocess.Popen(
                command, env=environment, start_new_session=True, pass_fds=(lock.fileno(),))
            may_remove = False
            try:
                result = process.wait()
                may_remove = True
                return result
            except BaseException as interrupted:
                try:
                    stop(process)
                    may_remove = True
                finally:
                    # Cleanup EPERM must not mask the primary failure; see docs/research/cpu-accounting.md.
                    raise interrupted
    finally:
        # A failed stop may leave the owned command using its files and inherited lease.
        if may_remove:
            shutil.rmtree(folder)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    prune = commands.add_parser('clean', help='List abandoned scratch runs; deletion requires --apply')
    prune.add_argument('--apply', action='store_true')
    prune.add_argument('--older-than-days', type=float, default=7)
    check = commands.add_parser('check', help='Fail on stale outputs outside active build/cache roots; never delete')
    check.add_argument('--older-than-days', type=float, default=7)
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
    if args.mode == 'check':
        candidates = audit(ROOT.parent, args.older_than_days * 86400)
        for path, reason in candidates:
            print(f'REVIEW: {path}: {reason}')
        print(f'{len(candidates)} stale build artifacts. Check is read-only; clean --apply removes only owned scratch runs.')
        return int(bool(candidates))
    paths = clean(ROOT, args.older_than_days * 86400, args.apply)
    for path in paths:
        print(('Removed: ' if args.apply else 'Would remove: ') + str(path))
    print(f'{len(paths)} abandoned scratch runs; active builds and app bundles untouched.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
