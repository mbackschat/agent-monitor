#!/usr/bin/env python3
"""Assemble a fresh, versioned native app; the caller chooses its signing identity."""
from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

from release_licenses import copy_licenses


def compile_app_icon(source, resources):
    with tempfile.TemporaryDirectory(prefix='agent-monitor-icon-') as temporary:
        metadata = Path(temporary) / 'icon.plist'
        subprocess.run([
            'xcrun', 'actool', str(source), '--compile', str(resources),
            '--platform', 'macosx', '--minimum-deployment-target', '27.0',
            '--app-icon', 'AgentMonitor', '--output-partial-info-plist', str(metadata)],
            check=True, capture_output=True)
        info = plistlib.loads(metadata.read_bytes())
        if info.get('CFBundleIconFile') != 'AgentMonitor' or info.get('CFBundleIconName') != 'AgentMonitor':
            raise ValueError('Icon compiler did not declare the expected application icon')
        return {key: info[key] for key in ('CFBundleIconFile', 'CFBundleIconName')}


def validate_bundle_icon(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIconFile') != 'AgentMonitor' or info.get('CFBundleIconName') != 'AgentMonitor':
        raise ValueError('Native app does not declare its application icon')
    resources = app / 'Contents/Resources'
    icon = resources / 'AgentMonitor.icns'
    catalog = resources / 'Assets.car'
    if not icon.is_file() or not catalog.is_file():
        raise ValueError('Native app is missing compiled icon resources')
    result = subprocess.run(['xcrun', 'assetutil', '--info', str(catalog)],
                            check=True, capture_output=True, text=True)
    assets = [item for item in json.loads(result.stdout) if item.get('Name') == 'AgentMonitor']
    sizes = {item.get('PixelWidth') for item in assets
             if item.get('AssetType') == 'Icon Image' and item.get('PixelWidth') == item.get('PixelHeight')}
    if not any(item.get('AssetType') == 'IconImageStack' for item in assets) or not {32, 64, 128, 256, 512, 1024} <= sizes:
        raise ValueError('Native icon catalog lacks its layered icon or required resolutions')
    with tempfile.TemporaryDirectory(prefix='agent-monitor-icon-verify-') as temporary:
        decoded = Path(temporary) / 'AppIcon.iconset'
        subprocess.run(['iconutil', '-c', 'iconset', '-o', str(decoded), str(icon)],
                       check=True, capture_output=True)
        if not any(decoded.glob('*.png')):
            raise ValueError('Native application icon has no decodable images')


def create_bundle(root, products, app, version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Expected a semantic release version')
    app.mkdir()
    executable = app / 'Contents/MacOS'
    resources = app / 'Contents/Resources'
    executable.mkdir(parents=True)
    resources.mkdir()
    icon_info = compile_app_icon(root / 'Resources/AgentMonitor.icon', resources)
    shutil.copy2(products / 'agent-monitor-menubar', executable / 'agent-monitor-menubar')
    for name in ('AgentMonitorPresentation', 'AgentMonitorMenuBar'):
        bundle = f'AgentMonitor_{name}.bundle'
        shutil.copytree(products / bundle, resources / bundle)
    copy_licenses(root, resources)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        **icon_info,
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
    validate_bundle_icon(app)


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
        validate_bundle_icon(app)
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
