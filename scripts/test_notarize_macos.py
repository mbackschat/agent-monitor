#!/usr/bin/env python3
"""Exercise resumable notarization with fake Apple commands and disposable files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('notarize', Path(__file__).with_name('notarize-macos.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

ID = '2b6d6544-1430-4b28-8bdd-d8d44ce6d562'
REVISION = 'a' * 40


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        (self.dist / 'agent-monitor-0.4.0-macos-arm64.commit').write_text(REVISION + '\n')
        binary = self.root / '.build/Agent Monitor.app/Contents/MacOS/agent-monitor-menubar'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'executable')
        self.calls = []
        self.status = 'In Progress'
        self.timeout = False
        self.uncertain = False
        self.log_hash = None

    def tearDown(self):
        self.temp.cleanup()

    def fake_run(self, *args):
        args = tuple(map(str, args))
        self.calls.append(args)
        if args[:2] == ('git', '-C'):
            return REVISION if args[-2:] == ('rev-parse', 'HEAD') else ''
        if args[0] == 'ditto':
            if '-k' in args:
                Path(args[-1]).write_bytes(b'zip')
            else:
                shutil.copytree(args[-2], args[-1])
        if args[:3] == ('xcrun', 'notarytool', 'submit'):
            if self.uncertain:
                raise subprocess.CalledProcessError(1, args)
            return json.dumps({'id': ID})
        if args[:3] == ('xcrun', 'notarytool', 'info'):
            return json.dumps({'status': self.status})
        if args[:3] == ('xcrun', 'notarytool', 'wait'):
            if self.timeout:
                raise subprocess.CalledProcessError(1, args)
            self.status = 'Accepted'
        if args[:3] == ('xcrun', 'notarytool', 'log'):
            Path(args[-1]).write_text(json.dumps({
                'status': self.status, 'issues': None,
                'sha256': self.log_hash or hashlib.sha256(b'zip').hexdigest()}))
        return ''

    def invoke(self, submission_id=None):
        with patch.object(release, 'run', self.fake_run), patch.object(release, 'verify_archive'), \
                patch.object(release, 'validate_bundle_version'):
            release.notarize(self.root, '0.4.0', 'identity', 'profile', '10m', submission_id)

    def count(self, prefix):
        return sum(call[:len(prefix)] == prefix for call in self.calls)

    def test_packages_only_after_acceptance_and_writes_matching_receipts(self):
        self.invoke()
        archive = self.dist / 'agent-monitor-app-0.4.0-macos-arm64.zip'
        self.assertTrue(archive.exists())
        self.assertEqual(archive.with_suffix('.commit').read_text().strip(), REVISION)
        self.assertEqual(archive.with_suffix('.zip.sha256').read_text().split()[0], hashlib.sha256(archive.read_bytes()).hexdigest())
        self.assertEqual(self.count(('xcrun', 'notarytool', 'submit')), 1)
        self.assertEqual(self.count(('xcrun', 'stapler', 'staple')), 1)

    def test_timeout_resumes_same_submission_without_signing_or_uploading_again(self):
        self.timeout = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.assertEqual(json.loads((self.dist / 'macos-0.4.0/submission.json').read_text())['id'], ID)
        self.assertEqual(self.count(('xcrun', 'stapler', 'staple')), 0)
        self.assertFalse((self.dist / 'agent-monitor-app-0.4.0-macos-arm64.zip').exists())
        self.timeout = False
        self.invoke()
        self.assertEqual(self.count(('xcrun', 'notarytool', 'submit')), 1)
        self.assertEqual(self.count(('codesign', '--force')), 1)

    def test_uncertain_upload_requires_explicit_submission_recovery(self):
        self.uncertain = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        self.uncertain = False
        with self.assertRaisesRegex(RuntimeError, 'uncertain'):
            self.invoke()
        self.assertEqual(self.count(('xcrun', 'notarytool', 'submit')), 1)
        self.invoke(ID)
        self.assertEqual(self.count(('xcrun', 'notarytool', 'submit')), 1)

    def test_invalid_submission_keeps_log_and_never_staples(self):
        self.status = 'Invalid'
        with self.assertRaisesRegex(RuntimeError, 'Invalid'):
            self.invoke()
        self.assertTrue((self.dist / 'macos-0.4.0/notary-log.json').exists())
        self.assertEqual(self.count(('xcrun', 'stapler', 'staple')), 0)

    def test_recovered_submission_must_match_uploaded_bytes(self):
        self.log_hash = '0' * 64
        with self.assertRaisesRegex(RuntimeError, 'archive'):
            self.invoke()
        self.assertEqual(self.count(('xcrun', 'stapler', 'staple')), 0)

    def test_finished_run_is_repeatable_without_signing_or_submitting(self):
        self.invoke()
        self.calls.clear()
        self.invoke()
        self.assertFalse(any(call[0] == 'xcrun' for call in self.calls))

    def test_source_revision_change_stops_before_signing(self):
        (self.dist / 'agent-monitor-0.4.0-macos-arm64.commit').write_text('b' * 40)
        with self.assertRaisesRegex(RuntimeError, 'revision'):
            self.invoke()
        self.assertEqual(self.count(('codesign', '--force')), 0)

    def test_staged_source_mismatch_stops_resumption(self):
        self.timeout = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke()
        (self.dist / 'macos-0.4.0/source.commit').write_text('b' * 40)
        self.calls.clear()
        with self.assertRaisesRegex(RuntimeError, 'source revision'):
            self.invoke()
        self.assertFalse(any(call[0] == 'xcrun' for call in self.calls))

    def test_modified_final_archive_is_never_overwritten(self):
        self.invoke()
        archive = self.dist / 'agent-monitor-app-0.4.0-macos-arm64.zip'
        archive.write_bytes(b'changed')
        self.calls.clear()
        with self.assertRaisesRegex(RuntimeError, 'receipts'):
            self.invoke()
        self.assertEqual(archive.read_bytes(), b'changed')
        self.assertFalse(any(call[0] == 'xcrun' for call in self.calls))

    def test_incomplete_final_receipts_are_repaired_without_resubmission(self):
        self.invoke()
        (self.dist / 'agent-monitor-app-0.4.0-macos-arm64.commit').unlink()
        self.calls.clear()
        self.invoke()
        self.assertEqual(self.count(('xcrun', 'notarytool', 'submit')), 0)
        self.assertTrue((self.dist / 'agent-monitor-app-0.4.0-macos-arm64.commit').exists())


if __name__ == '__main__':
    unittest.main()
