#!/usr/bin/env python3
"""Release automation checks using disposable Git repositories and fake Homebrew calls."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("homebrew_release", Path(__file__).with_name("update-homebrew.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

OLD = 'class AgentMonitor < Formula\n  url "https://github.com/mbackschat/agent-monitor/releases/download/v0.2.2/agent-monitor-0.2.2-macos-arm64.tar.gz"\n  sha256 "' + 'a' * 64 + '"\nend\n'
SHA = 'b' * 64


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.remote = self.root / 'remote.git'
        self.tap = self.root / 'tap'
        self.git('init', '--bare', str(self.remote))
        self.git('init', '-b', 'main', str(self.tap))
        self.git('-C', str(self.tap), 'config', 'user.email', 'mbackschat@mail.de')
        self.git('-C', str(self.tap), 'config', 'user.name', 'Release test')
        self.git('-C', str(self.tap), 'remote', 'add', 'origin', str(self.remote))
        (self.tap / 'Formula').mkdir()
        self.formula = self.tap / 'Formula/agent-monitor.rb'
        self.formula.write_text(OLD)
        self.git('-C', str(self.tap), 'add', '.')
        self.git('-C', str(self.tap), 'commit', '-m', 'Initial fixture')
        self.git('-C', str(self.tap), 'push', '-u', 'origin', 'main')
        self.calls = []
        self.fail_at = None

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True, stderr=subprocess.DEVNULL).strip()

    def command(self, *args):
        self.calls.append(args)
        if self.fail_at and args[:len(self.fail_at)] == self.fail_at:
            raise RuntimeError('injected failure')
        if args[0] == 'git':
            return self.git(*args[1:])
        if args[:2] == ('brew', '--prefix'):
            return str(self.root / 'installed')
        if args[:3] == ('brew', 'list', '--versions'):
            return 'agent-monitor 0.2.2'
        if args[0] == 'brew':
            return ''
        if args[-1] == '--version':
            return '0.3.0'
        if args[-1] == '--json-schema':
            return '{"$schema":"https://json-schema.org/draft/2020-12/schema"}'
        if args[-2:] == ('guide', 'semantics'):
            return 'CPU semantics'
        raise AssertionError(args)

    def update(self):
        with patch.object(release, 'TAP_REMOTE', str(self.remote)), patch.object(release, 'command', self.command):
            release.update_tap(self.tap, '0.3.0', SHA)

    def test_updates_tests_commits_and_pushes_only_the_formula(self):
        self.update()
        self.assertEqual(self.formula.read_text(), release.formula_text(OLD, '0.3.0', SHA))
        self.assertEqual(self.git('-C', str(self.tap), 'status', '--porcelain'), '')
        self.assertEqual(self.git('-C', str(self.tap), 'rev-parse', 'HEAD'), self.git('--git-dir', str(self.remote), 'rev-parse', 'main'))
        self.assertIn(('brew', 'audit', '--strict', 'mbackschat/tap/agent-monitor'), self.calls)
        self.assertIn(('brew', 'test', 'mbackschat/tap/agent-monitor'), self.calls)

    def test_retry_after_audit_failure_reuses_only_its_own_edit(self):
        self.fail_at = ('brew', 'audit')
        with self.assertRaises(RuntimeError):
            self.update()
        self.fail_at = None
        self.update()
        self.assertEqual(self.git('-C', str(self.tap), 'status', '--porcelain'), '')

    def test_retry_after_push_failure_does_not_create_another_commit(self):
        self.fail_at = ('git', '-C', str(self.tap), 'push')
        with self.assertRaises(RuntimeError):
            self.update()
        commit = self.git('-C', str(self.tap), 'rev-parse', 'HEAD')
        self.fail_at = None
        self.update()
        self.assertEqual(self.git('-C', str(self.tap), 'rev-parse', 'HEAD'), commit)

    def test_completed_update_is_repeatable(self):
        self.update()
        commit = self.git('-C', str(self.tap), 'rev-parse', 'HEAD')
        self.update()
        self.assertEqual(self.git('-C', str(self.tap), 'rev-parse', 'HEAD'), commit)

    def test_refuses_unrelated_work_before_mutation(self):
        (self.tap / 'unrelated').write_text('leave me alone')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertEqual(self.formula.read_text(), OLD)
        self.assertFalse(any(call[0] == 'brew' for call in self.calls))

    def test_refuses_other_formula_edits(self):
        self.formula.write_text(OLD + '# user edit\n')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertTrue(self.formula.read_text().endswith('# user edit\n'))

    def test_refuses_a_staged_formula_edit_even_if_working_copy_was_restored(self):
        self.formula.write_text(OLD + '# staged user edit\n')
        self.git('-C', str(self.tap), 'add', 'Formula/agent-monitor.rb')
        self.formula.write_text(OLD)
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertIn('# staged user edit', self.git('-C', str(self.tap), 'show', ':Formula/agent-monitor.rb'))

    def test_refuses_wrong_push_identity(self):
        self.git('-C', str(self.tap), 'config', 'user.email', 'wrong@example.invalid')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertEqual(self.formula.read_text(), OLD)

    def test_refuses_wrong_remote(self):
        self.git('-C', str(self.tap), 'remote', 'set-url', 'origin', 'https://example.invalid/elsewhere')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertEqual(self.formula.read_text(), OLD)

    def test_failed_installed_test_never_commits_or_pushes(self):
        commit = self.git('-C', str(self.tap), 'rev-parse', 'HEAD')
        self.fail_at = ('brew', 'test')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertEqual(self.git('-C', str(self.tap), 'rev-parse', 'HEAD'), commit)
        self.assertFalse(any(call[-3:] == ('push', 'origin', 'main') for call in self.calls))

    def test_refuses_unrelated_unpushed_commits(self):
        (self.tap / 'unrelated').write_text('unpublished work')
        self.git('-C', str(self.tap), 'add', '.')
        self.git('-C', str(self.tap), 'commit', '-m', 'Unrelated work')
        with self.assertRaises(RuntimeError):
            self.update()
        self.assertEqual(self.formula.read_text(), OLD)

    def test_refuses_downgrade_or_changed_published_checksum(self):
        current = release.formula_text(OLD, '0.3.0', SHA)
        for version, sha in [('0.2.2', SHA), ('0.3.0', 'c' * 64)]:
            with self.assertRaises(RuntimeError):
                release.formula_text(current, version, sha)


if __name__ == '__main__':
    unittest.main()
