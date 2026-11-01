#!/usr/bin/env python3
"""Check native release bundle contents without building or signing live products."""
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from macos_bundle import create_bundle, validate_bundle_version


class MacBundleTests(unittest.TestCase):
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
        self.app = self.root / 'Agent Monitor.app'

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
