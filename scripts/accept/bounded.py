"""Deadline and owned-process cleanup for the existing Points acceptance CLIs."""
import contextlib
import contextvars
import fcntl
import math
import os
import signal
import subprocess
import time

ACTIVE = contextvars.ContextVar('points_run_budget', default=None)


class BudgetExpired(RuntimeError):
    pass


class Budget:
    def __init__(self, seconds, started=None):
        if not math.isfinite(seconds) or seconds <= 0:
            raise ValueError('time budget must be finite and positive')
        self.started = time.monotonic() if started is None else started
        self.deadline = self.started + seconds
        self.reserve = min(10, seconds * .1)
        self.cleaning = False

    def remaining(self, cleanup=False):
        end = self.deadline if cleanup or self.cleaning else self.deadline - self.reserve
        return max(0, end - time.monotonic())

    def timeout(self, ceiling, cleanup=False):
        left = self.remaining(cleanup)
        if left <= 0:
            raise BudgetExpired('Points total time budget exhausted')
        return min(ceiling, left)

    def _expired(self, *_):
        if not self.cleaning:
            self.cleaning = True
            signal.setitimer(signal.ITIMER_REAL, max(.001, self.remaining(True)))
        raise BudgetExpired('Points total time budget exhausted; retain completed outputs')

    def __enter__(self):
        delay = self.timeout(float('inf'))
        self.token = ACTIVE.set(self)
        self.handler = signal.signal(signal.SIGALRM, self._expired)
        self.entered = time.monotonic()
        self.old_timer = signal.setitimer(signal.ITIMER_REAL, delay)
        return self

    def __exit__(self, *_):
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, self.handler)
        if self.old_timer[0]:
            signal.setitimer(signal.ITIMER_REAL, max(.001, self.old_timer[0] - (time.monotonic() - self.entered)), self.old_timer[1])
        ACTIVE.reset(self.token)

    @contextlib.contextmanager
    def cleanup(self):
        delay = self.timeout(float('inf'), True)
        prior = self.cleaning
        self.cleaning = True
        signal.setitimer(signal.ITIMER_REAL, delay)
        try:
            yield
        finally:
            self.cleaning = prior
            signal.setitimer(signal.ITIMER_REAL, max(.001, self.remaining()))

    def lock(self, stream, wait=True):
        # Never wait indefinitely behind another Codex / SDK / sampler.
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                if not wait:
                    raise
                time.sleep(min(.1, self.timeout(.1)))

    def run(self, args, *, timeout=600, input=None, **kwargs):
        delay = self.timeout(timeout)
        capture = kwargs.pop('capture_output', False)
        check = kwargs.pop('check', False)
        kwargs.setdefault('text', True)
        if capture:
            kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if input is not None:
            kwargs['stdin'] = subprocess.PIPE
        proc = subprocess.Popen(args, start_new_session=True, **kwargs)
        try:
            stdout, stderr = proc.communicate(input, timeout=delay)
        except BaseException:
            # Only the process group created by this call is eligible for cleanup.
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=max(.01, min(1, self.remaining(True))))
                except subprocess.TimeoutExpired:
                    pass
            except (ProcessLookupError, PermissionError):
                if proc.poll() is None:
                    raise
            finally:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    if proc.poll() is None:
                        raise
                proc.wait(timeout=max(.01, min(.5, self.remaining(True))))
            raise
        result = subprocess.CompletedProcess(args, proc.returncode, stdout, stderr)
        if check and result.returncode:
            raise RuntimeError('Points owned command failed; see its log')
        return result


def current():
    budget = ACTIVE.get()
    if budget is None:
        raise RuntimeError('Points run has no total budget')
    return budget
