#!/usr/bin/env python3
"""Does the iPhone (compact) UI still render exactly as the recorded demo? Same data, two builds, pixel diff.

    ~/Dev/.venv/bin/python scripts/media/compact_unchanged.py [--base HEAD] [--out DIR] [--record]

The App Store preview video and the iPhone screenshots show the compact layout. Since 2026-10-02 the same target also
draws the wide layout (iPad / Mac / Vision Pro) and ships a Watch app, so every UI change has to show that the compact
screens did not move. This builds the --base commit (default HEAD: the source the existing media were last reviewed
against) and the current working tree through the shared sim_lane (copies outside the repo, unsigned simulator
builds), starts the isolated demo ledger (scripts/demo/ledger.py), and on one iPhone 17 Pro simulator (shared lock,
load gate, headless, status bar pinned to 9:41) renders six screens for each build from a fresh install: login,
ledger, trend, shop, account and the parent sheet. Screens are compared pixel by pixel; a screen passes when it is
identical, or when every differing pixel lies in the system-drawn status bar / Dynamic Island band at the top and no
channel differs by more than 2 (the clock and island are drawn by the simulator, not the app).

--record keeps the report as perf/media/compact-unchanged.json and appends the result to the media provenance
(sop.media_meta) under ui_reviews, bound to the sop.ui source snapshot Chapter computes, so a later release can cite
it in reused_for. Exit 0 unchanged, 1 changed or failed,
75 simulator lock held / machine loaded (run again later).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP_ID = "points-deck-ios"
BUNDLE = "cyou.tianli.pointsdeck"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane  # noqa: E402

PY = str(Path.home() / "Dev/.venv/bin/python")
SCREENS = [("login", None), ("deck", ["-tab", "0"]), ("trend", ["-tab", "1"]), ("shop", ["-tab", "2"]),
           ("account", ["-tab", "3"]), ("parent", ["-tab", "0", "-parent", "1"])]
TOP_BAND = 0.055      # status bar + Dynamic Island on a 2622-px-tall iPhone 17 Pro shot (≈ 144 px); simulator-drawn
MAX_TOP_DIFF = 2


def sha(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ui_snapshot() -> dict:
    sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
    import app_sop  # noqa: E402  (the snapshot Chapter's media check reads sop.ui through)
    app = app_sop.load_apps(APP_ID)[0]
    snap = app_sop.app_source_snapshot(app, app["sop"]["ui"])
    return {"globs": app["sop"]["ui"], "sha256": snap["sha256"], "file_count": snap["file_count"]}


def build(src: Path, work: Path) -> dict:
    return sim_lane.build(src, "PointsDeck", "iphone", "Release", work)


def shots(udid: str, s, app: Path, args: list[str], out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    s.install(app)
    hashes = {}
    for name, extra in SCREENS:
        launch = args[:2] if extra is None else [*args, *extra]   # login: ledger address only, no dev login
        sim_lane.simctl("launch", "--terminate-running-process", udid, BUNDLE, *launch, timeout=120)
        time.sleep(9)     # base builds predate the lane-ready log; the same fixed wait for both sides
        a, b = out / f".{name}.a.png", out / f"{name}.png"
        s.shot(a)
        for _ in range(8):
            time.sleep(1.2)
            s.shot(b)
            if sim_lane.Frame(b, "iphone").diff(sim_lane.Frame(a, "iphone")) <= 0.0005:
                break
            shutil.copyfile(b, a)
        a.unlink(missing_ok=True)
        hashes[name] = sha(b)
        s.terminate(BUNDLE)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    return hashes


def compare(a: Path, b: Path) -> dict:
    from PIL import Image, ImageChops
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return {"identical": False, "ok": False, "why": f"size {ia.size} vs {ib.size}"}
    diff = ImageChops.difference(ia, ib)
    bbox = diff.getbbox()
    if bbox is None:
        return {"identical": True, "ok": True, "diff_pixels": 0}
    gray = diff.convert("L")
    pixels = sum(1 for v in gray.getdata() if v)
    top = int(ia.size[1] * TOP_BAND)
    below = diff.crop((0, top, ia.size[0], ia.size[1])).getbbox()
    peak = max(hi for _, hi in diff.getextrema())
    ok = below is None and peak <= MAX_TOP_DIFF
    return {"identical": False, "ok": ok, "diff_pixels": pixels, "diff_bbox": list(bbox), "max_channel_diff": peak,
            "why": None if ok else ("differs below the status band" if below else f"status band differs by {peak}")}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="HEAD", help="git revision the existing media were last reviewed against")
    ap.add_argument("--out", type=Path, help="keep screenshots and report here (outside the repo); default a temp dir")
    ap.add_argument("--record", action="store_true", help="append the result to the media provenance ui_reviews")
    a = ap.parse_args(argv)
    base = subprocess.run(["git", "-C", str(REPO), "rev-parse", a.base], capture_output=True, text=True, check=True).stdout.strip()
    work = Path(tempfile.mkdtemp(prefix="points-compact."))
    out = (a.out or work / "out").expanduser().resolve()
    if out == REPO or out.is_relative_to(REPO):
        print("--out 必须在仓外", file=sys.stderr)
        return 2
    before_ui = ui_snapshot()
    started = dt.datetime.now().astimezone()
    try:
        src_base = work / "base-src"
        src_base.mkdir()
        tar = subprocess.run(["git", "-C", str(REPO), "archive", base], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", str(src_base)], input=tar, check=True)
        built = {"base": build(src_base, work / "base"), "current": build(REPO, work / "current")}
        r = subprocess.run([PY, str(REPO / "scripts/demo/ledger.py"), "start", "--dir", str(work / "ledger"), "--json"],
                           capture_output=True, text=True, timeout=600)
        if r.returncode:
            raise SystemExit(f"演示账本没起来：{(r.stderr or r.stdout)[-300:]}")
        ledger = json.loads(r.stdout)
        args = ["-api_base", ledger["url"], "-dev_user", ledger["user"], "-dev_pw", ledger["pw"]]
        dev = sim_lane.ensure_device("iphone", "iPhone-17-Pro")
        hashes = {}
        try:
            with sim_lane.Session("iphone", dev["udid"], label="points compact_unchanged") as s:
                sim_lane.simctl("status_bar", dev["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                                "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                                "--batteryState", "charged", "--batteryLevel", "100", check=False)
                for side in ("base", "current"):
                    hashes[side] = shots(dev["udid"], s, Path(built[side]["app_path"]), args, out / side)
        finally:
            subprocess.run([PY, str(REPO / "scripts/demo/ledger.py"), "stop", "--dir", str(work / "ledger")], capture_output=True)
    except sim_lane.Busy as exc:
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    after_ui = ui_snapshot()
    screens = {name: {**compare(out / "base" / f"{name}.png", out / "current" / f"{name}.png"),
                      "base_sha256": hashes["base"][name], "current_sha256": hashes["current"][name]}
               for name, _ in SCREENS}
    unchanged = all(v["ok"] for v in screens.values()) and before_ui["sha256"] == after_ui["sha256"]
    report = {"schema_version": 1, "app": APP_ID, "checked_at": started.isoformat(timespec="seconds"),
              "base_commit": base, "ui_source": before_ui, "ui_source_unchanged_during_check": before_ui == after_ui,
              "device": f"{dev['name']} ({dev['device_type']}) / {dev['runtime'].rsplit('.', 1)[-1]} simulator",
              "builds": {k: {x: v.get(x) for x in ("version", "build", "executable_sha256", "sdk")} for k, v in built.items()},
              "data": "isolated demo ledger (scripts/demo/ledger.py), same fixture for both builds, status bar 9:41",
              "rule": f"identical, or differences only in the top {TOP_BAND:.1%} (status bar / Dynamic Island) "
                      f"with max channel diff <= {MAX_TOP_DIFF}",
              "screens": screens, "unchanged": unchanged}
    (out / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if a.record:
        record(report, out / "summary.json")
    shutil.rmtree(work / "base", ignore_errors=True)
    shutil.rmtree(work / "current", ignore_errors=True)
    print(json.dumps({"unchanged": unchanged, "out": str(out),
                      "screens": {k: ("identical" if v.get("identical") else "ok" if v["ok"] else v.get("why"))
                                  for k, v in screens.items()}}, ensure_ascii=False))
    return 0 if unchanged else 1


def record(report: dict, summary: Path) -> None:
    import yaml
    kept = REPO / "perf/media/compact-unchanged.json"
    kept.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(summary, kept)
    summary = kept
    sop = (yaml.safe_load((REPO / "project.yaml").read_text(encoding="utf-8")) or {}).get("sop") or {}
    meta = (REPO / sop["media_meta"]).resolve()
    doc = json.loads(meta.read_text(encoding="utf-8"))
    doc.setdefault("ui_reviews", []).append({
        "checked_at": report["checked_at"], "base_commit": report["base_commit"],
        "ui_source_sha256": report["ui_source"]["sha256"], "ui_source_globs": report["ui_source"]["globs"],
        "unchanged": report["unchanged"], "device": report["device"], "rule": report["rule"],
        "screens": {k: ("identical" if v.get("identical") else
                        f"{v.get('diff_pixels')} px in status band, max {v.get('max_channel_diff')}" if v["ok"] else v.get("why"))
                    for k, v in report["screens"].items()},
        "current_sha256": {k: v["current_sha256"] for k, v in report["screens"].items()},
        "report": "01-源程序/perf/media/compact-unchanged.json", "report_sha256": sha(summary),
        "tool": "01-源程序/scripts/media/compact_unchanged.py"})
    meta.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
