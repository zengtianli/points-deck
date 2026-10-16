"""Second, owned native account session, inside the original coordinator's lane lease.

This reuses the round5 peer fixture without injecting a cookie or login state.
It never shuts down or takes ownership of an unrelated simulator.
"""
from pathlib import Path
import json
import os
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/accept"))
import platform_ui as lane
from bounded import Budget


def main():
    mode, private, receipt, output, runner_path = sys.argv[1:]
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    out.chmod(0o700)
    connection = json.loads(Path(private).read_text())
    connection["qa"]["MODE"] = mode
    runner = json.loads(Path(runner_path).read_text())
    platform = runner["platform"]
    app = lane.app_sop.load_apps("points-deck-ios")[0]
    cfg = app["sop"]["platforms"][platform]["simulator"]
    before = lane.sim_lane.simulator_app_pids()
    device = None
    admission = lane.sim_lane._chapter_sim_admission()
    if admission is None:
        raise lane.sim_lane.Busy("original simulator ownership protection unavailable")
    with Budget(200), admission.hooked(lane.sim_lane, label="points-deck-ios native account peer"):
        try:
            built = lane.sim_lane.reuse_build(Path(receipt), "points-deck-ios", ROOT, platform, "PointsDeck", "Release", False)
            # The coordinator's primary native device is intentionally running
            # under the same lane lease. A second device is needed to test real
            # native session invalidation; retain the canonical CPU/memory gate.
            reason = lane.sim_lane.machine_busy(lane.sim_lane.max_load_default()) or lane.sim_lane.memory_tight()
            if reason:
                raise lane.sim_lane.Busy(reason)
            holder = lane.sim_lane.Lock(lane.sim_lane.LOCK_DIR, "points-account-peer-probe").record() or {}
            ledger = admission.read_ledger()
            primary = lane.sim_lane.booted_udids()
            if (len(primary) != 1 or not holder.get("pid") or any(
                    ledger.get(udid, {}).get("pid") != holder["pid"]
                    or not admission.holder_alive(lane.sim_lane, ledger[udid])
                    or not admission.same_boot(lane.sim_lane, udid, ledger[udid]) for udid in primary)):
                raise lane.sim_lane.Busy("the coordinator's sole live primary simulator cannot be verified; leave all devices untouched")
            device = lane.sim_lane.ensure_device(platform, cfg["device_type"], "Points Account Peer")["udid"]
            lane.sim_lane.boot(device, 120)
            lane.sim_lane.simctl("install", device, built["app_path"])
            lane.run_tests(runner, device, connection, out, "testAccountPasswordLogin")
            if lane.sim_lane.simulator_app_pids() - before:
                raise RuntimeError("unexpected Simulator.app")
            (out / "proof.json").write_text(json.dumps({"ok": True, "mode": mode, "native_device": device,
                "test_sha256": runner["test_sha256"], "receipt_sha256": lane.sim_lane.sha256(Path(receipt)),
                "cookie_injected": False, "credential_entry": "actual native password form" if mode == "PeerStart"
                else "none; existing native session launch"}, indent=2))
        finally:
            if device:
                with lane.run_budget().cleanup():
                    lane.sim_lane.shutdown(device)


if __name__ == "__main__":
    try:
        main()
    except lane.sim_lane.Busy as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(75)
