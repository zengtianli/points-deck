"""Narrow regression: real deadlines/locks/owned children, no Apple build or boot."""
import contextlib
import fcntl
import importlib.util
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/accept'))
from bounded import ACTIVE, Budget, BudgetExpired

spec = importlib.util.spec_from_file_location('points_measure', ROOT / 'scripts/perf/measure_platforms.py')
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class DeadlineTests(unittest.TestCase):
    def test_invalid_and_already_spent_budget_restore_state(self):
        for value in (0, -1, float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                Budget(value)
        previous = signal.getsignal(signal.SIGALRM)
        with self.assertRaises(BudgetExpired):
            with Budget(1, time.monotonic() - 2):
                self.fail('expired entry ran')
        self.assertIsNone(ACTIVE.get())
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous)

    def test_entry_time_includes_preparation(self):
        began = time.monotonic()
        time.sleep(.12)
        with self.assertRaises(BudgetExpired):
            with Budget(.3, began):
                time.sleep(2)
        self.assertLess(time.monotonic() - began, .6)

    def test_lock_wait_bounded_and_other_holder_survives(self):
        with tempfile.NamedTemporaryFile() as lock:
            holder = subprocess.Popen([sys.executable, '-c',
                'import fcntl,sys,time; f=open(sys.argv[1],"a+"); fcntl.flock(f,fcntl.LOCK_EX); print("held",flush=True); time.sleep(20)',
                lock.name], stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(holder.stdout.readline().strip(), 'held')
                with open(lock.name, 'a+') as waiter:
                    began = time.monotonic()
                    with self.assertRaises(BudgetExpired):
                        with Budget(.3) as budget:
                            budget.lock(waiter)
                    self.assertLess(time.monotonic() - began, .6)
                self.assertIsNone(holder.poll())
                with open(lock.name, 'a+') as waiter, Budget(2) as budget:
                    began = time.monotonic()
                    with self.assertRaises(BlockingIOError):
                        budget.lock(waiter, wait=False)
                    self.assertLess(time.monotonic() - began, .1)
            finally:
                holder.terminate(); holder.wait(); holder.stdout.close()

    def test_owned_child_group_killed_with_cleanup_inside_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / 'child.pid'
            program = ('import subprocess,sys,time,pathlib; '
                       'p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(20)"]); '
                       'pathlib.Path(sys.argv[1]).write_text(str(p.pid)); time.sleep(20)')
            began = time.monotonic()
            with self.assertRaises((BudgetExpired, subprocess.TimeoutExpired)):
                with Budget(.6) as budget:
                    budget.run([sys.executable, '-c', program, str(pidfile)])
            self.assertLess(time.monotonic() - began, .95)
            child = int(pidfile.read_text())
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try: os.kill(child, 0)
                except ProcessLookupError: break
                time.sleep(.02)
            else: self.fail('owned descendant survived deadline cleanup')

    def test_hard_cleanup_deadline(self):
        began = time.monotonic()
        with self.assertRaises(BudgetExpired):
            with Budget(.3) as budget:
                try: time.sleep(2)
                finally:
                    with budget.cleanup(): time.sleep(2)
        self.assertLess(time.monotonic() - began, .6)


class ScopeTests(unittest.TestCase):
    def test_detached_demo_server_registered_before_account_setup(self):
        with tempfile.TemporaryDirectory(prefix='points-deadline-test.') as directory:
            work = Path(directory)
            script = ('import importlib.util,time; from pathlib import Path; '
                      's=importlib.util.spec_from_file_location("ledger", "scripts/demo/ledger.py"); '
                      'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
                      'm.Client.post=lambda *a,**k:time.sleep(20); m.start(Path(__import__("sys").argv[1]))')
            owned_pid = None
            with self.assertRaises((BudgetExpired, subprocess.TimeoutExpired)):
                with Budget(3) as budget:
                    try:
                        budget.run([sys.executable, '-c', script, directory], cwd=ROOT)
                    finally:
                        metadata = work / 'ledger.json'
                        if metadata.exists():
                            import json
                            owned_pid = json.loads(metadata.read_text())['pid']
                        with budget.cleanup():
                            stopped = budget.run([sys.executable, str(ROOT / 'scripts/demo/ledger.py'), 'stop', '--dir', directory], capture_output=True)
                            self.assertEqual(stopped.returncode, 0)
            self.assertIsNotNone(owned_pid, 'detached fixture ownership was not recorded')
            self.assertFalse((work / 'ledger.json').exists())
            limit = time.monotonic() + 1
            while time.monotonic() < limit:
                try: os.kill(owned_pid, 0)
                except ProcessLookupError: break
                time.sleep(.02)
            else: self.fail('detached fixture survived deadline cleanup')

    def test_no_implicit_all_and_invalid_selection(self):
        with patch.dict(os.environ, {}, clear=True), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error: measure.main([])
            self.assertEqual(error.exception.code, 2)
            self.assertEqual(measure.main(['--only', ',']), 2)
            with self.assertRaises(SystemExit): measure.main(['--all', '--only', 'ipad'])

    def test_chapter_single_lane_reuses_current_without_fixture(self):
        with patch.dict(os.environ, {'SOP_PERF_PLATFORM': 'ipad'}), \
             patch.object(measure, 'lane_digest', return_value='current') as digest, \
             patch.object(measure, 'recorded', return_value='current'), \
             patch.object(Budget, 'run', side_effect=AssertionError('fixture or resource sampler started')), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(measure.main([]), 0)
            digest.assert_called_once_with('ipad')


if __name__ == '__main__':
    unittest.main()
