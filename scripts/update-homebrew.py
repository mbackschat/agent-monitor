#!/usr/bin/env python3
"""Verify and publish the Homebrew formula for an already-published CLI release."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

TAP_REMOTE = "https://github.com/mbackschat/homebrew-tap"
FORMULA = "mbackschat/tap/agent-monitor"
FORMULA_PATH = "Formula/agent-monitor.rb"
EMAIL = "mbackschat@mail.de"


def command(*args):
    environment = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_INSTALL_CLEANUP="1")
    if (args[0] == 'brew' and args[1] in {'audit', 'install', 'upgrade', 'test'}
            or args[0] == 'git' and args[3] in {'fetch', 'merge', 'commit', 'push'}):
        print('+ ' + ' '.join(args), flush=True)
        subprocess.run(args, check=True, env=environment)
        return ''
    return subprocess.check_output(args, text=True, env=environment).strip()


def formula_text(text, version, checksum):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise RuntimeError("Invalid release version or SHA-256")
    pattern = r'url "https://github.com/mbackschat/agent-monitor/releases/download/v([0-9.]+)/agent-monitor-\1-macos-arm64.tar.gz"'
    matches = list(re.finditer(pattern, text))
    hashes = list(re.finditer(r'sha256 "([a-f0-9]{64})"', text))
    if len(matches) != 1 or len(hashes) != 1:
        raise RuntimeError("Unexpected formula URL/checksum shape; review it manually")
    previous = matches[0].group(1)
    if tuple(map(int, previous.split('.'))) > tuple(map(int, version.split('.'))):
        raise RuntimeError("Refusing to downgrade the formula")
    if previous == version and hashes[0].group(1) != checksum:
        raise RuntimeError("Published release checksum changed")
    url = f'url "https://github.com/mbackschat/agent-monitor/releases/download/v{version}/agent-monitor-{version}-macos-arm64.tar.gz"'
    return re.sub(r'sha256 "[a-f0-9]{64}"', f'sha256 "{checksum}"', re.sub(pattern, lambda _: url, text))


def update_tap(tap, version, checksum):
    import json

    def git(*args):
        return command('git', '-C', str(tap), *args)

    def identity():
        if git('branch', '--show-current') != 'main':
            raise RuntimeError('The Homebrew tap must be on main')
        if git('remote', 'get-url', 'origin') not in (TAP_REMOTE, TAP_REMOTE + '.git'):
            raise RuntimeError('Unexpected Homebrew tap remote')
        if git('config', 'user.email') != EMAIL:
            raise RuntimeError(f'GitHub pushes require user.email={EMAIL}')

    identity()
    formula = tap / FORMULA_PATH
    baseline = git('show', f'HEAD:{FORMULA_PATH}') + '\n'
    desired = formula_text(baseline, version, checksum)
    changed = set(git('diff', 'HEAD', '--name-only').splitlines())
    staged = set(git('diff', '--cached', '--name-only').splitlines())
    changed.update(staged)
    if git('ls-files', '--others', '--exclude-standard') or changed - {FORMULA_PATH}:
        raise RuntimeError('The tap contains unrelated changes; leave them untouched')
    if formula.read_text() not in (baseline, desired):
        raise RuntimeError('The formula contains edits outside this release update')
    if FORMULA_PATH in staged and git('show', f':{FORMULA_PATH}') + '\n' not in (baseline, desired):
        raise RuntimeError('The formula has staged edits outside this release update')
    git('fetch', 'origin', 'main')
    behind, ahead = map(int, git('rev-list', '--left-right', '--count', 'origin/main...HEAD').split())
    subject = f'chore(agent-monitor): update to {version}'
    if behind:
        if ahead or changed:
            raise RuntimeError('The tap advanced remotely; reconcile its local work before retrying')
        git('merge', '--ff-only', 'origin/main')
        baseline = git('show', f'HEAD:{FORMULA_PATH}') + '\n'
        desired = formula_text(baseline, version, checksum)
    elif ahead:
        remote_formula = git('show', f'origin/main:{FORMULA_PATH}') + '\n'
        if (ahead != 1 or git('log', '-1', '--format=%s') != subject
                or git('diff', '--name-only', 'origin/main', 'HEAD') != FORMULA_PATH
                or baseline != formula_text(remote_formula, version, checksum)):
            raise RuntimeError('Refusing to push unrelated local commits')

    formula.write_text(desired)
    print(f'Verifying {FORMULA} {version}', flush=True)
    command('brew', 'audit', '--strict', FORMULA)
    try:
        installed = command('brew', 'list', '--versions', FORMULA)
    except subprocess.CalledProcessError:
        installed = ''
    if not installed:
        command('brew', 'install', FORMULA)
    elif version not in installed.split()[1:]:
        command('brew', 'upgrade', FORMULA)
    command('brew', 'test', FORMULA)
    binary = str(Path(command('brew', '--prefix', FORMULA)) / 'bin/agent-monitor')
    if command(binary, '--version') != version:
        raise RuntimeError('Installed version does not match the release')
    for args in [('--json-schema',), ('diagnose', 'cpu', '--json-schema')]:
        if '$schema' not in json.loads(command(binary, *args)):
            raise RuntimeError('Installed schema discovery failed')
    if 'CPU' not in command(binary, 'guide', 'semantics'):
        raise RuntimeError('Installed guide check failed')
    if git('diff', 'HEAD', '--', FORMULA_PATH):
        git('add', '--', FORMULA_PATH)
        git('commit', '-m', subject)
    identity()
    git('push', 'origin', 'main')
    print(f'Published Homebrew formula for Agent Monitor {version}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', args.version):
        parser.error('expected a semantic version, e.g. 0.3.0')
    name = f'agent-monitor-{args.version}-macos-arm64.tar.gz'
    with tempfile.TemporaryDirectory(prefix='agent-monitor-homebrew-') as directory:
        command('gh', 'release', 'download', f'v{args.version}', '--repo', 'mbackschat/agent-monitor',
                '--pattern', name + '.sha256', '--dir', directory)
        fields = (Path(directory) / (name + '.sha256')).read_text().split()
        if len(fields) != 2 or fields[1] != name or not re.fullmatch(r'[a-f0-9]{64}', fields[0]):
            raise RuntimeError('Published checksum does not identify the expected archive')
        tap = Path(command('brew', '--repository', 'mbackschat/tap'))
        update_tap(tap, args.version, fields[0])


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'FAIL: {error}\nAfter resolving the issue, rerun this command; existing release assets are unchanged.')
