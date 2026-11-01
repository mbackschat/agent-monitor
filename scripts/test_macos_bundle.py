#!/usr/bin/env python3
"""Check native release bundle contents without building or signing live products."""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import macos_bundle
from macos_bundle import create_bundle, validate_bundle_version


class MacBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.icons = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.icons.cleanup)
        cls.compiled = Path(cls.icons.name)
        cls.source = Path(__file__).resolve().parent.parent / 'Resources/AgentMonitor.icon'
        subprocess.run([
            'xcrun', 'actool', str(cls.source), '--compile', str(cls.compiled),
            '--platform', 'macosx', '--minimum-deployment-target', '27.0',
            '--app-icon', 'AgentMonitor', '--output-partial-info-plist',
            str(cls.compiled / 'icon.plist')], check=True, capture_output=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.products = self.root / 'products'
        self.products.mkdir()
        (self.products / 'agent-monitor-menubar').write_bytes(b'native executable')
        for name in ('AgentMonitorPresentation', 'AgentMonitorMenuBar'):
            bundle = self.products / f'AgentMonitor_{name}.bundle'
            bundle.mkdir()
            (bundle / 'fixture.txt').write_text(name)
        (self.root / 'LICENSE').write_text('project license')
        (self.root / 'THIRD_PARTY_NOTICES.md').write_text('notice index')
        (self.root / 'Package.resolved').write_text(json.dumps({'pins': [{'identity': 'swift-tui'}]}))
        checkout = self.root / '.build/checkouts/swift-tui'
        fonts = checkout / 'Vendor/swift-figlet/Fonts'
        fonts.mkdir(parents=True)
        (checkout / 'LICENSE').write_text('dependency license')
        (checkout / 'NOTICE').write_text('dependency notice')
        (fonts.parent / 'LICENSE').write_text('vendored license')
        (fonts / 'fixture.flf').write_text('font notice')
        shutil.copytree(self.source, self.root / 'Resources/AgentMonitor.icon')
        self.compiler = patch.object(macos_bundle, 'compile_app_icon', self.copy_compiled_icon, create=True)
        self.compiler.start()
        self.addCleanup(self.compiler.stop)
        self.app = self.root / 'Agent Monitor.app'

    def copy_compiled_icon(self, source, resources):
        for name in ('AgentMonitor.icns', 'Assets.car'):
            shutil.copy2(self.compiled / name, resources / name)
        return plistlib.loads((self.compiled / 'icon.plist').read_bytes())

    def test_bundle_declares_the_packaged_application_icon(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info.get('CFBundleIconFile'), 'AgentMonitor')
        self.assertEqual(info.get('CFBundleIconName'), 'AgentMonitor')
        for name in ('AgentMonitor.icns', 'Assets.car'):
            self.assertEqual((self.app / 'Contents/Resources' / name).read_bytes(), (self.compiled / name).read_bytes())

    def test_production_compiler_builds_and_validates_the_approved_source(self):
        self.compiler.stop()
        create_bundle(self.root, self.products, self.app, '0.4.0')
        macos_bundle.validate_bundle_icon(self.app)

    def test_icon_validation_rejects_missing_or_different_declarations(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        path = self.app / 'Contents/Info.plist'
        original = plistlib.loads(path.read_bytes())
        for key in ('CFBundleIconFile', 'CFBundleIconName'):
            for value in (None, 'Unrelated'):
                with self.subTest(key=key, value=value):
                    info = dict(original)
                    info[key] = value or ''
                    path.write_bytes(plistlib.dumps(info))
                    with self.assertRaises(ValueError):
                        macos_bundle.validate_bundle_icon(self.app)

    def test_icon_validation_rejects_missing_and_corrupt_resources(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        for name in ('AgentMonitor.icns', 'Assets.car'):
            path = self.app / 'Contents/Resources' / name
            original = path.read_bytes()
            for content in (None, b'invalid icon resource'):
                with self.subTest(name=name, content=content):
                    if content is None:
                        path.unlink()
                    else:
                        path.write_bytes(content)
                    with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                        macos_bundle.validate_bundle_icon(self.app)
                    path.write_bytes(original)

    def test_icon_validation_rejects_catalog_without_layered_icon_or_full_resolution(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        for entries in ([], [{'Name': 'AgentMonitor', 'AssetType': 'IconImageStack'}]):
            with self.subTest(entries=entries), patch.object(
                    macos_bundle.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(entries))):
                with self.assertRaises(ValueError):
                    macos_bundle.validate_bundle_icon(self.app)

    def test_archive_rejects_missing_icon_before_signature_checks(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        (self.app / 'Contents/Resources/AgentMonitor.icns').unlink()
        def extract(args, **kwargs):
            self.assertEqual(args[:3], ['ditto', '-x', '-k'])
            shutil.copytree(self.app, Path(args[-1]) / self.app.name)
        with patch.object(macos_bundle.subprocess, 'run', side_effect=extract):
            with self.assertRaises(ValueError):
                macos_bundle.verify_archive(self.root / 'download.zip', '0.4.0')

    def test_bundle_uses_release_version_and_retains_resources_and_licenses(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '0.4.0')
        self.assertEqual(info['CFBundleVersion'], '0.4.0')
        self.assertEqual(info['CFBundleIdentifier'], 'de.mbackschat.agent-monitor.menubar')
        self.assertTrue(info['LSUIElement'])
        self.assertIn('NSAppleEventsUsageDescription', info)
        resources = self.app / 'Contents/Resources'
        self.assertEqual((resources / 'AgentMonitor_AgentMonitorPresentation.bundle/fixture.txt').read_text(), 'AgentMonitorPresentation')
        self.assertTrue((resources / 'AgentMonitor_AgentMonitorMenuBar.bundle/fixture.txt').is_file())
        self.assertEqual((resources / 'licenses/swift-tui/NOTICE').read_text(), 'dependency notice')
        self.assertEqual((resources / 'licenses/swift-tui/Vendor/swift-figlet/Fonts/fixture.flf').read_text(), 'font notice')
        self.assertEqual((self.app / 'Contents/MacOS/agent-monitor-menubar').read_bytes(), b'native executable')

    def test_invalid_version_does_not_create_bundle(self):
        with self.assertRaises(ValueError):
            create_bundle(self.root, self.products, self.app, 'release candidate')
        self.assertFalse(self.app.exists())

    def test_existing_bundle_is_not_overwritten(self):
        self.app.mkdir()
        marker = self.app / 'keep'
        marker.write_text('existing app')
        with self.assertRaises(FileExistsError):
            create_bundle(self.root, self.products, self.app, '0.4.0')
        self.assertEqual(marker.read_text(), 'existing app')

    def test_release_verification_rejects_wrong_version_or_bundle_identity(self):
        create_bundle(self.root, self.products, self.app, '0.4.0')
        validate_bundle_version(self.app, '0.4.0')
        with self.assertRaises(ValueError):
            validate_bundle_version(self.app, '0.3.0')
        path = self.app / 'Contents/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleIdentifier'] = 'example.other-app'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):
            validate_bundle_version(self.app, '0.4.0')


if __name__ == '__main__':
    unittest.main()
