#!/usr/bin/env python3
"""Growth Treasury (points-deck) iOS simulator resource measurement (Release, isolated headless simulator).

Builds the *current working tree* (the exact files app_sop hashes as sop.source) in a temporary copy,
installs it on a dedicated, windowless simulator, and measures:
  - size: zipped .app (download proxy) and .app bytes (installed proxy) — simulator build, not an IPA;
  - launch: unified-log markers "Requesting launch" -> scene content "ready" / "Dropping launch assertion";
  - idle: shared app-lightweight measure.py (45 s settle, 60 s CPU window, footprint after window).
Writes perf/raw/simulator-full-<date>.json and updates perf/simulator.json only if the source snapshot
is unchanged across the whole run. Never opens Simulator.app, never touches the clipboard or input.

  ~/Dev/.venv/bin/python scripts/perf/sim_measure.py [--runs 5] [--max-load 8] [--min-user-idle 600]
Adapted from ~/Apps/clip/ios/01-源程序/scripts/perf/sim_measure.py; adds the user-idle gate.
"""
import argparse, datetime as dt, hashlib, json, os, plistlib, re, shutil, statistics, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, "/Users/tianli/Apps/chapter/engine")
import app_sop  # noqa: E402  (source snapshot = the binding app_sop verifies)

MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/measure.py"
MACAPP = Path.home() / "Dev/tools/dev/lib/tools/macapp"
DEVICE_NAME, DEVICE_TYPE = "PointsDeck Perf iPhone 17 Pro", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
BUNDLE = "cyou.tianli.pointsdeck"


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def snapshot():
    app = app_sop.load_apps("points-deck-ios")[0]
    return app_sop.app_source_snapshot(app, app["sop"]["source"])


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def device():
    data = json.loads(sh(["xcrun", "simctl", "list", "devices", "-j"]))
    for d in data["devices"].get(RUNTIME, []):
        if d["name"] == DEVICE_NAME and d["isAvailable"]:
            return d["udid"]
    return sh(["xcrun", "simctl", "create", DEVICE_NAME, DEVICE_TYPE, RUNTIME]).strip()


def build(work):
    shutil.copytree(REPO, work, ignore=shutil.ignore_patterns(".git", "build", ".dd*", "perf", "shots", "archived",
                                                              "verification", "PointsDeck.xcodeproj", "*.xcresult"))
    script = f"""set -e
source {MACAPP}/xcode_env.sh && xcode_env_use iphonesimulator >/dev/null
source {MACAPP}/scrub_env.sh
cd "{work}" && xcodegen generate --spec project.yml >/dev/null
scrub_env_run xcodebuild -project PointsDeck.xcodeproj -scheme PointsDeck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "{work}/dd" \
  CODE_SIGNING_ALLOWED=NO build >"{work}/build.log" 2>&1 || {{ tail -30 "{work}/build.log"; exit 1; }}
echo "$XCODE_ENV_NAME"
"""
    t = time.time()
    xcode = sh(["/bin/bash", "-c", script]).strip().splitlines()[-1]
    app = next((work / "dd/Build/Products/Release-iphonesimulator").glob("PointsDeck.app"))
    return app, round(time.time() - t, 1), xcode


def log_markers(udid, start, pid):
    out = sh(["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "json", "--start", start, "--predicate",
              f'eventMessage CONTAINS "{BUNDLE}" OR eventMessage CONTAINS "app<{BUNDLE}>"'])
    rows = [{"timestamp": e["timestamp"], "process": Path(e.get("processImagePath", "")).name, "message": e["eventMessage"]}
            for e in json.loads(out or "[]")]
    def at(pred):
        hit = next((r for r in rows if pred(r)), None)
        return dt.datetime.strptime(hit["timestamp"][:26], "%Y-%m-%d %H:%M:%S.%f") if hit else None
    req = at(lambda r: r["message"].startswith(f"Requesting launch of {BUNDLE}"))
    ready = at(lambda r: f"sceneID:{BUNDLE}-default] scene content state changed: ready" in r["message"])
    done = at(lambda r: r["process"] == "SpringBoard" and f"[app<{BUNDLE}>:{pid}] Dropping launch assertion" in r["message"])
    ms = lambda a: round((a - req).total_seconds() * 1000, 1) if a and req else None
    keep = [r for r in rows if any(k in r["message"] for k in ("Requesting launch", "Launch successful", "content state changed: ready", "Dropping launch assertion"))]
    return ms(ready), ms(done), keep


def user_idle_s():
    out = sh(["ioreg", "-c", "IOHIDSystem"])
    m = re.search(r'"HIDIdleTime" = (\d+)', out)
    return int(m.group(1)) / 1e9 if m else 0.0


def settle_gate(limit, stage, wait_s=600):
    deadline = time.time() + wait_s
    while os.getloadavg()[0] > limit:
        if time.time() > deadline:
            sys.exit(f"{stage}负载 {os.getloadavg()[0]:.1f} 在 {wait_s}s 内未降到 {limit} 以下，未测量")
        time.sleep(10)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--max-load", type=float, default=12.0, help="1-min load average required before measuring starts")
    ap.add_argument("--min-user-idle", type=float, default=600.0,
                    help="app-lightweight idle gate: seconds without keyboard/mouse input before measuring starts")
    ap.add_argument("--abort-load", type=float, default=40.0,
                    help="reject the sample if the 1-min load exceeds this during timing/idle (gross host contamination)")
    a = ap.parse_args()
    idle_s = user_idle_s()
    if idle_s < a.min_user_idle:
        sys.exit(f"用户 {idle_s:.0f}s 前仍有操作，未满 {a.min_user_idle:.0f}s 空闲门，未测量")
    settle_gate(a.max_load, "开测前", 900)
    load = os.getloadavg()
    before = snapshot()
    started = dt.datetime.now().astimezone()
    work = Path(tempfile.mkdtemp(prefix="points-sim-measure."))
    udid = None
    try:
        app, build_s, xcode = build(work / "src")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        version = f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
        zip_path = work / "PointsDeck.app.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(zip_path)], check=True)
        installed = sum(f.stat().st_size for f in app.rglob("*") if f.is_file() and not f.is_symlink())
        udid = device()
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, capture_output=True)
        # A freshly created iOS 27 simulator spends minutes on first-boot work (load > 300 seen 2026-09-29);
        # timing launches during that window measures the host, not the app.
        settle_gate(a.max_load, "开机后")
        subprocess.run(["xcrun", "simctl", "uninstall", udid, BUNDLE], capture_output=True)
        subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True)
        samples = []
        load_mid = os.getloadavg()
        for run in range(a.runs + 1):  # run 0 = first launch after install, discarded
            subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
            time.sleep(3)
            start = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            out = sh(["xcrun", "simctl", "launch", udid, BUNDLE])
            pid = int(out.strip().split(":")[-1])
            time.sleep(5)
            ready, done, lines = log_markers(udid, start, pid)
            samples.append({"run": run, "pid": pid, "request_to_ready_ms": ready, "request_to_launch_complete_ms": done, "markers": lines})
        load_after_launch = os.getloadavg()
        if max(load_after_launch[0], load_mid[0]) > a.abort_load:
            sys.exit(f"启动计时期间负载 {load_mid[0]:.1f}/{load_after_launch[0]:.1f} 超过 {a.abort_load}，样本作废，未写入")
        kept = [s for s in samples[1:] if s["request_to_ready_ms"] and s["request_to_launch_complete_ms"]]
        if len(kept) < a.runs:
            sys.exit(f"启动标记不全：{len(kept)}/{a.runs} 次有效")
        ready_med = round(statistics.median(s["request_to_ready_ms"] for s in kept), 1)
        done_med = round(statistics.median(s["request_to_launch_complete_ms"] for s in kept), 1)
        # idle: fresh launch, settle 45 s, 60 s CPU window via shared measure.py
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
        time.sleep(3)
        pid = int(sh(["xcrun", "simctl", "launch", udid, BUNDLE]).strip().split(":")[-1])
        time.sleep(45)
        idle_load = os.getloadavg()
        if idle_load[0] > a.abort_load:
            sys.exit(f"空闲采样前 1 分钟负载 {idle_load[0]:.1f} > {a.abort_load}，样本作废，未写入")
        idle_out = sh([sys.executable, str(MEASURE), "idle", str(pid), "--seconds", "60"])
        idle = json.loads(idle_out[idle_out.index("{"):idle_out.rindex("}") + 1])["idle"]
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    finally:
        if udid:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    after = snapshot()
    if after["sha256"] != before["sha256"]:
        shutil.rmtree(work, ignore_errors=True)
        sys.exit("测量期间源码输入变化，未写入证据")
    host = sh(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
    model = sh(["sysctl", "-n", "hw.model"]).strip()
    macos = sh(["sw_vers", "-productVersion"]).strip()
    stamp = started.strftime("%Y%m%d")
    raw_rel = f"perf/raw/simulator-full-{stamp}.json"
    raw = {"schema_version": 1, "app_id": "points-deck-ios", "environment": "simulator", "mode": "full",
           "measured_at": started.isoformat(), "completed_at": dt.datetime.now().astimezone().isoformat(),
           "version": version, "configuration": "Release", "bundle_id": BUNDLE,
           "binary_sha256": sha(app / "PointsDeck") if (app / "PointsDeck").exists() else None,
           "build_receipt": {"configuration": "Release", "seconds": build_s, "xcode": xcode, "source_sha256": before["sha256"],
                             "source_file_count": before["file_count"], "source_dirty": before["dirty"], "git_head": before["commit"],
                             "built_from": "working-tree copy (exactly the files app_sop hashes as sop.source)", "source_unchanged": True},
           "simulator_device": "iPhone 17 Pro", "simulator_os": "iOS 27.0", "simulator_udid": udid,
           "host": f"{model} / {host} / macOS {macos}", "load_average_at_start": list(load), "load_average_before_launches": list(load_mid),
           "load_average_after_launches": list(load_after_launch), "load_average_before_idle": list(idle_load),
           "load_gates": {"start_max": a.max_load, "abort_above": a.abort_load},
           "measurement_tool_sha256": sha(MEASURE), "probe_sha256": sha(__file__),
           "scope": "Simulator App process only; excludes CoreSimulator, Simulator GUI, system services and inactive extensions",
           "launch": {"samples": samples, "discarded_runs": 1, "runs": len(kept), "ready_median_ms": ready_med,
                      "launch_complete_median_ms": done_med,
                      "method": "Simulator unified log: CoreSimulatorBridge \"Requesting launch of <bundle>\" -> SpringBoard scene content state \"ready\" / SpringBoard \"Dropping launch assertion\". App terminated 3 s before each run; first run after install discarded."},
           "size": {"download_bytes": zip_path.stat().st_size, "installed_bytes": installed,
                    "kind": "Local simulator Release .app ZIP / .app bytes; not an App Store IPA or device slice"},
           "idle": {**idle, "settle_s": 45}, "source_unchanged_during_measurement": True}
    (REPO / raw_rel).write_text(json.dumps(raw, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    shutil.rmtree(work, ignore_errors=True)

    sim_path = REPO / "perf/simulator.json"
    sim = json.loads(sim_path.read_text())
    method = raw["launch"]["method"] + f" Median of {len(kept)} runs."
    sim.update({"version": version, "configuration": "Release", "measured_at": started.isoformat(),
                "device": f"iPhone 17 Pro / iOS 27.0 Simulator / {model} / {host} / macOS {macos}",
                "input_sha256": before["sha256"], "git_head": before["commit"],
                "size": raw["size"],
                "idle": {"process": str(pid), "footprint_mb": idle["footprint_mb"], "cpu_pct": idle["cpu_pct"],
                         "window_s": idle["window_s"], "settle_s": 45,
                         "method": "Shared measure.py: CPU time delta / 60s wall; 3 phys_footprint samples after CPU window, maximum reported",
                         "scope": raw["scope"]},
                "runtime_measurement": {"environment": "simulator", "device": "iPhone 17 Pro", "os": "iOS 27.0", "version": version,
                                        "evidence": raw_rel, "evidence_sha256": sha(REPO / raw_rel)}})
    for entry in sim.get("speed_gui", []):
        entry.update(runs=len(kept), method=method, evidence=raw_rel, evidence_sha256=sha(REPO / raw_rel))
        if entry.get("key") == "first_screen_ready":
            entry["median_ms"] = ready_med
        elif entry.get("key") == "launch_complete":
            entry["median_ms"] = done_med
    sim_path.write_text(json.dumps(sim, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"version": version, "input_sha256": before["sha256"], "size": raw["size"], "idle": idle,
                      "ready_median_ms": ready_med, "launch_complete_median_ms": done_med, "evidence": raw_rel}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
