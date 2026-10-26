import importlib.util
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, call, patch

SPEC = importlib.util.spec_from_file_location('clean_build', Path(__file__).with_name('clean-build.py'))


class ScratchCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.module)

    def test_command_output_is_removed_on_success_and_failure(self):
        for status in (0, 7):
            code = 'import os,pathlib,sys; pathlib.Path(os.environ["AGENT_MONITOR_SCRATCH"],"trace").write_text("data"); sys.exit(%d)' % status
            self.assertEqual(self.module.run(self.root, [sys.executable, '-c', code]), status)
            self.assertEqual(list(self.root.iterdir()), [])

    def test_interruption_survives_cleanup_failures(self):
        for phase in ('terminate', 'kill', 'reap'):
            with self.subTest(phase=phase):
                interruption = KeyboardInterrupt('original interruption')
                failure = PermissionError('cleanup denied')
                timeout = subprocess.TimeoutExpired('owned command', 5)
                waits = [interruption, timeout, failure]
                signals = [None, None]
                if phase == 'terminate':
                    signals = [failure]
                elif phase == 'kill':
                    signals = [None, failure]
                process = Mock(pid=123, **{'poll.return_value': None, 'wait.side_effect': waits})
                with patch.object(self.module.subprocess, 'Popen', return_value=process), patch.object(
                    self.module.os, 'killpg', side_effect=signals
                ):
                    with self.assertRaises(KeyboardInterrupt) as caught:
                        self.module.run(self.root, ['fake-command'])
                self.assertIs(caught.exception, interruption)
                self.assertIs(caught.exception.__context__, failure)
                self.assertEqual(list(self.root.iterdir()), [])

    def test_interruption_does_not_signal_an_already_finished_command(self):
        interruption = KeyboardInterrupt()
        process = Mock(pid=123, **{'poll.return_value': 0, 'wait.side_effect': interruption})
        with patch.object(self.module.subprocess, 'Popen', return_value=process), patch.object(
            self.module.os, 'killpg'
        ) as send_signal:
            with self.assertRaises(KeyboardInterrupt) as caught:
                self.module.run(self.root, ['fake-command'])
        self.assertIs(caught.exception, interruption)
        send_signal.assert_not_called()

    def test_group_disappearance_still_reaps_the_owned_command(self):
        interruption = KeyboardInterrupt()
        process = Mock(pid=123, **{'poll.return_value': None, 'wait.side_effect': [interruption, 0]})
        with patch.object(self.module.subprocess, 'Popen', return_value=process), patch.object(
            self.module.os, 'killpg', side_effect=ProcessLookupError()
        ):
            with self.assertRaises(KeyboardInterrupt) as caught:
                self.module.run(self.root, ['fake-command'])
        self.assertIs(caught.exception, interruption)
        self.assertEqual(process.wait.call_args_list, [call(), call(timeout=5)])

    def test_interrupted_cleanup_escalates_with_bounded_waits(self):
        interruption = KeyboardInterrupt()
        process = Mock(pid=123, **{
            'poll.return_value': None,
            'wait.side_effect': [interruption, subprocess.TimeoutExpired('owned command', 5), -9],
        })
        with patch.object(self.module.subprocess, 'Popen', return_value=process), patch.object(
            self.module.os, 'killpg'
        ) as send_signal:
            with self.assertRaises(KeyboardInterrupt) as caught:
                self.module.run(self.root, ['fake-command'])
        self.assertIs(caught.exception, interruption)
        self.assertEqual(send_signal.call_args_list, [call(123, signal.SIGTERM), call(123, signal.SIGKILL)])
        self.assertEqual(process.wait.call_args_list, [call(), call(timeout=5), call(timeout=5)])

    def test_cleanup_only_removes_old_owned_unlocked_directories(self):
        import fcntl
        old = self.root / 'run-old'
        old.mkdir()
        (old / '.cleanup-lock').touch()
        active = self.root / 'run-active'
        active.mkdir()
        lock = (active / '.cleanup-lock').open('w')
        self.addCleanup(lock.close)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        unknown = self.root / 'out'
        unknown.mkdir()
        self.assertEqual(self.module.clean(self.root, 0, False), [old])
        self.assertTrue(old.exists())
        self.assertEqual(self.module.clean(self.root, 0, True), [old])
        self.assertFalse(old.exists())
        self.assertTrue(active.exists())
        self.assertTrue(unknown.exists())

    def test_symlinks_and_unmarked_directories_are_never_followed(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / '.cleanup-lock').touch()
        (self.root / 'run-link').symlink_to(outside, target_is_directory=True)
        (self.root / 'run-unmarked').mkdir()
        self.assertEqual(self.module.clean(self.root, 0, True), [])
        self.assertTrue(outside.exists())

    def test_command_keeps_lease_when_wrapper_is_terminated(self):
        ready = self.root / 'ready'
        stop = self.root / 'stop'
        code = (
            'import pathlib,time; '
            f'pathlib.Path({str(ready)!r}).touch(); '
            f'\nwhile not pathlib.Path({str(stop)!r}).exists(): time.sleep(0.01)'
        )
        wrapper_code = (
            'import importlib.util,pathlib; '
            f's=importlib.util.spec_from_file_location("cleanup",{SPEC.origin!r}); '
            'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
            f'm.run(pathlib.Path({str(self.root)!r}),{[sys.executable, '-c', code]!r})'
        )
        wrapper = subprocess.Popen([sys.executable, '-c', wrapper_code])
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            wrapper.terminate()
            wrapper.wait(timeout=5)
            self.assertEqual(self.module.clean(self.root, 0, True), [])
        finally:
            stop.touch()
            if wrapper.poll() is None:
                wrapper.terminate()
                wrapper.wait(timeout=5)
            deadline = time.monotonic() + 5
            while list(self.root.glob('run-*')) and time.monotonic() < deadline:
                self.module.clean(self.root, 0, True)
                time.sleep(0.01)

    def test_recent_scratch_is_preserved(self):
        recent = self.root / 'run-recent'
        recent.mkdir()
        (recent / '.cleanup-lock').touch()
        self.assertEqual(self.module.clean(self.root, 86400, True), [])


if __name__ == '__main__':
    unittest.main()
