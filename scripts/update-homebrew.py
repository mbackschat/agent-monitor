#!/usr/bin/env python3
"""Verify and publish the CLI formula and Mac cask for an existing release."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

TAP_REMOTE = "https://github.com/mbackschat/homebrew-tap"
FORMULA = "mbackschat/tap/agent-monitor"
FORMULA_PATH = "Formula/agent-monitor.rb"
CASK = "mbackschat/tap/agent-monitor-app"
CASK_PATH = "Casks/agent-monitor-app.rb"
EMAIL = "mbackschat@mail.de"


def command(*args):
    environment = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_INSTALL_CLEANUP="1")
    if (args[0] == 'brew' and args[1] in {'audit', 'fetch', 'install', 'upgrade', 'test'}
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


def cask_text(text, version, checksum):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise RuntimeError("Invalid release version or SHA-256")
    if text is not None:
        previous = re.search(r'  version "([0-9.]+)"', text)
        digest = re.search(r'  sha256 "([a-f0-9]{64})"', text)
        if not previous or not digest or text != cask_text(None, previous[1], digest[1]):
            raise RuntimeError('Unexpected cask content; review it manually')
        if tuple(map(int, previous[1].split('.'))) > tuple(map(int, version.split('.'))):
            raise RuntimeError('Refusing to downgrade the cask')
        if previous[1] == version and digest[1] != checksum:
            raise RuntimeError('Published app checksum changed')
    return f'''cask "agent-monitor-app" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/mbackschat/agent-monitor/releases/download/v#{{version}}/agent-monitor-app-#{{version}}-macos-arm64.zip"
  name "Agent Monitor"
  desc "Trace CPU and memory use to coding-agent sessions from the menu bar"
  homepage "https://github.com/mbackschat/agent-monitor"

  depends_on arch: :arm64
  depends_on macos: :golden_gate

  app "Agent Monitor.app"
end
'''


def update_tap(tap, version, checksum, app_checksum):
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

    def baseline_at(revision):
        return {path: (git('show', f'{revision}:{path}') + '\n'
                       if git('ls-tree', '--name-only', revision, '--', path) else None)
                for path in (FORMULA_PATH, CASK_PATH)}

    def recipes(baseline):
        if baseline[FORMULA_PATH] is None:
            raise RuntimeError('Expected the existing CLI formula')
        return {FORMULA_PATH: formula_text(baseline[FORMULA_PATH], version, checksum),
                CASK_PATH: cask_text(baseline[CASK_PATH], version, app_checksum)}

    identity()
    baseline = baseline_at('HEAD')
    desired = recipes(baseline)
    changed = set(git('diff', 'HEAD', '--name-only').splitlines())
    staged = set(git('diff', '--cached', '--name-only').splitlines())
    changed.update(staged)
    changed.update(git('ls-files', '--others', '--exclude-standard').splitlines())
    if changed - desired.keys():
        raise RuntimeError('The tap contains unrelated changes; leave them untouched')
    for path in desired:
        current = (tap / path).read_text() if (tap / path).exists() else None
        if current not in (baseline[path], desired[path]):
            raise RuntimeError(f'{path} contains edits outside this release update')
        if path in staged and git('show', f':{path}') + '\n' not in (baseline[path], desired[path]):
            raise RuntimeError(f'{path} has staged edits outside this release update')
    git('fetch', 'origin', 'main')
    behind, ahead = map(int, git('rev-list', '--left-right', '--count', 'origin/main...HEAD').split())
    subject = f'chore(agent-monitor): update to {version}'
    if behind:
        if ahead or changed:
            raise RuntimeError('The tap advanced remotely; reconcile its local work before retrying')
        git('merge', '--ff-only', 'origin/main')
        baseline = baseline_at('HEAD')
        desired = recipes(baseline)
    elif ahead:
        if (ahead != 1 or git('log', '-1', '--format=%s') != subject
                or set(git('diff', '--name-only', 'origin/main', 'HEAD').splitlines()) - desired.keys()
                or baseline != recipes(baseline_at('origin/main'))):
            raise RuntimeError('Refusing to push unrelated local commits')

    for path, text in desired.items():
        (tap / path).parent.mkdir(parents=True, exist_ok=True)
        (tap / path).write_text(text)
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
    command('brew', 'audit', '--strict', '--cask', CASK)
    command('brew', 'fetch', '--cask', CASK)
    app_archive = command('brew', '--cache', '--cask', CASK)
    command('python3', str(Path(__file__).with_name('macos_bundle.py')),
            '--verify-archive', app_archive, version)
    git('add', '--', *desired)
    if git('diff', '--cached', '--name-only'):
        git('commit', '-m', subject)
    identity()
    git('push', 'origin', 'main')
    print(f'Published Homebrew formula and Mac cask for Agent Monitor {version}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', args.version):
        parser.error('expected a semantic version, e.g. 0.3.0')
    with tempfile.TemporaryDirectory(prefix='agent-monitor-homebrew-') as directory:
        checksums = []
        for name in (f'agent-monitor-{args.version}-macos-arm64.tar.gz',
                     f'agent-monitor-app-{args.version}-macos-arm64.zip'):
            command('gh', 'release', 'download', f'v{args.version}', '--repo', 'mbackschat/agent-monitor',
                    '--pattern', name + '.sha256', '--dir', directory)
            fields = (Path(directory) / (name + '.sha256')).read_text().split()
            if len(fields) != 2 or fields[1] != name or not re.fullmatch(r'[a-f0-9]{64}', fields[0]):
                raise RuntimeError('Published checksum does not identify the expected archive')
            checksums.append(fields[0])
        tap = Path(command('brew', '--repository', 'mbackschat/tap'))
        update_tap(tap, args.version, *checksums)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'FAIL: {error}\nAfter resolving the issue, rerun this command; existing release assets are unchanged.')
