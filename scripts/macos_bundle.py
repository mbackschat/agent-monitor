#!/usr/bin/env python3
"""Assemble a fresh, versioned native app; the caller chooses its signing identity."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

from release_licenses import copy_licenses


def create_bundle(root, products, app, version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Expected a semantic release version')
    app.mkdir()
    executable = app / 'Contents/MacOS'
    resources = app / 'Contents/Resources'
    executable.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(products / 'agent-monitor-menubar', executable / 'agent-monitor-menubar')
    for name in ('AgentMonitorPresentation', 'AgentMonitorMenuBar'):
        bundle = f'AgentMonitor_{name}.bundle'
        shutil.copytree(products / bundle, resources / bundle)
    copy_licenses(root, resources)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'agent-monitor-menubar',
        'CFBundleIdentifier': 'de.mbackschat.agent-monitor.menubar',
        'CFBundleName': 'Agent Monitor',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version,
        'CFBundleVersion': version,
        'LSMinimumSystemVersion': '27.0',
        'LSUIElement': True,
        'NSAppleEventsUsageDescription': 'Select the terminal tab hosting the agent session you choose.',
    }))


def validate_bundle_version(app, version):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'de.mbackschat.agent-monitor.menubar'
            or info.get('CFBundleShortVersionString') != version
            or info.get('CFBundleVersion') != version):
        raise ValueError('Native app identity/version does not match the release')


def verify_archive(archive, version):
    with tempfile.TemporaryDirectory(prefix='agent-monitor-app-verify-') as temporary:
        subprocess.run(['ditto', '-x', '-k', str(archive), temporary], check=True)
        app = Path(temporary) / 'Agent Monitor.app'
        validate_bundle_version(app, version)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], check=True)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--verify-archive':
        verify_archive(Path(sys.argv[2]).resolve(), sys.argv[3])
    elif len(sys.argv) == 3:
        root = Path(__file__).resolve().parent.parent
        source = (root / 'Sources/AgentMonitorCore/Version.swift').read_text()
        version = re.search(r'current = "([^"]+)"', source).group(1)
        create_bundle(root, Path(sys.argv[1]), Path(sys.argv[2]), version)
    else:
        raise SystemExit('Usage: macos_bundle.py <products> <new-app-path> | --verify-archive <zip> <version>')
