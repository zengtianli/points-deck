#!/usr/bin/env python3
"""Capture the real five views from a source-verified Release App in the canonical lane.

One simulator boot, real stored-session reopens, isolated server only. Mac stays
offscreen with no Dock tile. Captures are evidence for review, not an automatic
claim that every sheet/input or platform delivery requirement passed.
"""
from pathlib import Path
import argparse
import fcntl
import json
import shutil
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(Path.home() / "Apps/chapter/engine"),
                 str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios")]
import app_sop
import sim_lane


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--platform", choices=("ipad", "mac", "vision"), required=True)
    ap.add_argument("--receipt", type=Path, required=True)
    ap.add_argument("--connection", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    if __import__("os").environ.get("SOP_OWNER_NOW") == "1":
        raise ValueError("original admission cannot be overridden")
    built = sim_lane.reuse_build(a.receipt, "points-deck-ios", REPO, a.platform, "PointsDeck", "Release", False)
    ledger = json.loads(a.connection.read_text())
    if not ledger["url"].startswith("http://127.0.0.1:"):
        raise ValueError("only the isolated local ledger is allowed")
    app = app_sop.load_apps("points-deck-ios")[0]
    before = app_sop.lane_inputs(app, a.platform)["input_sha256"]
    a.out.mkdir(parents=True, exist_ok=True)
    records = []
    def arguments(tab):
        args = ["-api_base", ledger["url"], "-tab", str(tab)]
        if tab == 0:
            args += ["-dev_user", ledger["user"], "-dev_pw", ledger["pw"]]
        return args
    try:
        with (app_sop.STATE_DIR / "lock").open("a+") as global_lock:
            fcntl.flock(global_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            gate = app_sop.steady(False, allow_owner_now=False)
            if not gate[0] or not app_sop.on_ac_power():
                raise sim_lane.Busy(gate[1])
            if a.platform == "mac":
                for tab in range(5):
                    result = sim_lane.run_mac_quiet(Path(built["app_path"]),
                        arguments(tab) + ["-lane_window", "760x540"], a.out / f"tab-{tab}.png", 60)
                    if not result["ok"]:
                        raise sim_lane.LaneError(str(result.get("errors")))
                    records.append({"tab": tab, "stored_session": tab > 0,
                                    "quiet": result.get("quiet"), "screenshot": f"tab-{tab}.png"})
            else:
                kind = app["sop"]["platforms"][a.platform]["simulator"]["device_type"]
                device = sim_lane.ensure_device(a.platform, kind)
                with sim_lane.Session(a.platform, device["udid"], label=f"Points actual {a.platform} five views",
                                      lock_wait=0, load_wait=0) as lane:
                    lane.install(Path(built["app_path"]))
                    for tab in range(5):
                        result = lane.launch(built["bundle_id"], arguments(tab), "log", 60, None,
                            sim_lane.bundle_info(Path(built["app_path"]))["executable"],
                            functional_thin=a.platform == "ipad")
                        if result["errors"]:
                            raise sim_lane.LaneError(str(result["errors"]))
                        image = lane.shot(a.out / f"tab-{tab}.png")
                        records.append({"tab": tab, "stored_session": tab > 0, "screenshot": image.name,
                                        "ready_signal": result["ready_signal"], "udid": device["udid"]})
                        lane.terminate(built["bundle_id"])
                    if a.platform == "ipad":
                        previous = sim_lane.simctl("ui", device["udid"], "content_size").stdout.strip()
                        try:
                            sim_lane.simctl("ui", device["udid"], "content_size", "accessibility-extra-extra-extra-large")
                            result = lane.launch(built["bundle_id"], arguments(2), "log", 60, None,
                                sim_lane.bundle_info(Path(built["app_path"]))["executable"], functional_thin=True)
                            if result["errors"]:
                                raise sim_lane.LaneError(str(result["errors"]))
                            lane.shot(a.out / "score-largest-type.png")
                            records.append({"tab": 2, "dynamic_type": "accessibility-extra-extra-extra-large",
                                            "screenshot": "score-largest-type.png"})
                        finally:
                            sim_lane.simctl("ui", device["udid"], "content_size", previous)
            if app_sop.lane_inputs(app, a.platform)["input_sha256"] != before:
                raise sim_lane.LaneError("source changed during actual view capture")
    except (BlockingIOError, sim_lane.Busy) as error:
        print(json.dumps({"ok": False, "deferred": True, "reason": str(error)}, ensure_ascii=False))
        return 75
    proof = {"ok": True, "scope": "real five views, minimum Mac window / largest iPad text, stored-session reopen",
             "platform": a.platform, "environment": "native" if a.platform == "mac" else "simulator",
             "input_sha256": before, "receipt": str(a.receipt.resolve()),
             "receipt_sha256": sim_lane.sha256(a.receipt), "captures": records,
             "limitations": ["interactive sheet controls and system input were not exercised by this capture"]}
    (a.out / "capture.json").write_text(json.dumps(proof, ensure_ascii=False, indent=1) + "\n")
    print(json.dumps({"ok": True, "out": str(a.out), "captures": len(records)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
