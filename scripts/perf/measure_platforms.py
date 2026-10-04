#!/usr/bin/env python3
"""Growth Treasury resource measurement for every platform lane (Chapter sop.measure.command).

    ~/Dev/.venv/bin/python scripts/perf/measure_platforms.py --only iphone,watch [--force] [--budget-min 50]

One isolated demo ledger (scripts/demo/ledger.py: real server.py on a random 127.0.0.1 port, scratch data dir,
synthetic account) serves every run. Every launch gets -api_base; the dev login (-dev_user / -dev_pw) goes only on the
discarded first launch after install (platform_measure --warmup-arg), so the timed launches are the app's real reopen
with the stored session up to its first data-bearing screen, not a fresh sign-in each time (that adds ~450 ms of
server-side password hashing, 2026-10-02). The legacy iPhone step times SpringBoard's scene markers, which a sign-in
does not move, and keeps the login on every launch. Steps, each skipped when its evidence already binds the current input:
  legacy  scripts/perf/sim_measure.py → perf/simulator.json (Chapter's iOS perf/budget/speed items read it through
          perf/lightweight.json; bound to sop.source)
  lanes   the shared app-lightweight platform_measure.py → perf/platforms/<lane>.json (bound to
          `app_sop.py lane-inputs`), order iphone, ipad, watch, mac, vision (Vision boots heaviest, last)
Simulators go through the shared sim_lane lock and load gate (one simulator on this Mac at a time) and are always
shut down; the Mac lane launches quietly (sim_lane: open -g -j + the app's -lane_quiet — no window on screen, no Dock
icon), so like the simulators it runs while the owner works.
Exit 0 all current, 75 something deferred (lock held, machine loaded, owner active, or the time budget below ran out;
Chapter runs the same input again and only the missing steps are measured), 1 a step failed.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts/accept'))
from bounded import Budget, BudgetExpired, current as run_budget
APP_ID = "points-deck-ios"
LANES = ("iphone", "ipad", "watch", "mac", "vision")
ENGINE = Path.home() / "Apps/chapter/engine/app_sop.py"
PLATFORM_MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"
PY = str(Path.home() / "Dev/.venv/bin/python") if (Path.home() / "Dev/.venv/bin/python").exists() else sys.executable
DEFER = 75


def lane_digest(lane: str) -> str | None:
    r = run_budget().run([PY, str(ENGINE), "lane-inputs", "--app", APP_ID, "--platform", lane, "--json"],
                       capture_output=True, timeout=300)
    try:
        return json.loads(r.stdout).get("input_sha256") if r.returncode == 0 else None
    except ValueError:
        return None


def recorded(path: Path) -> str | None:
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("input_sha256")
    except (OSError, ValueError, AttributeError):
        return None


def legacy_digest() -> str | None:
    sys.path.insert(0, str(ENGINE.parent))
    import app_sop  # noqa: E402  (the binding Chapter verifies for perf/simulator.json)
    app = app_sop.load_apps(APP_ID)[0]
    return app_sop.app_source_snapshot(app, app["sop"]["source"])["sha256"]


def main(argv=None) -> int:
    started = time.monotonic()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default=os.environ.get("SOP_PERF_PLATFORM"),
                    help="comma-separated steps: legacy and/or lane ids; Chapter single-lane contract via SOP_PERF_PLATFORM")
    ap.add_argument("--force", action="store_true", help="measure even when the evidence binds the current input")
    ap.add_argument("--all", action="store_true", help="explicitly select legacy plus every platform")
    ap.add_argument("--postboot-load-wait", type=float, default=180)
    ap.add_argument("--warmup-settle", type=float, default=0)
    ap.add_argument("--budget-min", type=float, default=50.0,
                    help="total minutes, including input checks, waiting, child work and cleanup")
    a = ap.parse_args(argv)
    if a.all and a.only:
        ap.error('choose --all or --only, not both')
    if not a.all and not a.only:
        ap.error('select --only PLATFORM (or explicit --all); no default fleet measurement')
    import math
    if any(not math.isfinite(v) or v < 0 for v in (a.postboot_load_wait, a.warmup_settle)):
        ap.error('setup waits must be finite and nonnegative')
    try:
        with Budget(a.budget_min * 60, started):
            result = measure_selected(a)
            run_budget().timeout(1, cleanup=True)
            return result
    except (BudgetExpired, subprocess.TimeoutExpired):
        print(json.dumps({'ok': False, 'deferred': True, 'reason': 'total time budget exhausted',
                          'elapsed_seconds': round(time.monotonic() - started, 3)}))
        return DEFER
    except ValueError as error:
        ap.error(str(error))


def measure_selected(a):
    steps = ["legacy", *LANES]
    if a.only:
        wanted = [s.strip() for s in a.only.split(",") if s.strip()]
        if not wanted:
            print('--only requires at least one platform', file=sys.stderr)
            return 2
        unknown = [s for s in wanted if s not in steps]
        if unknown:
            print(f"未知步骤 {unknown}（可选 {', '.join(steps)}）", file=sys.stderr)
            return 2
        steps = [s for s in steps if s in wanted]
    todo = []
    for step in steps:
        current = legacy_digest() if step == "legacy" else lane_digest(step)
        path = REPO / ("perf/simulator.json" if step == "legacy" else f"perf/platforms/{step}.json")
        if current and recorded(path) == current and not a.force:
            print(f"＝ {step}: 证据已绑定当前输入 {current[:8]}…，跳过", flush=True)
        else:
            todo.append(step)
    if not todo:
        print(json.dumps({"ok": True, "measured": [], "skipped": steps}, ensure_ascii=False))
        return 0
    results: dict[str, int | str] = {}
    with tempfile.TemporaryDirectory(prefix="points-measure.") as scratch:
        try:
            r = run_budget().run([PY, str(REPO / "scripts/demo/ledger.py"), "start", "--dir", scratch, "--json"],
                                 capture_output=True, timeout=600)
            if r.returncode:
                return r.returncode if r.returncode in (DEFER, 78) else 1
            ledger = json.loads(r.stdout)
            base = ["-api_base", ledger["url"]]
            login = ["-dev_user", ledger["user"], "-dev_pw", ledger["pw"]]
            for step in todo:
                run_budget().timeout(600)
                if step == "legacy":
                    cmd = [PY, str(REPO / "scripts/perf/sim_measure.py"), *[f"--launch-arg={x}" for x in base + login]]
                else:
                    cmd = [PY, str(PLATFORM_MEASURE), "--app", APP_ID, "--platform", step, "--repo", str(REPO),
                           *[f"--launch-arg={x}" for x in base], *[f"--warmup-arg={x}" for x in login]]
                    if step == "ipad":
                        cmd += ["--postboot-load-wait", str(a.postboot_load_wait),
                                "--warmup-settle", str(a.warmup_settle)]
                print(f"→ {step}", flush=True)
                env = {**os.environ, "SIM_LANE_LABEL": f"points measure_platforms {step}"}
                proc = run_budget().run(cmd, cwd=REPO, env=env, stdin=subprocess.DEVNULL,
                                        timeout=run_budget().remaining())
                results[step] = proc.returncode
                print(f"← {step}: 退出码 {proc.returncode}", flush=True)
                if proc.returncode:
                    break
        finally:
            with run_budget().cleanup():
                run_budget().run([PY, str(REPO / "scripts/demo/ledger.py"), "stop", "--dir", scratch],
                                 capture_output=True, timeout=10)
    failed = [s for s, c in results.items() if isinstance(c, int) and c not in (0, DEFER)]
    deferred = [s for s, c in results.items() if c == DEFER or isinstance(c, str)]
    print(json.dumps({"ok": not failed and not deferred, "results": results, "failed": failed, "deferred": deferred},
                     ensure_ascii=False))
    return 1 if failed else DEFER if deferred else 0


if __name__ == "__main__":
    sys.exit(main())
